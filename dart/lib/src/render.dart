import 'dart:math' as math;
import 'dart:typed_data';

import 'effects.dart';
import 'qr.dart';

/// Color as (r, g, b), 0..255. Tinted colors may be fractional.
typedef Rgb = (double, double, double);

class RenderOptions {
  const RenderOptions({
    this.effect = QrEffect.slide,
    this.ink = '#17132a',
    this.paper = '#f5f2ea',
    this.duration = 2.4,
    this.quiet = 4,
    this.seed = 1,
  });

  /// Built-in [QrEffect] or a custom [Effect]. Default slide.
  final Effect effect;

  /// Dark color, #rgb or #rrggbb.
  final String ink;

  /// Light color, #rgb or #rrggbb.
  final String paper;

  /// Seconds per animation cycle.
  final double duration;

  /// Quiet zone in modules. Default 4 (the spec minimum).
  final int quiet;

  /// Seed for per-module randomness, so output is reproducible.
  final int seed;
}

/// One filled rounded box, in module units of the full canvas (quiet zone included).
class Shape {
  const Shape(this.cx, this.cy, this.w, this.h, this.rot, this.r, this.fill);

  final double cx, cy, w, h;

  /// Degrees.
  final double rot;

  /// Corner radius in modules.
  final double r;
  final Rgb fill;
}

/// Options checked and prepared once; reused across frames. Not exported.
class Resolved {
  Resolved._(this.effect, this.ink, this.paper, this.duration, this.quiet, this.rand);

  final Effect effect;
  final Rgb ink, paper;
  final double duration;
  final int quiet;
  final Float32List rand;
}

Resolved resolve(QR qr, RenderOptions o) {
  final ink = _parseHex(o.ink), paper = _parseHex(o.paper);
  if (_luminance(paper) - _luminance(ink) < 0.4) {
    throw RangeError('ink must be much darker than paper (luminance gap of at least 0.4) or the code will not scan');
  }
  if (!(o.duration > 0)) throw RangeError('duration must be a positive number of seconds');
  if (o.quiet < 0) throw RangeError('quiet must be a non-negative integer');
  final rand = Float32List(qr.size * qr.size);
  var s = o.seed & 0xffffffff;
  for (var i = 0; i < rand.length; i++) {
    // mulberry32, kept in uint32 so it matches JS on the VM and on the web
    s = (s + 0x6d2b79f5) & 0xffffffff;
    var t = _imul(s ^ (s >>> 15), 1 | s);
    t = ((t + _imul(t ^ (t >>> 7), 61 | t)) & 0xffffffff) ^ t;
    rand[i] = ((t ^ (t >>> 14)) & 0xffffffff) / 4294967296;
  }
  return Resolved._(o.effect, ink, paper, o.duration, o.quiet, rand);
}

/// Math.imul on uint32 inputs, returned as uint32. 16-bit halves keep products exact on the web.
int _imul(int a, int b) {
  final al = a & 0xffff, ah = (a >>> 16) & 0xffff, bl = b & 0xffff, bh = (b >>> 16) & 0xffff;
  return (al * bl + ((((ah * bl + al * bh) & 0xffff) * 65536))) & 0xffffffff;
}

// Same as JS ((x % 1) + 1) % 1; Dart's % on doubles is not JS's, remainder() is.
double _frac(double x) => (x.remainder(1) + 1).remainder(1);

/// Shapes for a single frame at time t (seconds). Paper background is not included.
List<Shape> frameShapes(QR qr, [RenderOptions opts = const RenderOptions(), double t = 0]) =>
    shapesAt(qr, resolve(qr, opts), t);

