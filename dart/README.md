# qrmotion

Animated QR codes for Flutter where every frame still scans. Boxes slide, jiggle, flip, ripple, spin and change color, and a built-in verifier checks every frame.

- **Zero dependencies** beyond the Flutter SDK. The QR encoder is a Dart port of [Project Nayuki's](https://www.nayuki.io/page/qr-code-generator-library) (MIT).
- Same math as the TypeScript package [`@bsreeram08/qrmotion`](https://www.npmjs.com/package/@bsreeram08/qrmotion): same seed, same frame, same shapes.
- Respects reduced motion: shows a still frame when the platform asks for it.

## Install

```sh
flutter pub add qrmotion
```

## Use

```dart
import 'package:qrmotion/qrmotion.dart';

AnimatedQr(
  text: 'https://example.com',
  effect: QrEffect.slide,          // default
  ecc: Ecc.q,                      // l | m | q | h
  ink: const Color(0xFF0B3A40),    // must be much darker than paper
  paper: const Color(0xFFF5F2EA),
  duration: const Duration(milliseconds: 2400),
  size: 240,                       // null fills the available width
)
```

Pure-Dart core, no widgets needed:

```dart
final qr = encode('https://example.com', Ecc.q);
const opts = RenderOptions(effect: QrEffect.flip, ink: '#0b3a40');
verify(qr, opts);                  // VerifyResult(ok: true, frames: 48, worst: 0, ...)
frameShapes(qr, opts, 0.7);        // the boxes at t = 0.7 s
rasterize(qr, opts, 0.7, 8);       // RGBA pixels
```

### Effects

| Effect | What moves |
|---|---|
| `slide` (default) | Rows of boxes glide left and right in opposite directions, in a wave |
| `jiggle` | Each box shakes and tilts on its own rhythm |
| `flip` | Boxes turn like tiles in a diagonal wave |
| `ripple` | Round dots swell and shrink in a wave from the center |
| `spectrum` | Hue flows across the code, lightness stays fixed |
| `morph` | Boxes spin and pulse in a wave from the center |
| `none` | Static styled code |

Bring your own with `Effect.of(size:, radius:, phase:, pose:)` or by subclassing `Effect`, then run `verify()` on it.

### Why it scans

Scanners read the middle of each module. qrmotion never animates the finder eyes, timing lines, alignment squares, format/version info or quiet zone. Every other box keeps the middle of its own module covered (center ±0.2 modules) and stays out of its neighbors' middles. In practice that limits sideways movement to about a quarter of a module.

`verify()` renders frames and checks a 3×3 grid of points inside every module, with zero wrong modules allowed on any frame. Low-contrast colors (luminance gap under 0.4) throw a `RangeError`.

Built-in effects have only been machine-tested so far. Test with iPhone Camera and Google Lens before relying on them in print.

## License

MIT. Includes a port of Project Nayuki's QR Code generator (MIT).
