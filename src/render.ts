import { encode, isFinder, type Ecc, type QR } from './qr.js';
import { resolveEffect, type Effect, type EffectName } from './effects.js';

export interface RenderOptions {
  /** Built-in effect name or a custom Effect. Default "slide". */
  effect?: EffectName | Effect;
  /** Dark color, #rgb or #rrggbb. Default #17132a. */
  ink?: string;
  /** Light color, #rgb or #rrggbb. Default #f5f2ea. */
  paper?: string;
  /** Seconds per animation cycle. Default 2.4. */
  duration?: number;
  /** Quiet zone in modules. Default 4 (the spec minimum). */
  quiet?: number;
  /** Seed for per-module randomness, so output is reproducible. Default 1. */
  seed?: number;
  /** Second ink color. Set it to fill the body with a gradient from `ink` to `inkTo` (SVG only). Must also be much darker than paper. */
  inkTo?: string;
  /** Gradient shape when `inkTo` is set. Default "linear". */
  gradient?: 'linear' | 'radial';
  /** Linear gradient angle in degrees (0 = left to right, clockwise). Default 45. */
  angle?: number;
  /** Color of the dark parts of the finder eyes. Default `ink`. Must be much darker than paper. */
  eyeColor?: string;
  /** Corner style of the finder eyes. Default "rounded". */
  eyeShape?: 'square' | 'rounded';
}

type RGB = [number, number, number];

/** One filled rounded box, in module units of the full canvas (quiet zone included). */
export interface Shape {
  cx: number;
  cy: number;
  w: number;
  h: number;
  /** Degrees. */
  rot: number;
  /** Corner radius in modules. */
  r: number;
  fill: RGB;
}

interface Resolved {
  effect: Effect;
  ink: RGB;
  paper: RGB;
  inkTo: RGB | null;
  gradient: 'linear' | 'radial';
  angle: number;
  eyeColor: RGB;
  eyeShape: 'square' | 'rounded';
  duration: number;
  quiet: number;
  rand: Float32Array;
}

const DEFAULT_INK = '#17132a', DEFAULT_PAPER = '#f5f2ea';

function resolve(qr: QR, o: RenderOptions = {}): Resolved {
  const effect = resolveEffect(o.effect);
  const ink = parseHex(o.ink ?? DEFAULT_INK), paper = parseHex(o.paper ?? DEFAULT_PAPER);
  const dark = (c: RGB, what: string) => {
    if (luminance(paper) - luminance(c) < 0.4)
      throw new RangeError(`${what} must be much darker than paper (luminance gap of at least 0.4) or the code will not scan`);
    return c;
  };
  dark(ink, 'ink');
  const inkTo = o.inkTo != null ? dark(parseHex(o.inkTo), 'inkTo') : null;
  const eyeColor = o.eyeColor != null ? dark(parseHex(o.eyeColor), 'eyeColor') : ink;
  const gradient = o.gradient ?? 'linear', angle = o.angle ?? 45, eyeShape = o.eyeShape ?? 'rounded';
  const duration = o.duration ?? 2.4, quiet = o.quiet ?? 4;
  if (!(duration > 0)) throw new RangeError('duration must be a positive number of seconds');
  if (!(Number.isInteger(quiet) && quiet >= 0)) throw new RangeError('quiet must be a non-negative integer');
  const rand = new Float32Array(qr.size * qr.size);
  let s = (o.seed ?? 1) >>> 0;
  for (let i = 0; i < rand.length; i++) {
    // mulberry32
    s = (s + 0x6d2b79f5) >>> 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    rand[i] = ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  return { effect, ink, paper, inkTo, gradient, angle, eyeColor, eyeShape, duration, quiet, rand };
}

const frac = (x: number) => ((x % 1) + 1) % 1;

/** Shapes for a single frame at time t (seconds). Paper background is not included. */
export function frameShapes(qr: QR, opts: RenderOptions = {}, t = 0): Shape[] {
  const o = resolve(qr, opts);
  return shapes(qr, o, (phase) => o.effect.pose(frac(t / o.duration + phase)));
}

function shapes(qr: QR, o: Resolved, poseAt: (phase: number) => import('./effects.js').Pose): Shape[] {
  const { size: n, dark, fixed } = qr, q = o.quiet, e = o.effect, mid = (n - 1) / 2;
  const out: Shape[] = [];
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) {
    const i = r * n + c;
    if (!dark[i] || isFinder(qr, r, c)) continue;
    const cx = c + q + 0.5, cy = r + q + 0.5;
    if (fixed[i]) { out.push({ cx, cy, w: 1, h: 1, rot: 0, r: 0, fill: o.ink }); continue; }
    const p = poseAt(e.phase(r, c, Math.hypot(r - mid, c - mid), o.rand[i]));
    const w = e.size * p.sx, h = e.size * p.sy;
    out.push({ cx: cx + p.dx, cy: cy + p.dy, w, h, rot: p.rot, r: e.radius * Math.min(w, h), fill: tint(o.ink, p.hue, p.shade) });
  }
  for (const [r, c] of [[0, 0], [0, n - 7], [n - 7, 0]]) out.push(...eye(r + q, c + q, o));
  return out;
}