List<Shape> shapesAt(QR qr, Resolved o, double t) {
  final n = qr.size, dark = qr.dark, fixed = qr.fixed, q = o.quiet, e = o.effect, mid = (n - 1) / 2;
  final out = <Shape>[];
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      final i = r * n + c;
      if (dark[i] == 0 || isFinder(qr, r, c)) continue;
      final cx = c + q + 0.5, cy = r + q + 0.5;
      if (fixed[i] != 0) {
        out.add(Shape(cx, cy, 1, 1, 0, 0, o.ink));
        continue;
      }
      final dr = r - mid, dc = c - mid;
      final p = e.pose(_frac(t / o.duration + e.phase(r, c, math.sqrt(dr * dr + dc * dc), o.rand[i])));
      final w = e.size * p.sx, h = e.size * p.sy;
      out.add(Shape(cx + p.dx, cy + p.dy, w, h, p.rot, e.radius * math.min(w, h), _tint(o.ink, p.hue, p.shade)));
    }
  }
  for (final (r, c) in [(0, 0), (0, n - 7), (n - 7, 0)]) {
    out.addAll(_eye(r + q, c + q, o));
  }
  return out;
}

// concentric 7/5/3 rounded squares keep the 1:1:3:1:1 finder ratio
List<Shape> _eye(int r, int c, Resolved o) {
  Shape at(double side, double rad, Rgb fill) => Shape(c + 3.5, r + 3.5, side, side, 0, rad, fill);
  return [at(7, 1, o.ink), at(5, 0.9, o.paper), at(3, 0.7, o.ink)];
}

class Raster {
  const Raster(this.width, this.height, this.data);

  final int width, height;

  /// RGBA, row-major.
  final Uint8List data;
}

/// Rasterize one frame to RGBA pixels (no anti-aliasing).
Raster rasterize(QR qr, [RenderOptions opts = const RenderOptions(), double t = 0, int scale = 8]) =>
    _raster(qr, resolve(qr, opts), t, scale);

Raster _raster(QR qr, Resolved o, double t, int scale) {
  final w = (qr.size + o.quiet * 2) * scale;
  final data = Uint8List(w * w * 4);
  final (pr, pg, pb) = o.paper;
  for (var i = 0; i < w * w; i++) {
    data[i * 4] = _byte(pr);
    data[i * 4 + 1] = _byte(pg);
    data[i * 4 + 2] = _byte(pb);
    data[i * 4 + 3] = 255;
  }
  for (final s in shapesAt(qr, o, t)) {
    _fillShape(data, w, s, scale);
  }
  return Raster(w, w, data);
}

/// Same conversion as a JS Uint8ClampedArray store: clamp, then round half to even.
int _byte(double v) {
  if (!(v > 0)) return 0;
  if (v >= 255) return 255;
  final f = v.floorToDouble(), d = v - f;
  return (d > 0.5 || (d == 0.5 && f % 2 == 1) ? f + 1 : f).toInt();
}

void _fillShape(Uint8List data, int w, Shape s, int scale) {
  final cx = s.cx * scale, cy = s.cy * scale, hw = (s.w * scale) / 2, hh = (s.h * scale) / 2;
  final rr = math.min(math.min(s.r * scale, hw), hh), a = (s.rot * math.pi) / 180, cos = math.cos(a), sin = math.sin(a);
  final rad = math.sqrt(hw * hw + hh * hh);
  final x0 = math.max(0, (cx - rad).floor()), x1 = math.min(w - 1, (cx + rad).ceil());
  final y0 = math.max(0, (cy - rad).floor()), y1 = math.min(w - 1, (cy + rad).ceil());
  final (fr, fg, fb) = s.fill;
  final br = _byte(fr), bg = _byte(fg), bb = _byte(fb);
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      final lx = (cos * dx + sin * dy).abs(), ly = (-sin * dx + cos * dy).abs();
      final qx = lx - (hw - rr), qy = ly - (hh - rr);
      final ox = math.max(qx, 0.0), oy = math.max(qy, 0.0);
      final outside = math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0.0) - rr;
      if (outside > 0) continue;
      final k = (y * w + x) * 4;
      data[k] = br;
      data[k + 1] = bg;
      data[k + 2] = bb;
    }
  }
}

class VerifyResult {
  const VerifyResult(this.ok, this.frames, this.worst, this.worstAt);

  final bool ok;

  /// Frames checked.
  final int frames;

  /// Most wrong modules seen in any one frame.
  final int worst;

