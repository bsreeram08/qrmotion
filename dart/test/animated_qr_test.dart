import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrmotion/qrmotion.dart';

Widget host(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(textDirection: TextDirection.ltr, child: Center(child: child)),
    );

void main() {
  testWidgets('animates every effect without errors', (tester) async {
    for (final effect in QrEffect.values) {
      await tester.pumpWidget(host(AnimatedQr(text: 'https://example.com', effect: effect, size: 240)));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.getSize(find.byType(AnimatedQr)), const Size(240, 240));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 1900));
      expect(tester.hasRunningAnimations, effect != QrEffect.none);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reduced motion renders a still frame', (tester) async {
    await tester.pumpWidget(host(const AnimatedQr(text: 'https://example.com'), reduceMotion: true));
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('QR code: https://example.com'), findsOneWidget);

    // turning reduced motion off starts the animation
    await tester.pumpWidget(host(const AnimatedQr(text: 'https://example.com')));
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets('updates text, colors and duration', (tester) async {
    await tester.pumpWidget(host(const AnimatedQr(text: 'a', size: 100)));
    await tester.pumpWidget(host(const AnimatedQr(
        text: 'b', ink: Color(0xFF0B3A40), duration: Duration(seconds: 1), effect: QrEffect.flip, size: 100)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('low contrast throws', (tester) async {
    await tester.pumpWidget(host(const AnimatedQr(text: 'a', ink: Color(0xFF999999), paper: Color(0xFFAAAAAA))));
    expect(tester.takeException(), isA<RangeError>());
  });
}