function eye(r: number, c: number, o: Resolved): Shape[] {
  // concentric 7/5/3 squares keep the 1:1:3:1:1 finder ratio. "rounded" radii are capped so the
  // corner module centers stay covered and verify() still passes; "square" is radius 0.
  const k = o.eyeShape === 'square' ? 0 : 1;
  const at = (side: number, rad: number, fill: RGB): Shape => ({ cx: c + 3.5, cy: r + 3.5, w: side, h: side, rot: 0, r: rad * k, fill });
  return [at(7, 1, o.eyeColor), at(5, 0.9, o.paper), at(3, 0.7, o.eyeColor)];
}

/** Animated SVG (CSS keyframes). Respects prefers-reduced-motion. */
export function toSVG(qr: QR, opts: RenderOptions & { px?: number } = {}): string {
  const o = resolve(qr, opts), e = o.effect, N = qr.size + o.quiet * 2;
  const px = opts.px ?? N * 8;
  const n = qr.size, q = o.quiet, mid = (n - 1) / 2;
  const animated = e.name !== 'none';
  // unique per output: inline SVG <style> is global in HTML, so two codes on one page would share names
  const id = 'qm' + fnv(`${qr.text}|${qr.ecc}|${e.name}|${opts.ink}|${opts.paper}|${o.duration}|${opts.seed}`);

  // keyframes sampled from the same pose() the canvas and verifier use
  const STEPS = 24;
  let keyframes = '';
  if (animated) {
    let usesColor = false;
    for (let k = 0; k <= STEPS; k++) { const p = e.pose(k / STEPS); if (p.hue || p.shade) usesColor = true; }
    keyframes = `@keyframes ${id}{`;
    for (let k = 0; k <= STEPS; k++) {
      const p = e.pose(k / STEPS);
      keyframes += `${+(k * 100 / STEPS).toFixed(3)}%{transform:translate(${n4(p.dx)}px,${n4(p.dy)}px) rotate(${n4(p.rot)}deg) scale(${n4(p.sx)},${n4(p.sy)})`;
      if (usesColor) keyframes += `;fill:${hex(tint(o.ink, p.hue, p.shade))}`;
      keyframes += '}';
    }
    keyframes += `}.${id}{transform-box:fill-box;transform-origin:center;animation:${id} ${o.duration}s linear infinite}`
      + `@media (prefers-reduced-motion:reduce){.${id}{animation:none}}`;
  }

  // gradient spans the whole symbol (userSpaceOnUse), not each module. ponytail: a hue-cycling
  // effect (spectrum/flip) sets per-module fill in its keyframes and will override the gradient.
  let defs = '', bodyFill = hex(o.ink);
  if (o.inkTo) {
    const gid = id + 'g', a = hex(o.ink), b = hex(o.inkTo);
    if (o.gradient === 'radial') {
      defs = `<radialGradient id="${gid}" gradientUnits="userSpaceOnUse" cx="${N / 2}" cy="${N / 2}" r="${N / 2}">`
        + `<stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></radialGradient>`;
    } else {
      const t = (o.angle * Math.PI) / 180, dx = Math.cos(t), dy = Math.sin(t);
      const L = (N / 2) * (Math.abs(dx) + Math.abs(dy)), mx = N / 2, my = N / 2;
      defs = `<linearGradient id="${gid}" gradientUnits="userSpaceOnUse" x1="${n4(mx - dx * L)}" y1="${n4(my - dy * L)}" x2="${n4(mx + dx * L)}" y2="${n4(my + dy * L)}">`
        + `<stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient>`;
    }
    bodyFill = `url(#${gid})`;
  }
  let body = '';
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) {
    const i = r * n + c;
    if (!qr.dark[i] || isFinder(qr, r, c)) continue;
    if (qr.fixed[i]) { body += `<rect x="${c + q}" y="${r + q}" width="1" height="1"/>`; continue; }
    const s = e.size, x = c + q + (1 - s) / 2, y = r + q + (1 - s) / 2;
    const rx = e.radius ? ` rx="${n4(e.radius * s)}"` : '';
    const delay = animated ? ` style="animation-delay:-${n4(frac(e.phase(r, c, Math.hypot(r - mid, c - mid), o.rand[i])) * o.duration)}s"` : '';
    body += `<rect${animated ? ` class="${id}"` : ''} x="${n4(x)}" y="${n4(y)}" width="${n4(s)}" height="${n4(s)}"${rx}${delay}/>`;
  }
  for (const [r, c] of [[0, 0], [0, n - 7], [n - 7, 0]])
    for (const sh of eye(r + q, c + q, o))
      body += `<rect x="${sh.cx - sh.w / 2}" y="${sh.cy - sh.h / 2}" width="${sh.w}" height="${sh.h}" rx="${sh.r}" fill="${hex(sh.fill)}"/>`;

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${N} ${N}" width="${px}" height="${px}" role="img" aria-label="QR code: ${escapeXml(qr.text)}">`
    + (keyframes ? `<style>${keyframes}</style>` : '')
    + (defs ? `<defs>${defs}</defs>` : '')
    + `<rect width="${N}" height="${N}" fill="${hex(o.paper)}"/><g fill="${bodyFill}">${body}</g></svg>`;
}

