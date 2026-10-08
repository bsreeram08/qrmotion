# Changelog

All notable changes to `@bsreeram08/qrmotion` are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/), and the project uses [semantic versioning](https://semver.org/).

## [0.2.0] - 2026-10-08

### Added
- **Gradient body.** Pass `inkTo` to fill the modules with a gradient from `ink` to `inkTo` (SVG output). `gradient: 'linear' | 'radial'` and `angle` control its shape. Both stops are held to the same contrast guard as `ink`, and the gradient spans the whole symbol rather than tiling per module. CLI: `--ink-to`, `--gradient`, `--angle`.
- **Custom finder eyes.** `eyeColor` recolors the finder eyes (defaults to `ink`), and `eyeShape: 'square' | 'rounded'` picks their corner style. `eyeColor` flows through `verify()`, so a too-light eye is rejected. CLI: `--eye-color`, `--eye-shape`.

These are additive and backward compatible: existing calls render identically.

## [0.1.2]

- Animated QR codes where every frame still scans: `slide`, `jiggle`, `flip`, `ripple`, `spectrum`, `morph`, `none` effects, SVG/canvas/RGBA/terminal output, a built-in `verify()`, a JSON-Schema tool definition, and an MCP server.
- Flutter (`dart/`) and Kotlin (`kotlin/`) ports with shared parity fixtures.

[0.2.0]: https://github.com/bsreeram08/qrmotion/releases/tag/v0.2.0
