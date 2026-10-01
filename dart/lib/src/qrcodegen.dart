/*
 * QR Code generator library, ported to Dart from the TypeScript version.
 *
 * Copyright (c) Project Nayuki. (MIT License)
 * https://www.nayuki.io/page/qr-code-generator-library
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 * - The above copyright notice and this permission notice shall be included in
 *   all copies or substantial portions of the Software.
 * - The Software is provided "as is", without warranty of any kind, express or
 *   implied, including but not limited to the warranties of merchantability,
 *   fitness for a particular purpose and noninfringement. In no event shall the
 *   authors or copyright holders be liable for any claim, damages or other
 *   liability, whether in an action of contract, tort or otherwise, arising from,
 *   out of or in connection with the Software or the use or other dealings in the
 *   Software.
 */

// Trimmed to what qrmotion uses: encodeText with numeric, alphanumeric and byte
// segments, automatic version, ECC boost and automatic mask. Logic is unchanged.

import 'dart:convert';

/// Error correction level. Higher levels survive more damage and need more modules.
enum Ecc {
  l(1),
  m(0),
  q(3),
  h(2);

  const Ecc(this.formatBits);

  /// The 2-bit value in the format information.
  final int formatBits;
}

/// A QR Code symbol (Model 2, versions 1 to 40).
class QrCode {
  QrCode._(this.version, this.ecc, List<int> dataCodewords, int msk) : size = version * 4 + 17 {
    if (version < minVersion || version > maxVersion) throw RangeError('Version value out of range');
    if (msk < -1 || msk > 7) throw RangeError('Mask value out of range');
    _modules = List.generate(size, (_) => List.filled(size, false));
    _isFunction = List.generate(size, (_) => List.filled(size, false));

    _drawFunctionPatterns();
    _drawCodewords(_addEccAndInterleave(dataCodewords));

    if (msk == -1) {
      var minPenalty = 1000000000;
      for (var i = 0; i < 8; i++) {
        _applyMask(i);
        _drawFormatBits(i);
        final penalty = _getPenaltyScore();
        if (penalty < minPenalty) {
          msk = i;
          minPenalty = penalty;
        }
        _applyMask(i); // undoes the mask due to XOR
      }
    }
    _assert(0 <= msk && msk <= 7);
    mask = msk;
    _applyMask(msk);
    _drawFormatBits(msk);
  }

  static const int minVersion = 1, maxVersion = 40;

  /// Encodes Unicode text (UTF-8) at the smallest version that fits. The level may be boosted for free.
  static QrCode encodeText(String text, Ecc ecl) => encodeSegments(QrSegment.makeSegments(text), ecl);

  static QrCode encodeSegments(List<QrSegment> segs, Ecc ecl,
      {int minVer = 1, int maxVer = 40, int mask = -1, bool boostEcl = true}) {
    if (!(minVersion <= minVer && minVer <= maxVer && maxVer <= maxVersion) || mask < -1 || mask > 7) {
      throw RangeError('Invalid value');
    }
    int version;
    int dataUsedBits;
    for (version = minVer;; version++) {
      final dataCapacityBits = _getNumDataCodewords(version, ecl) * 8;
      final usedBits = QrSegment.getTotalBits(segs, version);
      if (usedBits != null && usedBits <= dataCapacityBits) {
        dataUsedBits = usedBits;
        break;
      }
      if (version >= maxVer) throw RangeError('Data too long');
    }

    for (final newEcl in const [Ecc.m, Ecc.q, Ecc.h]) {
      if (boostEcl && dataUsedBits <= _getNumDataCodewords(version, newEcl) * 8) ecl = newEcl;
    }

    final bb = <int>[];
    for (final seg in segs) {
      _appendBits(seg.mode.modeBits, 4, bb);
      _appendBits(seg.numChars, seg.mode.numCharCountBits(version), bb);
      bb.addAll(seg.data);
    }
    _assert(bb.length == dataUsedBits);

    final dataCapacityBits = _getNumDataCodewords(version, ecl) * 8;
    _assert(bb.length <= dataCapacityBits);
    _appendBits(0, (dataCapacityBits - bb.length) < 4 ? dataCapacityBits - bb.length : 4, bb);
    _appendBits(0, (8 - bb.length % 8) % 8, bb);
    _assert(bb.length % 8 == 0);

    for (var padByte = 0xEC; bb.length < dataCapacityBits; padByte ^= 0xEC ^ 0x11) {
      _appendBits(padByte, 8, bb);
    }

    final dataCodewords = List.filled(bb.length >> 3, 0);
    for (var i = 0; i < bb.length; i++) {
      dataCodewords[i >>> 3] |= bb[i] << (7 - (i & 7));
    }
    return QrCode._(version, ecl, dataCodewords, mask);
  }

