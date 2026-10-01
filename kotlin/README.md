# qrmotion for Kotlin

Animated QR codes where every frame still scans. This is the Kotlin port of the [TypeScript library](../README.md). It produces the same output: the parity tests check it against `../fixtures/parity.json`.

- `qrmotion-core`: pure Kotlin/JVM with **zero dependencies** (stdlib only). It contains the encoder, effects, frame shapes, an RGBA rasterizer and `verify()`. The QR encoder is a port of [Project Nayuki's](https://www.nayuki.io/page/qr-code-generator-library) library (MIT).
- `qrmotion-compose`: the `AnimatedQr` composable. It depends only on Compose and core.

## Install

```kotlin
// not published yet
implementation("io.github.bsreeram08:qrmotion-compose:0.1.0")
implementation("io.github.bsreeram08:qrmotion-core:0.1.0") // JVM only, no Compose
```

## Compose

```kotlin
AnimatedQr(
    text = "https://example.com",
    modifier = Modifier.size(240.dp),
    effect = Effects.Flip,
    ecc = Ecc.Q,
    ink = Color(0xFF0B3A40),
    paper = Color(0xFFF5F2EA),
    durationMillis = 2400,
)
```

Each frame only redraws the Canvas. Nothing recomposes. If the system animator duration scale is 0 (reduced motion), the composable shows a static first frame.

## Core

```kotlin
val qr = encode("https://example.com", Ecc.Q)
val options = RenderOptions(effect = Effects.Jiggle, ink = Rgb.hex("#0b3a40"))

verify(qr, options)                   // VerifyResult(ok=true, frames=48, worst=0, worstAt=0.0)
frameShapes(qr, options, t = 0.7)     // rounded boxes in module units
rasterize(qr, options, t = 0.7)       // RGBA ByteArray, 8 px per module

val anim = QrAnimation(qr, options)   // reuse across frames
anim.shapes(t)
```

`encode` and `RenderOptions` throw `IllegalArgumentException` in two cases: the text does not fit, or the ink is not much darker than the paper (luminance gap below 0.4).

## Effects

| Effect | What moves |
|---|---|
| `Effects.Slide` (default) | Rows of boxes glide left and right in opposite directions, in a wave |
| `Effects.Jiggle` | Each box shakes and tilts on its own rhythm |
| `Effects.Flip` | Boxes turn like tiles in a diagonal wave |
| `Effects.Ripple` | Round dots swell and shrink in a wave from the center |
| `Effects.Spectrum` | Hue flows across the code, lightness stays fixed |
| `Effects.Morph` | Boxes spin and pulse in a wave from the center |
| `Effects.None` | Static styled code |

For a custom effect, implement `Effect` (`size`, `radius`, `phase()`, `pose()`) and run `verify()` on it before you ship it.

## Why it scans

Scanners read the middle of each module. qrmotion never animates the finder eyes, timing lines, alignment squares, format/version info or the quiet zone. Every other box covers the middle of its own module (center ±0.2 modules) and stays out of its neighbors' middles. `verify()` renders frames and checks a 3×3 grid of points (0.3, 0.5 and 0.7 of a module) inside every module. It fails if any single module reads wrong in any frame.

## Build

```sh
./gradlew :core:test :compose:assembleRelease
```

## License

MIT