export interface Raster {
  width: number;
  height: number;
  /** RGBA, row-major. */
  data: Uint8ClampedArray;
}

/** Rasterize one frame to RGBA pixels (no anti-aliasing). Works without a DOM. */
export function rasterize(qr: QR, opts: RenderOptions = {}, t = 0, scale = 8): Raster {
  const o = resolve(qr, opts), N = qr.size + o.quiet * 2, W = N * scale;
  const data = new Uint8ClampedArray(W * W * 4);
  for (let i = 0; i < W * W; i++) { data[i * 4] = o.paper[0]; data[i * 4 + 1] = o.paper[1]; data[i * 4 + 2] = o.paper[2]; data[i * 4 + 3] = 255; }
  for (const s of shapes(qr, o, (ph) => o.effect.pose(frac(t / o.duration + ph)))) fillShape(data, W, s, scale);
  return { width: W, height: W, data };
}

function fillShape(data: Uint8ClampedArray, W: number, s: Shape, scale: number) {
  const cx = s.cx * scale, cy = s.cy * scale, hw = (s.w * scale) / 2, hh = (s.h * scale) / 2;
  const rr = Math.min(s.r * scale, hw, hh), a = (s.rot * Math.PI) / 180, cos = Math.cos(a), sin = Math.sin(a);
  const R = Math.hypot(hw, hh);
  const x0 = Math.max(0, Math.floor(cx - R)), x1 = Math.min(W - 1, Math.ceil(cx + R));
  const y0 = Math.max(0, Math.floor(cy - R)), y1 = Math.min(W - 1, Math.ceil(cy + R));
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
    const dx = x + 0.5 - cx, dy = y + 0.5 - cy;
    const lx = Math.abs(cos * dx + sin * dy), ly = Math.abs(-sin * dx + cos * dy);
    const qx = lx - (hw - rr), qy = ly - (hh - rr);
    const outside = Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - rr;
    if (outside > 0) continue;
    const k = (y * W + x) * 4;
    data[k] = s.fill[0]; data[k + 1] = s.fill[1]; data[k + 2] = s.fill[2];
  }
}

export interface VerifyResult {
  ok: boolean;
  /** Frames checked. */
  frames: number;
  /** Most wrong modules seen in any one frame. */
  worst: number;
  /** Time (seconds) of the worst frame. */
  worstAt: number;
}

/**
 * Check that the middle of every module has the right color on every sampled frame. Real decoders
 * don't hit the exact center (jsQR fails a box that drifts 0.42 modules even though the center
 * stays dark), so a 3x3 grid of points at the center and ±0.2 modules must all be right.
 * Strict: built-in effects must have zero wrong modules on every frame.
 */
// ponytail: strict zero-error check; per-RS-block EC budgeting comes when an effect needs to damage modules on purpose (logos, art)
export function verify(qr: QR, opts: RenderOptions = {}, frames = 48): VerifyResult {
  const o = resolve(qr, opts), N = qr.size + o.quiet * 2, n = qr.size, S = 5; // pixel centers 1..3 sit at 0.3, 0.5, 0.7 of a module
  const threshold = (luminance(o.ink) + luminance(o.paper)) / 2;
  let worst = 0, worstAt = 0;
  for (let f = 0; f < frames; f++) {
    const t = (f / frames) * o.duration;
    const img = rasterize(qr, opts, t, S);
    let wrong = 0;
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) {
      const want = !!qr.dark[r * n + c];
      check: for (let y = 1; y <= 3; y++) for (let x = 1; x <= 3; x++) {
        const k = (((r + o.quiet) * S + y) * N * S + (c + o.quiet) * S + x) * 4;
        if ((luminance([img.data[k], img.data[k + 1], img.data[k + 2]]) < threshold) !== want) { wrong++; break check; }
      }
    }
    if (wrong > worst) { worst = wrong; worstAt = t; }
  }
  return { ok: worst === 0, frames, worst, worstAt };
}