  /// Time (seconds) of the worst frame.
  final double worstAt;

  @override
  String toString() => 'VerifyResult(ok: $ok, frames: $frames, worst: $worst, worstAt: $worstAt)';
}

/// Check that the middle of every module has the right color on every sampled frame. Real decoders
/// don't hit the exact center, so a 3x3 grid of points at the center and ±0.2 modules must all be
/// right. Strict: built-in effects must have zero wrong modules on every frame.
VerifyResult verify(QR qr, [RenderOptions opts = const RenderOptions(), int frames = 48]) {
  // pixel centers 1..3 sit at 0.3, 0.5, 0.7 of a module
  const s = 5;
  final o = resolve(qr, opts), big = qr.size + o.quiet * 2, n = qr.size;
  final threshold = (_luminance(o.ink) + _luminance(o.paper)) / 2;
  var worst = 0;
  var worstAt = 0.0;
  for (var f = 0; f < frames; f++) {
    final t = (f / frames) * o.duration;
    final img = _raster(qr, o, t, s).data;
    var wrong = 0;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final want = qr.dark[r * n + c] != 0;
        check:
        for (var y = 1; y <= 3; y++) {
          for (var x = 1; x <= 3; x++) {
            final k = (((r + o.quiet) * s + y) * big * s + (c + o.quiet) * s + x) * 4;
            final lum = _luminance((img[k].toDouble(), img[k + 1].toDouble(), img[k + 2].toDouble()));
            if ((lum < threshold) != want) {
              wrong++;
              break check;
            }
          }
        }
      }
    }
    if (wrong > worst) {
      worst = wrong;
      worstAt = t;
    }
  }
  return VerifyResult(worst == 0, frames, worst, worstAt);
}

// ---- color helpers ----

final _hexRe = RegExp(r'^#?([0-9a-f]{3}|[0-9a-f]{6})$', caseSensitive: false);

Rgb _parseHex(String s) {
  final m = _hexRe.firstMatch(s.trim());
  if (m == null) throw ArgumentError('color must be #rgb or #rrggbb (got $s)');
  var h = m[1]!;
  if (h.length == 3) h = h.split('').map((ch) => ch + ch).join();
  double at(int i) => int.parse(h.substring(i, i + 2), radix: 16).toDouble();
  return (at(0), at(2), at(4));
}

/// Relative luminance (Rec. 709 / sRGB).
double _luminance(Rgb c) {
  double lin(double v) {
    v /= 255;
    return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  final (r, g, b) = c;
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

Rgb _tint(Rgb rgb, double hue, double shade) {
  if (hue == 0 && shade == 0) return rgb;
  var (h, s, l) = _toHsl(rgb);
  if (hue != 0) s = math.max(s, 0.65);
  return _fromHsl((h + hue) % 360, s, math.min(1.0, math.max(0.0, l + shade)));
}

(double, double, double) _toHsl(Rgb rgb) {
  final r = rgb.$1 / 255, g = rgb.$2 / 255, b = rgb.$3 / 255;
  final max = math.max(r, math.max(g, b)), min = math.min(r, math.min(g, b)), l = (max + min) / 2, d = max - min;
  if (d == 0) return (0, 0, l);
  final s = d / (1 - (2 * l - 1).abs());
  final h = max == r
      ? ((g - b) / d + 6).remainder(6)
      : max == g
          ? (b - r) / d + 2
          : (r - g) / d + 4;
  return (h * 60, s, l);
}

Rgb _fromHsl(double h, double s, double l) {
  final c = (1 - (2 * l - 1).abs()) * s, x = c * (1 - ((h / 60).remainder(2) - 1).abs()), m = l - c / 2;
  final (r, g, b) = h < 60
      ? (c, x, 0.0)
      : h < 120
          ? (x, c, 0.0)
          : h < 180
              ? (0.0, c, x)
              : h < 240
                  ? (0.0, x, c)
                  : h < 300
                      ? (x, 0.0, c)
                      : (c, 0.0, x);
  return ((r + m) * 255, (g + m) * 255, (b + m) * 255);
}
