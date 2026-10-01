import { qrcodegen } from './qrcodegen.js';

export type Ecc = 'L' | 'M' | 'Q' | 'H';

/** An encoded QR symbol plus a map of which modules must never move. */
export interface QR {
  text: string;
  /** Modules per side (21 for version 1, up to 177). */
  size: number;
  version: number;
  /** Actual level used. May be higher than requested when it fits for free. */
  ecc: Ecc;
  /** 1 = dark module, row-major, size * size. */
  dark: Uint8Array;
  /** 1 = function pattern (finder, separator, timing, alignment, format/version info). Never animated. */
  fixed: Uint8Array;
}

const LEVELS: Record<Ecc, qrcodegen.QrCode.Ecc> = {
  L: qrcodegen.QrCode.Ecc.LOW,
  M: qrcodegen.QrCode.Ecc.MEDIUM,
  Q: qrcodegen.QrCode.Ecc.QUARTILE,
  H: qrcodegen.QrCode.Ecc.HIGH,
};

/** Encode text (UTF-8). Throws RangeError when the text does not fit in version 40 at this level. */
export function encode(text: string, ecc: Ecc = 'Q'): QR {
  if (typeof text !== 'string') throw new TypeError('text must be a string');
  if (!(ecc in LEVELS)) throw new TypeError(`ecc must be one of L, M, Q, H (got ${String(ecc)})`);
  const code = qrcodegen.QrCode.encodeText(text, LEVELS[ecc]);
  const n = code.size, v = code.version;
  const dark = new Uint8Array(n * n), fixed = new Uint8Array(n * n);
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) dark[r * n + c] = code.getModule(c, r) ? 1 : 0;

  const mark = (r0: number, c0: number, h: number, w: number) => {
    for (let r = Math.max(0, r0); r < Math.min(n, r0 + h); r++)
      for (let c = Math.max(0, c0); c < Math.min(n, c0 + w); c++) fixed[r * n + c] = 1;
  };
  // finders + separators + format info; the always-dark module sits inside the bottom-left block
  mark(0, 0, 9, 9); mark(0, n - 8, 9, 8); mark(n - 8, 0, 8, 9);
  mark(6, 0, 1, n); mark(0, 6, n, 1); // timing
  const align = alignmentPositions(v, n);
  for (const a of align) for (const b of align) {
    if ((a < 9 && b < 9) || (a < 9 && b > n - 10) || (a > n - 10 && b < 9)) continue;
    mark(a - 2, b - 2, 5, 5);
  }
  if (v >= 7) { mark(0, n - 11, 6, 3); mark(n - 11, 0, 3, 6); } // version info

  return { text, size: n, version: v, ecc: (['L', 'M', 'Q', 'H'] as const)[code.errorCorrectionLevel.ordinal], dark, fixed };
}

// Same formula as qrcodegen's private getAlignmentPatternPositions
function alignmentPositions(v: number, n: number): number[] {
  if (v === 1) return [];
  const count = Math.floor(v / 7) + 2;
  const step = Math.floor((v * 8 + count * 3 + 5) / (count * 4 - 4)) * 2;
  const out = [6];
  for (let pos = n - 7; out.length < count; pos -= step) out.splice(1, 0, pos);
  return out;
}

/** True for modules inside one of the three 7x7 finder squares. */
export function isFinder(qr: QR, r: number, c: number): boolean {
  const n = qr.size;
  return (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);
}
