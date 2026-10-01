import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'effects.dart';
import 'qr.dart';
import 'render.dart';

/// An animated QR code. Every frame scans.
///
/// Draws with a [CustomPainter] that repaints on its own; the rest of the tree is untouched.
/// When the platform asks for reduced motion ([MediaQuery.disableAnimationsOf]) it shows a still
/// frame at t = 0. With [size] null it fills the available width as a square.
///
/// Throws [RangeError] if the text does not fit or [ink] is not much darker than [paper]
/// (luminance gap of at least 0.4). Alpha in [ink] and [paper] is ignored.
class AnimatedQr extends StatefulWidget {
  const AnimatedQr({
    super.key,
    required this.text,
    this.effect = QrEffect.slide,
    this.ecc = Ecc.q,
    this.ink = const Color(0xFF17132A),
    this.paper = const Color(0xFFF5F2EA),
    this.duration = const Duration(milliseconds: 2400),
    this.size,
  });

  final String text;

  /// A built-in [QrEffect] or a custom [Effect]. Run `verify()` on custom effects.
  final Effect effect;
  final Ecc ecc;
  final Color ink;
  final Color paper;

  /// One animation cycle.
  final Duration duration;

  /// Side length in logical pixels, quiet zone included.
  final double? size;

  @override
  State<AnimatedQr> createState() => _AnimatedQrState();
}

class _AnimatedQrState extends State<AnimatedQr> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: widget.duration);
  late QR _qr;
  late Resolved _o;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _qr = encode(widget.text, widget.ecc);
    _o = _resolve();
  }

  Resolved _resolve() => resolve(
        _qr,
        RenderOptions(
          effect: widget.effect,
          ink: _hex(widget.ink),
          paper: _hex(widget.paper),
          duration: widget.duration.inMicroseconds / Duration.microsecondsPerSecond,
        ),
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(AnimatedQr old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.ecc != widget.ecc) _qr = encode(widget.text, widget.ecc);
    if (old.text != widget.text ||
        old.ecc != widget.ecc ||
        old.effect != widget.effect ||
        old.ink != widget.ink ||
        old.paper != widget.paper ||
        old.duration != widget.duration) {
      _o = _resolve();
    }
    if (old.duration != widget.duration) {
      _clock.duration = widget.duration;
      if (_clock.isAnimating) _clock.repeat();
    }
    _sync();
  }

  void _sync() {
    if (_reduceMotion || widget.effect == QrEffect.none) {
      _clock
        ..stop()
        ..value = 0;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paint = RepaintBoundary(
      child: CustomPaint(painter: _QrPainter(_qr, _o, _clock), willChange: _clock.isAnimating),
    );
    final size = widget.size;
    return Semantics(
      label: 'QR code: ${widget.text}',
      image: true,
      child: size == null ? AspectRatio(aspectRatio: 1, child: paint) : SizedBox.square(dimension: size, child: paint),
    );
  }
}

String _hex(Color c) => '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';

class _QrPainter extends CustomPainter {
  _QrPainter(this.qr, this.o, this.clock) : super(repaint: clock);

  final QR qr;
  final Resolved o;
  final Animation<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide, scale = side / (qr.size + o.quiet * 2);
    final fill = Paint();
    canvas.drawRect(Offset.zero & Size.square(side), fill..color = _color(o.paper));
    // clock.value is the cycle position, so t / duration == value
    for (final s in shapesAt(qr, o, clock.value * o.duration)) {
      fill
        ..color = _color(s.fill)
        // crisp edges for axis-aligned squares so adjacent fixed modules tile without seams
        ..isAntiAlias = s.rot != 0 || s.r != 0;
      final rect = Rect.fromCenter(center: Offset.zero, width: s.w * scale, height: s.h * scale);
      canvas
        ..save()
        ..translate(s.cx * scale, s.cy * scale);
      if (s.rot != 0) canvas.rotate(s.rot * math.pi / 180);
      if (s.r == 0) {
        canvas.drawRect(rect, fill);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(s.r * scale)), fill);
      }
      canvas.restore();
    }
  }

  static Color _color(Rgb c) =>
      Color.fromARGB(255, c.$1.round().clamp(0, 255), c.$2.round().clamp(0, 255), c.$3.round().clamp(0, 255));

  @override
  bool shouldRepaint(_QrPainter old) => old.qr != qr || old.o != o || old.clock != clock;
}
