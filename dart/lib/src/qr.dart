import 'dart:typed_data';

import 'qrcodegen.dart';

export 'qrcodegen.dart' show Ecc;

/// An encoded QR symbol plus a map of which modules must never move.
class QR {
  const QR._(this.text, this.size, this.version, this.ecc, this.dark, this.fixed);

  final String text;

  /// Modules per side (21 for version 1, up to 177).
  final int size;
  final int version;

  /// Actual level used. May be higher than requested when it fits for free.
  final Ecc ecc;

  /// 1 = dark module, row-major, size * size.
  final Uint8List dark;

  /// 1 = function pattern (finder, separator, timing, alignment, format/version info). Never animated.
  final Uint8List fixed;
}

/// Encode text (UTF-8). Throws [RangeError] when the text does not fit in version 40 at this level.
QR encode(String text, [Ecc ecc = Ecc.q]) {
  final code = QrCode.encodeText(text, ecc);
  final n = code.size, v = code.version;
  final dark = Uint8List(n * n), fixed = Uint8List(n * n);
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      dark[r * n + c] = code.getModule(c, r) ? 1 : 0;
    }
  }

  void mark(int r0, int c0, int h, int w) {
    for (var r = r0 < 0 ? 0 : r0; r < (n < r0 + h ? n : r0 + h); r++) {
      for (var c = c0 < 0 ? 0 : c0; c < (n < c0 + w ? n : c0 + w); c++) {
        fixed[r * n + c] = 1;
      }
    }
  }

  // finders + separators + format info; the always-dark module sits inside the bottom-left block
  mark(0, 0, 9, 9);
  mark(0, n - 8, 9, 8);
  mark(n - 8, 0, 8, 9);
  mark(6, 0, 1, n); // timing
  mark(0, 6, n, 1);
  final align = _alignmentPositions(v, n);
  for (final a in align) {
    for (final b in align) {
      if ((a < 9 && b < 9) || (a < 9 && b > n - 10) || (a > n - 10 && b < 9)) continue;
      mark(a - 2, b - 2, 5, 5);
    }
  }
  if (v >= 7) {
    mark(0, n - 11, 6, 3); // version info
    mark(n - 11, 0, 3, 6);
  }

  return QR._(text, n, v, code.ecc, dark, fixed);
}

// Same formula as qrcodegen's private getAlignmentPatternPositions
List<int> _alignmentPositions(int v, int n) {
  if (v == 1) return [];
  final count = v ~/ 7 + 2;
  final step = (v * 8 + count * 3 + 5) ~/ (count * 4 - 4) * 2;
  final out = [6];
  for (var pos = n - 7; out.length < count; pos -= step) {
    out.insert(1, pos);
  }
  return out;
}

/// True for modules inside one of the three 7x7 finder squares.
bool isFinder(QR qr, int r, int c) {
  final n = qr.size;
  return (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);
}
