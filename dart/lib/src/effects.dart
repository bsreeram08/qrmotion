import 'dart:math' as math;

/// How one data module looks at cycle position u. Offsets are in modules, rotation in degrees.
///
/// Safety rule every built-in effect follows: the box always covers the middle of its own module
/// (center ±0.2 modules) and never reaches the middle of a neighbor's. `verify()` checks it.
/// In practice that caps sideways movement at about a quarter of a module.
class Pose {
  const Pose({this.dx = 0, this.dy = 0, this.sx = 1, this.sy = 1, this.rot = 0, this.hue = 0, this.shade = 0});

  final double dx, dy, sx, sy, rot;

  /// Hue rotation in degrees applied to the ink. Lightness is kept.
  final double hue;

  /// Lightness change applied to the ink, e.g. -0.05.
  final double shade;
}

/// An animation. Subclass it, or use [Effect.of], then run `verify()` on it.
abstract class Effect {
  const Effect();

  factory Effect.of({
    required String name,
    String description,
    required double size,
    required double radius,
    required double Function(int r, int c, double d, double rand) phase,
    required Pose Function(double u) pose,
  }) = _FnEffect;

  String get name;
  String get description;

  /// Box side as a fraction of a module.
  double get size;

  /// Corner radius as a fraction of the box side (0.5 = circle).
  double get radius;

  /// Cycle offset for a module. d = distance from the symbol center in modules, rand = stable random 0..1.
  double phase(int r, int c, double d, double rand);

  /// Pose at cycle position u in [0, 1). Must be periodic.
  Pose pose(double u);
}

class _FnEffect extends Effect {
  const _FnEffect({
    required this.name,
    this.description = '',
    required this.size,
    required this.radius,
    required double Function(int r, int c, double d, double rand) phase,
    required Pose Function(double u) pose,
  })  : _phase = phase,
        _pose = pose;

  @override
  final String name, description;
  @override
  final double size, radius;
  final double Function(int r, int c, double d, double rand) _phase;
  final Pose Function(double u) _pose;

  @override
  double phase(int r, int c, double d, double rand) => _phase(r, c, d, rand);
  @override
  Pose pose(double u) => _pose(u);
}

const _tau = math.pi * 2;

/// Built-in effects. All pass `verify()`.
enum QrEffect implements Effect {
  slide('Rows of boxes glide left and right in opposite directions, in a wave.', 0.92, 0.12),
  jiggle('Each box shakes and tilts on its own rhythm.', 0.9, 0.1),
  flip('Boxes turn like tiles in a diagonal wave, stopping before they go edge-on.', 0.92, 0.1),
  ripple('Round dots swell and shrink in a wave from the center.', 1, 0.5),
  spectrum('Hue flows across the code while lightness stays fixed.', 0.9, 0.32),
  morph('Boxes spin and pulse in a wave from the center.', 0.82, 0.25),
  none('No animation. A plain styled QR code.', 1, 0);

  const QrEffect(this.description, this.size, this.radius);

  @override
  String get name => EnumName(this).name;
  @override
  final String description;
  @override
  final double size, radius;

  @override
  double phase(int r, int c, double d, double rand) => switch (this) {
        QrEffect.slide => r * 0.07 + (r % 2) * 0.5,
        QrEffect.jiggle => rand,
        QrEffect.flip => -(r + c) * 0.045,
        QrEffect.ripple => -d * 0.1,
        QrEffect.spectrum => (r + c) * 0.017,
        QrEffect.morph => d * 0.04,
        QrEffect.none => 0,
      };

  @override
  Pose pose(double u) {
    switch (this) {
      case QrEffect.slide:
        return Pose(dx: 0.25 * math.sin(_tau * u));
      case QrEffect.jiggle:
        return Pose(
            dx: 0.18 * math.sin(_tau * u), dy: 0.18 * math.sin(2 * _tau * u + 1), rot: 8 * math.sin(3 * _tau * u));
      case QrEffect.flip:
        final k = math.cos(_tau * u);
        return Pose(sx: 0.5 + 0.5 * k.abs(), shade: k < 0 ? 0.06 : 0);
      case QrEffect.ripple:
        final s = 0.7 + 0.3 * (0.5 + 0.5 * math.sin(_tau * u));
        return Pose(sx: s, sy: s);
      case QrEffect.spectrum:
        return Pose(hue: 360 * u);
      case QrEffect.morph:
        final s = 0.9 + 0.1 * math.sin(_tau * u);
        return Pose(sx: s, sy: s, rot: 360 * u);
      case QrEffect.none:
        return const Pose();
    }
  }
}

/// Look up a built-in effect by name. Throws [ArgumentError] for unknown names.
Effect resolveEffect(String name) {
  for (final e in QrEffect.values) {
    if (e.name == name) return e;
  }
  throw ArgumentError('unknown effect "$name". Use one of: ${QrEffect.values.map((e) => e.name).join(', ')}');
}