  /// Between 1 and 40.
  final int version;

  /// Modules per side, version * 4 + 17.
  final int size;

  /// The level actually used (may be higher than requested).
  final Ecc ecc;

  /// Mask pattern 0..7.
  late final int mask;

  late final List<List<bool>> _modules;
  late List<List<bool>> _isFunction;

  /// True for dark. Out of bounds is light.
  bool getModule(int x, int y) => 0 <= x && x < size && 0 <= y && y < size && _modules[y][x];

  void _drawFunctionPatterns() {
    for (var i = 0; i < size; i++) {
      _setFunctionModule(6, i, i % 2 == 0);
      _setFunctionModule(i, 6, i % 2 == 0);
    }
    _drawFinderPattern(3, 3);
    _drawFinderPattern(size - 4, 3);
    _drawFinderPattern(3, size - 4);

    final alignPatPos = _getAlignmentPatternPositions();
    final numAlign = alignPatPos.length;
    for (var i = 0; i < numAlign; i++) {
      for (var j = 0; j < numAlign; j++) {
        if (!(i == 0 && j == 0 || i == 0 && j == numAlign - 1 || i == numAlign - 1 && j == 0)) {
          _drawAlignmentPattern(alignPatPos[i], alignPatPos[j]);
        }
      }
    }
    _drawFormatBits(0); // dummy mask, overwritten later
    _drawVersion();
  }

  void _drawFormatBits(int mask) {
    final data = ecc.formatBits << 3 | mask;
    var rem = data;
    for (var i = 0; i < 10; i++) {
      rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
    }
    final bits = (data << 10 | rem) ^ 0x5412;
    _assert(bits >>> 15 == 0);

    for (var i = 0; i <= 5; i++) {
      _setFunctionModule(8, i, _getBit(bits, i));
    }
    _setFunctionModule(8, 7, _getBit(bits, 6));
    _setFunctionModule(8, 8, _getBit(bits, 7));
    _setFunctionModule(7, 8, _getBit(bits, 8));
    for (var i = 9; i < 15; i++) {
      _setFunctionModule(14 - i, 8, _getBit(bits, i));
    }

    for (var i = 0; i < 8; i++) {
      _setFunctionModule(size - 1 - i, 8, _getBit(bits, i));
    }
    for (var i = 8; i < 15; i++) {
      _setFunctionModule(8, size - 15 + i, _getBit(bits, i));
    }
    _setFunctionModule(8, size - 8, true); // always dark
  }

  void _drawVersion() {
    if (version < 7) return;
    var rem = version;
    for (var i = 0; i < 12; i++) {
      rem = (rem << 1) ^ ((rem >>> 11) * 0x1F25);
    }
    final bits = version << 12 | rem;
    _assert(bits >>> 18 == 0);
    for (var i = 0; i < 18; i++) {
      final color = _getBit(bits, i);
      final a = size - 11 + i % 3;
      final b = i ~/ 3;
      _setFunctionModule(a, b, color);
      _setFunctionModule(b, a, color);
    }
  }

  void _drawFinderPattern(int x, int y) {
    for (var dy = -4; dy <= 4; dy++) {
      for (var dx = -4; dx <= 4; dx++) {
        final dist = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
        final xx = x + dx, yy = y + dy;
        if (0 <= xx && xx < size && 0 <= yy && yy < size) _setFunctionModule(xx, yy, dist != 2 && dist != 4);
      }
    }
  }

