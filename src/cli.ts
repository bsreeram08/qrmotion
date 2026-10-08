#!/usr/bin/env node
import { writeFileSync } from 'node:fs';
import { encode, type Ecc } from './qr.js';
import { EFFECTS, EFFECT_NAMES, type EffectName } from './effects.js';
import { toSVG, toTerminal, verify } from './render.js';
import { serveMcp } from './mcp.js';
import { VERSION } from './tool.js';

const HELP = `qrmotion ${VERSION}: animated QR codes where every frame still scans

Usage
  qrmotion <text> [options]     animate in the terminal (Ctrl+C to stop)
  qrmotion mcp                  run as an MCP server over stdio

Options
  -e, --effect <name>   ${EFFECT_NAMES.join(' | ')} (default slide)
      --ecc <L|M|Q|H>   error correction (default Q)
      --ink <#hex>      dark color (default #17132a)
      --paper <#hex>    light color (default #f5f2ea)
      --ink-to <#hex>   second ink color: fills the body with a gradient (SVG only)
      --gradient <k>    linear | radial (default linear)
      --angle <deg>     linear gradient angle (default 45)
      --eye-color <#hex> color of the finder eyes (default ink)
      --eye-shape <k>   square | rounded (default rounded)
      --duration <s>    seconds per loop (default 2.4)
      --svg <file|->    write an animated SVG instead (- for stdout)
      --json            print { version, size, ecc, effect, verified, svg } as JSON
      --once            print a single frame and exit (default when not a TTY)
      --mono            no colors
      --scale <n>       terminal columns per module (default: fit the window)
      --fps <n>         terminal frame rate (default 24)
  -v, --version
  -h, --help

Examples
  qrmotion https://example.com
  qrmotion "hello" -e flip --svg hello.svg
  qrmotion https://example.com --json | jq -r .svg > code.svg`;

function fail(msg: string): never {
  process.stderr.write(`qrmotion: ${msg}\n`);
  process.exit(1);
}

const args = process.argv.slice(2);
const flags: Record<string, string | true> = {};
const positional: string[] = [];
const ALIAS: Record<string, string> = { e: 'effect', v: 'version', h: 'help' };
const BOOL = new Set(['json', 'once', 'mono', 'version', 'help']);
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a.startsWith('-') && a !== '-') {
    let key = a.replace(/^--?/, '');
    let val: string | undefined;
    if (key.includes('=')) [key, val] = [key.slice(0, key.indexOf('=')), key.slice(key.indexOf('=') + 1)];
    key = ALIAS[key] ?? key;
    if (BOOL.has(key)) flags[key] = true;
    else {
      val ??= args[++i];
      if (val === undefined) fail(`--${key} needs a value`);
      flags[key] = val;
    }
  } else positional.push(a);
}

if (flags.help) { process.stdout.write(HELP + '\n'); process.exit(0); }
if (flags.version) { process.stdout.write(VERSION + '\n'); process.exit(0); }
if (positional[0] === 'mcp' && positional.length === 1) { serveMcp(); }
else main();

function num(key: string, def: number): number {
  const v = flags[key];
  if (v === undefined) return def;
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0) fail(`--${key} must be a positive number`);
  return n;
}

function main() {
  const text = positional.join(' ');
  if (!text) { process.stdout.write(HELP + '\n'); process.exit(1); }
  const effect = (flags.effect ?? 'slide') as EffectName;
  if (!(effect in EFFECTS)) fail(`unknown effect "${effect}". Use one of: ${EFFECT_NAMES.join(', ')}`);
  const ecc = String(flags.ecc ?? 'Q').toUpperCase() as Ecc;
  const opts = {
    effect,
    ink: flags.ink as string | undefined,
    paper: flags.paper as string | undefined,
    inkTo: flags['ink-to'] as string | undefined,
    gradient: flags.gradient as 'linear' | 'radial' | undefined,
    angle: flags.angle !== undefined ? Number(flags.angle) : undefined,
    eyeColor: flags['eye-color'] as string | undefined,
    eyeShape: flags['eye-shape'] as 'square' | 'rounded' | undefined,
    duration: num('duration', 2.4),
  };

  let qr;
  try {
    qr = encode(text, ecc);
    if (flags.svg || flags.json) {
      const svg = toSVG(qr, opts);
      if (flags.json) {
        process.stdout.write(JSON.stringify({ version: qr.version, size: qr.size, ecc: qr.ecc, effect, verified: verify(qr, opts, 24).ok, svg }) + '\n');
      }
      if (typeof flags.svg === 'string') {
        if (flags.svg === '-') process.stdout.write(svg + '\n');
        else { writeFileSync(flags.svg, svg); process.stderr.write(`wrote ${flags.svg}\n`); }
      }
      return;
    }
  } catch (e) {
    fail((e as Error).message);
  }

  const color = !flags.mono && !process.env.NO_COLOR;
  if (flags.once || !process.stdout.isTTY) {
    process.stdout.write(toTerminal(qr, { ...opts, color, scale: num('scale', 2) }, 0) + '\n');
    return;
  }

  // Motion is a fraction of a module, so at 2 columns per module it barely shows.
  // Use the biggest scale that fits the window (each module is `scale` columns by scale/2 rows).
  const N = qr.size + 8;
  const fit = Math.min(Math.floor((process.stdout.columns || 80) / N), Math.floor((2 * ((process.stdout.rows || 24) - 1)) / N));
  const scale = flags.scale ? num('scale', 2) : Math.max(2, Math.min(6, fit));
  if (fit < scale) process.stderr.write(`qrmotion: window too small for the full code (needs ${N * scale} columns x ${Math.ceil((N * scale) / 2)} rows). Enlarge it or zoom out.\n`);
  const term = { ...opts, color, scale };

  // alternate screen + cursor home each frame: no scrollback spam, works even if the frame is taller than the window
  const fps = num('fps', 24);
  const start = Date.now();
  const restore = () => { process.stdout.write('\x1b[?25h\x1b[?1049l'); process.exit(0); };
  process.on('SIGINT', restore);
  process.on('SIGTERM', restore);
  process.stdout.write('\x1b[?1049h\x1b[?25l\x1b[2J');
  setInterval(() => {
    process.stdout.write('\x1b[H' + toTerminal(qr, term, (Date.now() - start) / 1000));
  }, 1000 / fps);
}