/** Draw one frame onto a 2D canvas context (browser or OffscreenCanvas). */
export function drawFrame(ctx: CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D, qr: QR, opts: RenderOptions = {}, t = 0, scale = 8) {
  const o = resolve(qr, opts), W = (qr.size + o.quiet * 2) * scale;
  ctx.fillStyle = hex(o.paper);
  ctx.fillRect(0, 0, W, W);
  for (const s of shapes(qr, o, (ph) => o.effect.pose(frac(t / o.duration + ph)))) {
    ctx.save();
    ctx.translate(s.cx * scale, s.cy * scale);
    ctx.rotate((s.rot * Math.PI) / 180);
    ctx.fillStyle = hex(s.fill);
    ctx.beginPath();
    ctx.roundRect((-s.w * scale) / 2, (-s.h * scale) / 2, s.w * scale, s.h * scale, s.r * scale);
    ctx.fill();
    ctx.restore();
  }
}

/**
 * One frame as terminal text using half-block characters. Each module is `scale` columns wide
 * and scale/2 rows tall, so it looks square. color: 24-bit ANSI colors; otherwise plain text
 * that draws the paper as blocks (reads correctly on dark terminals).
 */
export function toTerminal(qr: QR, opts: RenderOptions & { color?: boolean; scale?: number } = {}, t = 0): string {
  const scale = opts.scale ?? 2;
  if (!(Number.isInteger(scale) && scale >= 1)) throw new RangeError('scale must be a positive integer');
  const img = rasterize(qr, opts, t, scale), W = img.width, d = img.data;
  const px = (x: number, y: number): RGB => {
    if (y >= W) return [d[0], d[1], d[2]];
    const k = (y * W + x) * 4;
    return [d[k], d[k + 1], d[k + 2]];
  };
  const paperLum = luminance(px(0, 0));
  const lines: string[] = [];
  for (let y = 0; y < W; y += 2) {
    let line = '';
    if (opts.color) {
      let last = '';
      for (let x = 0; x < W; x++) {
        const top = px(x, y), bot = px(x, y + 1);
        const code = `\x1b[38;2;${top.join(';')};48;2;${bot.join(';')}m`;
        line += (code === last ? '' : code) + '▀';
        last = code;
      }
      line += '\x1b[0m';
    } else {
      for (let x = 0; x < W; x++) {
        const top = luminance(px(x, y)) > paperLum / 2, bot = luminance(px(x, y + 1)) > paperLum / 2;
        line += top && bot ? '█' : top ? '▀' : bot ? '▄' : ' ';
      }
    }
    lines.push(line);
  }
  return lines.join('\n');
}

/** Convenience: encode and render an animated SVG in one call. */
export function animatedQR(text: string, opts: RenderOptions & { ecc?: Ecc; px?: number } = {}): string {
  return toSVG(encode(text, opts.ecc ?? 'Q'), opts);
}

// ---- color helpers ----

function parseHex(s: string): RGB {
  const m = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(String(s).trim());
  if (!m) throw new TypeError(`color must be #rgb or #rrggbb (got ${s})`);
  const h = m[1].length === 3 ? m[1].replace(/./g, (ch) => ch + ch) : m[1];
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}

const hex = (c: RGB) => '#' + c.map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');

/** Relative luminance (Rec. 709 / sRGB). */
function luminance([r, g, b]: RGB): number {
  const lin = (v: number) => { v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

function tint(rgb: RGB, hue = 0, shade = 0): RGB {
  if (!hue && !shade) return rgb;
  let [h, s, l] = toHsl(rgb);
  if (hue) s = Math.max(s, 0.65);
  return fromHsl((((h + hue) % 360) + 360) % 360, s, Math.min(1, Math.max(0, l + shade)));
}

function toHsl([r, g, b]: RGB): [number, number, number] {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
  if (!d) return [0, 0, l];
  const s = d / (1 - Math.abs(2 * l - 1));
  const h = max === r ? ((g - b) / d + 6) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [h * 60, s, l];
}

function fromHsl(h: number, s: number, l: number): RGB {
  const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return [(r + m) * 255, (g + m) * 255, (b + m) * 255];
}

const n4 = (v: number) => +v.toFixed(4);

function fnv(str: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) h = Math.imul(h ^ str.charCodeAt(i), 0x01000193);
  return (h >>> 0).toString(36);
}

function escapeXml(s: string) {
  return s.replace(/[<>&"']/g, (ch) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' })[ch]!);
}