  void _drawAlignmentPattern(int x, int y) {
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        _setFunctionModule(x + dx, y + dy, (dx.abs() > dy.abs() ? dx.abs() : dy.abs()) != 1);
      }
    }
  }

  void _setFunctionModule(int x, int y, bool isDark) {
    _modules[y][x] = isDark;
    _isFunction[y][x] = true;
  }

  List<int> _addEccAndInterleave(List<int> data) {
    final ver = version;
    if (data.length != _getNumDataCodewords(ver, ecc)) throw RangeError('Invalid argument');

    final numBlocks = _numErrorCorrectionBlocks[ecc.index][ver];
    final blockEccLen = _eccCodewordsPerBlock[ecc.index][ver];
    final rawCodewords = _getNumRawDataModules(ver) ~/ 8;
    final numShortBlocks = numBlocks - rawCodewords % numBlocks;
    final shortBlockLen = rawCodewords ~/ numBlocks;

    final blocks = <List<int>>[];
    final rsDiv = _reedSolomonComputeDivisor(blockEccLen);
    for (var i = 0, k = 0; i < numBlocks; i++) {
      final dat = [...data.sublist(k, k + shortBlockLen - blockEccLen + (i < numShortBlocks ? 0 : 1))];
      k += dat.length;
      final ecc = _reedSolomonComputeRemainder(dat, rsDiv);
      if (i < numShortBlocks) dat.add(0);
      blocks.add(dat..addAll(ecc));
    }

    final result = <int>[];
    for (var i = 0; i < blocks[0].length; i++) {
      for (var j = 0; j < blocks.length; j++) {
        if (i != shortBlockLen - blockEccLen || j >= numShortBlocks) result.add(blocks[j][i]);
      }
    }
    _assert(result.length == rawCodewords);
    return result;
  }

  void _drawCodewords(List<int> data) {
    if (data.length != _getNumRawDataModules(version) ~/ 8) throw RangeError('Invalid argument');
    var i = 0;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      for (var vert = 0; vert < size; vert++) {
        for (var j = 0; j < 2; j++) {
          final x = right - j;
          final upward = ((right + 1) & 2) == 0;
          final y = upward ? size - 1 - vert : vert;
          if (!_isFunction[y][x] && i < data.length * 8) {
            _modules[y][x] = _getBit(data[i >>> 3], 7 - (i & 7));
            i++;
          }
        }
      }
    }
    _assert(i == data.length * 8);
  }

  void _applyMask(int mask) {
    if (mask < 0 || mask > 7) throw RangeError('Mask value out of range');
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final invert = switch (mask) {
          0 => (x + y) % 2 == 0,
          1 => y % 2 == 0,
          2 => x % 3 == 0,
          3 => (x + y) % 3 == 0,
          4 => (x ~/ 3 + y ~/ 2) % 2 == 0,
          5 => x * y % 2 + x * y % 3 == 0,
          6 => (x * y % 2 + x * y % 3) % 2 == 0,
          _ => ((x + y) % 2 + x * y % 3) % 2 == 0,
        };
        if (!_isFunction[y][x] && invert) _modules[y][x] = !_modules[y][x];
      }
    }
  }

  int _getPenaltyScore() {
    var result = 0;
    for (var y = 0; y < size; y++) {
      var runColor = false;
      var runX = 0;
      final runHistory = [0, 0, 0, 0, 0, 0, 0];
      for (var x = 0; x < size; x++) {
        if (_modules[y][x] == runColor) {
          runX++;
          if (runX == 5) {
            result += _penaltyN1;
          } else if (runX > 5) {
            result++;
          }
        } else {
          _finderPenaltyAddHistory(runX, runHistory);
          if (!runColor) result += _finderPenaltyCountPatterns(runHistory) * _penaltyN3;
          runColor = _modules[y][x];
          runX = 1;
        }
      }
      result += _finderPenaltyTerminateAndCount(runColor, runX, runHistory) * _penaltyN3;
    }
    for (var x = 0; x < size; x++) {
      var runColor = false;
      var runY = 0;
      final runHistory = [0, 0, 0, 0, 0, 0, 0];
      for (var y = 0; y < size; y++) {
        if (_modules[y][x] == runColor) {
          runY++;
          if (runY == 5) {
            result += _penaltyN1;
          } else if (runY > 5) {
            result++;
          }
        } else {
          _finderPenaltyAddHistory(runY, runHistory);
          if (!runColor) result += _finderPenaltyCountPatterns(runHistory) * _penaltyN3;
          runColor = _modules[y][x];
          runY = 1;
        }
      }
      result += _finderPenaltyTerminateAndCount(runColor, runY, runHistory) * _penaltyN3;
    }

    for (var y = 0; y < size - 1; y++) {
      for (var x = 0; x < size - 1; x++) {
        final color = _modules[y][x];
        if (color == _modules[y][x + 1] && color == _modules[y + 1][x] && color == _modules[y + 1][x + 1]) {
          result += _penaltyN2;
        }
      }
    }

    var dark = 0;
    for (final row in _modules) {
      for (final color in row) {
        if (color) dark++;
      }
    }
    final total = size * size;
    final k = ((dark * 20 - total * 10).abs() / total).ceil() - 1;
    _assert(0 <= k && k <= 9);
    result += k * _penaltyN4;
    _assert(0 <= result && result <= 2568888);
    return result;
  }

  List<int> _getAlignmentPatternPositions() {
    if (version == 1) return [];
    final numAlign = version ~/ 7 + 2;
    final step = (version * 8 + numAlign * 3 + 5) ~/ (numAlign * 4 - 4) * 2;
    final result = [6];
    for (var pos = size - 7; result.length < numAlign; pos -= step) {
      result.insert(1, pos);
    }
    return result;
  }

  static int _getNumRawDataModules(int ver) {
    if (ver < minVersion || ver > maxVersion) throw RangeError('Version number out of range');
    var result = (16 * ver + 128) * ver + 64;
    if (ver >= 2) {
      final numAlign = ver ~/ 7 + 2;
      result -= (25 * numAlign - 10) * numAlign - 55;
      if (ver >= 7) result -= 36;
    }
    _assert(208 <= result && result <= 29648);
    return result;
  }

  static int _getNumDataCodewords(int ver, Ecc ecl) =>
      _getNumRawDataModules(ver) ~/ 8 -
      _eccCodewordsPerBlock[ecl.index][ver] * _numErrorCorrectionBlocks[ecl.index][ver];

  static List<int> _reedSolomonComputeDivisor(int degree) {
    if (degree < 1 || degree > 255) throw RangeError('Degree out of range');
    final result = List.filled(degree, 0)..[degree - 1] = 1;
    var root = 1;
    for (var i = 0; i < degree; i++) {
      for (var j = 0; j < result.length; j++) {
        result[j] = _reedSolomonMultiply(result[j], root);
        if (j + 1 < result.length) result[j] ^= result[j + 1];
      }
      root = _reedSolomonMultiply(root, 0x02);
    }
    return result;
  }

  static List<int> _reedSolomonComputeRemainder(List<int> data, List<int> divisor) {
    final result = List.filled(divisor.length, 0, growable: true);
    for (final b in data) {
      final factor = b ^ result.removeAt(0);
      result.add(0);
      for (var i = 0; i < divisor.length; i++) {
        result[i] ^= _reedSolomonMultiply(divisor[i], factor);
      }
    }
    return result;
  }

  static int _reedSolomonMultiply(int x, int y) {
    if (x >>> 8 != 0 || y >>> 8 != 0) throw RangeError('Byte out of range');
    var z = 0;
    for (var i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >>> 7) * 0x11D);
      z ^= ((y >>> i) & 1) * x;
    }
    _assert(z >>> 8 == 0);
    return z;
  }

  int _finderPenaltyCountPatterns(List<int> runHistory) {
    final n = runHistory[1];
    _assert(n <= size * 3);
    final core = n > 0 && runHistory[2] == n && runHistory[3] == n * 3 && runHistory[4] == n && runHistory[5] == n;
    return (core && runHistory[0] >= n * 4 && runHistory[6] >= n ? 1 : 0) +
        (core && runHistory[6] >= n * 4 && runHistory[0] >= n ? 1 : 0);
  }

  int _finderPenaltyTerminateAndCount(bool currentRunColor, int currentRunLength, List<int> runHistory) {
    if (currentRunColor) {
      _finderPenaltyAddHistory(currentRunLength, runHistory);
      currentRunLength = 0;
    }
    currentRunLength += size;
    _finderPenaltyAddHistory(currentRunLength, runHistory);
    return _finderPenaltyCountPatterns(runHistory);
  }

  void _finderPenaltyAddHistory(int currentRunLength, List<int> runHistory) {
    if (runHistory[0] == 0) currentRunLength += size;
    runHistory
      ..removeLast()
      ..insert(0, currentRunLength);
  }

  static const _penaltyN1 = 3, _penaltyN2 = 3, _penaltyN3 = 40, _penaltyN4 = 10;

  static const _eccCodewordsPerBlock = [
    [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30], // L
    [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28], // M
    [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30], // Q
    [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30], // H
  ];

  static const _numErrorCorrectionBlocks = [
    [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25], // L
    [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49], // M
    [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68], // Q
    [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81], // H
  ];
}

