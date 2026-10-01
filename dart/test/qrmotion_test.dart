import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:qrmotion/qrmotion.dart';

const text = 'https://example.com/animated-qr?ref=qrmotion';

Ecc eccOf(String s) => Ecc.values.byName(s.toLowerCase());

void main() {
  final fixture = jsonDecode(File('../fixtures/parity.json').readAsStringSync()) as Map<String, dynamic>;

  group('parity with the TypeScript reference', () {
    for (final m in (fixture['matrices'] as List).cast<Map<String, dynamic>>()) {
      test('matrix "${(m['text'] as String).length > 24 ? '${(m['text'] as String).substring(0, 24)}...' : m['text']}" @ ${m['eccRequested']}', () {
        final qr = encode(m['text'] as String, eccOf(m['eccRequested'] as String));
        expect(qr.ecc.name.toUpperCase(), m['ecc']);
        expect(qr.version, m['version']);
        expect(qr.size, m['size']);
        expect(qr.dark.join(), m['dark']);
        expect(qr.fixed.join(), m['fixed']);
      });
    }

    for (final f in (fixture['frames'] as List).cast<Map<String, dynamic>>()) {
      test('frame ${f['effect']} t=${f['t']}', () {
        final qr = encode(f['text'] as String, eccOf(f['ecc'] as String));
        final opts = RenderOptions(
            effect: resolveEffect(f['effect'] as String),
            seed: f['seed'] as int,
            duration: (f['duration'] as num).toDouble());
        final got = frameShapes(qr, opts, (f['t'] as num).toDouble());
        final want = (f['shapes'] as List).cast<List<dynamic>>();
        expect(got.length, want.length);
        for (var i = 0; i < got.length; i++) {
          final s = got[i], w = want[i].cast<num>();
          final geo = [s.cx, s.cy, s.w, s.h, s.rot, s.r], rgb = [s.fill.$1, s.fill.$2, s.fill.$3];
          for (var k = 0; k < 6; k++) {
            expect((geo[k] - w[k]).abs(), lessThan(1e-4), reason: 'shape $i field $k');
          }
          for (var k = 0; k < 3; k++) {
            expect((rgb[k] - w[6 + k]).abs(), lessThan(0.5), reason: 'shape $i color $k');
          }
        }
      });
    }

    for (final v in (fixture['verify'] as List).cast<Map<String, dynamic>>()) {
      test('verify ${v['effect']}', () {
        final r = verify(encode('https://example.com'), RenderOptions(effect: resolveEffect(v['effect'] as String)),
            v['frames'] as int);
        expect(r.ok, v['ok']);
        expect(r.worst, v['worst']);
        expect(r.frames, v['frames']);
      });
    }
  });

  group('every frame scans', () {
    for (final effect in QrEffect.values) {
      for (final ecc in [Ecc.l, Ecc.h]) {
        test('${effect.name} @ ${ecc.name}', () {
          final v = verify(encode(text, ecc), RenderOptions(effect: effect));
          expect(v.ok, isTrue, reason: '$v');
          expect(v.worst, 0);
        });
      }
    }

    test('large version with alignment and version info', () {
      final qr = encode('x' * 400, Ecc.m);
      expect(qr.version, greaterThanOrEqualTo(7));
      expect(verify(qr, const RenderOptions(effect: QrEffect.jiggle), 12).ok, isTrue);
    });
  });

  test('verify catches an unsafe effect', () {
    final drift = Effect.of(
      name: 'drift',
      description: 'moves boxes off their centers',
      size: 0.9,
      radius: 0.5,
      phase: (r, c, d, rand) => rand,
      pose: (u) => Pose(dx: 0.6 * math.cos(2 * math.pi * u), dy: 0.6 * math.sin(2 * math.pi * u)),
    );
    final v = verify(encode(text), RenderOptions(effect: drift), 12);
    expect(v.ok, isFalse);
    expect(v.worst, greaterThan(0));
  });

  test('rejects low contrast and bad input', () {
    final qr = encode(text);
    expect(() => frameShapes(qr, const RenderOptions(ink: '#999', paper: '#aaa')),
        throwsA(isA<RangeError>().having((e) => e.message, 'message', contains('darker'))));
    expect(() => frameShapes(qr, const RenderOptions(ink: 'red')),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('#rgb'))));
    expect(() => encode('x' * 5000), throwsRangeError);
    expect(() => resolveEffect('nope'),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('unknown effect'))));
    expect(() => frameShapes(qr, const RenderOptions(duration: 0)), throwsRangeError);
  });

  test('rasterize size and paper', () {
    final qr = encode('hi');
    final img = rasterize(qr, const RenderOptions(), 0, 2);
    expect(img.width, (qr.size + 8) * 2);
    expect(img.data.length, img.width * img.height * 4);
    expect(img.data.sublist(0, 4), [0xf5, 0xf2, 0xea, 255]);
  });
}
