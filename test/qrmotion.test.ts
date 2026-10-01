import { describe, expect, test } from 'bun:test';
import jsQR from 'jsqr';
import pkg from '../package.json';
import {
  encode, rasterize, verify, toSVG, toTerminal, runTool, handleMcp, tool, VERSION,
  EFFECT_NAMES, type Effect,
} from '../src/index.ts';

const TEXT = 'https://example.com/animated-qr?ref=qrmotion';

describe('every frame scans', () => {
  for (const effect of EFFECT_NAMES) {
    for (const ecc of ['L', 'H'] as const) {
      test(`${effect} @ ${ecc}`, () => {
        const qr = encode(TEXT, ecc);
        const v = verify(qr, { effect }, 48);
        expect(v).toMatchObject({ ok: true, worst: 0 });
        // second opinion from an independent decoder
        for (let f = 0; f < 24; f++) {
          const img = rasterize(qr, { effect }, (f / 24) * 2.4, 4);
          const res = jsQR(img.data, img.width, img.height, { inversionAttempts: 'dontInvert' });
          expect(res?.data).toBe(TEXT);
        }
      });
    }
  }

  test('large version with alignment and version info', () => {
    const qr = encode('x'.repeat(400), 'M');
    expect(qr.version).toBeGreaterThanOrEqual(7);
    expect(verify(qr, { effect: 'jiggle' }, 12).ok).toBe(true);
  });
});

test('verify catches an unsafe effect', () => {
  const drift: Effect = {
    name: 'drift', description: 'moves boxes off their centers', size: 0.9, radius: 0.5,
    phase: (_r, _c, _d, rand) => rand,
    pose: (u) => ({ dx: 0.6 * Math.cos(2 * Math.PI * u), dy: 0.6 * Math.sin(2 * Math.PI * u), sx: 1, sy: 1, rot: 0 }),
  };
  const v = verify(encode(TEXT), { effect: drift }, 12);
  expect(v.ok).toBe(false);
  expect(v.worst).toBeGreaterThan(0);
});

test('rejects low contrast and bad input', () => {
  const qr = encode(TEXT);
  expect(() => toSVG(qr, { ink: '#999', paper: '#aaa' })).toThrow(/darker/);
  expect(() => toSVG(qr, { ink: 'red' })).toThrow(/#rgb/);
  expect(() => encode('x'.repeat(5000))).toThrow();
  expect(() => toSVG(qr, { effect: 'nope' as never })).toThrow(/unknown effect/);
});

test('svg output', () => {
  const svg = toSVG(encode('a<b>&"c"'), { effect: 'slide' });
  expect(svg.startsWith('<svg')).toBe(true);
  expect(svg).toMatch(/@keyframes qm[0-9a-z]+\{/);
  const other = toSVG(encode('a<b>&"c"'), { effect: 'flip' });
  expect(other.match(/@keyframes (qm[0-9a-z]+)/)![1]).not.toBe(svg.match(/@keyframes (qm[0-9a-z]+)/)![1]);
  expect(svg).toContain('prefers-reduced-motion');
  expect(svg).toContain('aria-label="QR code: a&lt;b&gt;&amp;&quot;c&quot;"');
  expect(toSVG(encode('a'), { effect: 'none' })).not.toContain('@keyframes');
});

test('terminal output', () => {
  const qr = encode(TEXT);
  const mono = toTerminal(qr, { scale: 2 });
  const N = qr.size + 8;
  expect(mono.split('\n')).toHaveLength(N);
  expect(mono.split('\n')[0]).toBe('█'.repeat(N * 2)); // quiet zone row is all paper
  expect(toTerminal(qr, { color: true })).toContain('\x1b[38;2;');
});

test('LLM tool', () => {
  const out = runTool({ text: TEXT, effect: 'flip', ecc: 'M' });
  expect(out).toMatchObject({ format: 'svg', effect: 'flip', verified: true });
  expect(out.output.startsWith('<svg')).toBe(true);
  expect(() => runTool({ text: TEXT, color: 'x' })).toThrow(/unknown field/);
  expect(() => runTool({})).toThrow(/text/);
  expect(tool.inputSchema.properties.effect.enum).toEqual(EFFECT_NAMES);
});

test('MCP handshake and call', () => {
  const init = handleMcp({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18' } }) as any;
  expect(init.result.serverInfo.name).toBe('qrmotion');
  expect(handleMcp({ jsonrpc: '2.0', method: 'notifications/initialized' })).toBeNull();
  const list = handleMcp({ jsonrpc: '2.0', id: 2, method: 'tools/list' }) as any;
  expect(list.result.tools[0].name).toBe('animated_qr');
  const call = handleMcp({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'animated_qr', arguments: { text: 'hi' } } }) as any;
  expect(call.result.content[0].text.startsWith('<svg')).toBe(true);
  const bad = handleMcp({ jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'animated_qr', arguments: {} } }) as any;
  expect(bad.result.isError).toBe(true);
  expect((handleMcp({ jsonrpc: '2.0', id: 5, method: 'nope' }) as any).error.code).toBe(-32601);
});

test('zero runtime dependencies, version in sync', () => {
  expect((pkg as any).dependencies).toBeUndefined();
  expect((pkg as any).peerDependencies).toBeUndefined();
  expect(VERSION).toBe(pkg.version);
});