void _appendBits(int val, int len, List<int> bb) {
  if (len < 0 || len > 31 || val >>> len != 0) throw RangeError('Value out of range');
  for (var i = len - 1; i >= 0; i--) {
    bb.add((val >>> i) & 1);
  }
}

bool _getBit(int x, int i) => ((x >>> i) & 1) != 0;

void _assert(bool cond) {
  if (!cond) throw StateError('Assertion error');
}

/// Segment encoding mode.
enum QrMode {
  numeric(0x1, [10, 12, 14]),
  alphanumeric(0x2, [9, 11, 13]),
  byte(0x4, [8, 16, 16]);

  const QrMode(this.modeBits, this._numBitsCharCount);

  final int modeBits;
  final List<int> _numBitsCharCount;

  int numCharCountBits(int ver) => _numBitsCharCount[(ver + 7) ~/ 17];
}

/// A run of data in one encoding mode.
class QrSegment {
  QrSegment(this.mode, this.numChars, List<int> data) : data = List.unmodifiable(data) {
    if (numChars < 0) throw RangeError('Invalid argument');
  }

  final QrMode mode;
  final int numChars;
  final List<int> data;

  static QrSegment makeBytes(List<int> data) {
    final bb = <int>[];
    for (final b in data) {
      _appendBits(b, 8, bb);
    }
    return QrSegment(QrMode.byte, data.length, bb);
  }

  static QrSegment makeNumeric(String digits) {
    if (!isNumeric(digits)) throw RangeError('String contains non-numeric characters');
    final bb = <int>[];
    for (var i = 0; i < digits.length;) {
      final n = digits.length - i < 3 ? digits.length - i : 3;
      _appendBits(int.parse(digits.substring(i, i + n)), n * 3 + 1, bb);
      i += n;
    }
    return QrSegment(QrMode.numeric, digits.length, bb);
  }

  static QrSegment makeAlphanumeric(String text) {
    if (!isAlphanumeric(text)) throw RangeError('String contains unencodable characters in alphanumeric mode');
    final bb = <int>[];
    int i;
    for (i = 0; i + 2 <= text.length; i += 2) {
      var temp = _alphanumericCharset.indexOf(text[i]) * 45;
      temp += _alphanumericCharset.indexOf(text[i + 1]);
      _appendBits(temp, 11, bb);
    }
    if (i < text.length) _appendBits(_alphanumericCharset.indexOf(text[i]), 6, bb);
    return QrSegment(QrMode.alphanumeric, text.length, bb);
  }

  static List<QrSegment> makeSegments(String text) {
    if (text.isEmpty) return [];
    if (isNumeric(text)) return [makeNumeric(text)];
    if (isAlphanumeric(text)) return [makeAlphanumeric(text)];
    return [makeBytes(utf8.encode(text))];
  }

  static bool isNumeric(String text) => _numericRegex.hasMatch(text);
  static bool isAlphanumeric(String text) => _alphanumericRegex.hasMatch(text);

  /// Bits needed at this version, or null when a character count overflows its field.
  static int? getTotalBits(List<QrSegment> segs, int version) {
    var result = 0;
    for (final seg in segs) {
      final ccbits = seg.mode.numCharCountBits(version);
      if (seg.numChars >= (1 << ccbits)) return null;
      result += 4 + ccbits + seg.data.length;
    }
    return result;
  }

  static final _numericRegex = RegExp(r'^[0-9]*$');
  static final _alphanumericRegex = RegExp(r'^[A-Z0-9 $%*+./:-]*$');
  static const _alphanumericCharset = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';
}
