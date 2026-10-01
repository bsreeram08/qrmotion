# Animated QR Codes: Research Notes

*Researched 2026-10-01. GitHub stats (stars, last push) were pulled from the GitHub REST API on that date. Every claim links to its source. Claims marked **unverified** have no primary source behind them, or are my own inference.*

"Animated QR" means two different things, so this doc covers both:

- **A. Visual animation of one payload.** Every frame encodes the same data, and the motion is decorative.
- **B. Multi-frame data streams.** Each frame carries a different chunk, and a fountain code rebuilds the whole payload.

---

## 1. QR spec constraints (ISO/IEC 18004)

**Source note:** The current standard is **ISO/IEC 18004:2024** (4th edition, Aug 2024, revises the 2015 edition) and it is paywalled ([ANSI blog](https://blog.ansi.org/ansi/iso-iec-18004-2024-qr-code-bar-code-symbology/), [iTeh catalog](https://www.standards.iteh.ai/catalog/standards/iso/1a0badd4-8d6c-47e7-98fa-ccaddd7cd9a6/iso-iec-18004-2024)). The facts below come from three places: the free preview of **ISO/IEC 18004:2000** ([iTeh sample PDF](https://cdn.standards.iteh.ai/samples/30789/795f08fcf6c444eba142f8036ada6f8d/ISO-IEC-18004-2000.pdf)), **Thonky's QR tutorial**, and reference-implementation source code. I did not check them against the 2024 text.

| Item | Constraint | Source |
|---|---|---|
| Size | 21×21 (V1) to 177×177 (V40) modules, growing 4 modules per side per version | [ISO 18004:2000 sample §6](https://cdn.standards.iteh.ai/samples/30789/795f08fcf6c444eba142f8036ada6f8d/ISO-IEC-18004-2000.pdf) |
| Max capacity (V40-L) | 7,089 numeric / 4,296 alphanumeric / 2,953 bytes / 1,817 Kanji | same |
| ECC levels | Recover L 7%, M 15%, Q 25%, H 30% "of the symbol codewords" | same; [Thonky intro](https://www.thonky.com/qr-code-tutorial/introduction) |
| Function patterns | "Function patterns shall not be used for the encodation of data"; the symbol "shall be surrounded on all four sides by a quiet zone" | [ISO sample §7.3](https://cdn.standards.iteh.ai/samples/30789/795f08fcf6c444eba142f8036ada6f8d/ISO-IEC-18004-2000.pdf) |
| Quiet zone | 4 modules. The ISO preview pages don't include the clause. ZXing's writer hard-codes `QUIET_ZONE_SIZE = 4` | [ZXing QRCodeWriter.java](https://github.com/zxing/zxing/blob/master/core/src/main/java/com/google/zxing/qrcode/QRCodeWriter.java) (ISO clause itself unverified) |
| Finder patterns | Three 7×7 squares with a 1:1:3:1:1 ratio, plus 1-module white separators | [Thonky module placement](https://www.thonky.com/qr-code-tutorial/module-placement-matrix) |
| Timing patterns | Alternating modules along row 6 and column 6, between the finders | same |
| Alignment patterns | 5×5, present from V2 up | same |
| Dark module | Always dark, at (8, 4V+9) | same |
| Format info | 15 bits (2 for EC level + 3 for mask + 10 BCH), XOR'd with `101010000010010`, stored **twice** | [Thonky format/version](https://www.thonky.com/qr-code-tutorial/format-version-information) |
| Version info | V7+ only: 18 bits (Golay), stored twice in 6×3 blocks | same |
| Masking | 8 masks applied to data and EC modules only. The encoder picks the mask with the lowest penalty across 4 rules (runs, 2×2 blocks, finder-like patterns, dark/light balance) | [Thonky masking](https://www.thonky.com/qr-code-tutorial/data-masking) |
| Interleaving | Codewords from different blocks are interleaved round-robin, so damage in one spot is spread across blocks | [Thonky final structure](https://www.thonky.com/qr-code-tutorial/structure-final-message) |

### EC budget by codeword (examples from [Thonky's EC table](https://www.thonky.com/qr-code-tutorial/error-correction-table))

| Version-ECC | Data codewords | EC codewords per block |
|---|---|---|
| 1-L / 1-H | 19 / 9 | 7 / 17 |
| 10-M / 10-H | 216 / 122 | 26 / 28 |
| 40-L / 40-H | 2,956 / 1,276 | 30 / 30 |

- Reed–Solomon with *e* EC codewords per block fixes up to ⌊e/2⌋ codewords at unknown positions, or up to *e* erasures. This is a standard RS property. I did not check it against the ISO text, but it fits nayuki's comment that "H… can tolerate about 30% erroneous codewords" ([nayuki qrcodegen.ts](https://github.com/nayuki/QR-Code-generator/blob/master/typescript-javascript/qrcodegen.ts)).
- **What this means for decoration:** the budget is counted **per RS block, in codewords**, not in modules. One codeword covers 8 modules, so a small blob that crosses codeword boundaries can use up 2–4 codewords. Decoration budgets therefore have to be checked against the codeword map, not as a share of total area.

---

## 2. Interpretation A: visually animated single-payload QR

### 2.1 How decoders actually read a module (why some styling works)

- **They sample module centers.** jsQR samples each grid cell at `x + 0.5, y + 0.5`, after a perspective transform ([jsQR extractor](https://github.com/cozmo/jsQR/blob/master/src/extractor/index.ts)). This is why dots, rounded shapes, and halftone styles scan: only the center region needs the right luminance.
- **They threshold luminance locally, not by hue.** jsQR converts to grayscale with `0.2126R + 0.7152G + 0.0722B`, thresholds over 8×8 px regions, and treats a region as flat when its dynamic range is ≤24 ([jsQR binarizer](https://github.com/cozmo/jsQR/blob/master/src/binarizer/index.ts)). ZXing's `HybridBinarizer` also uses local thresholding and is "designed for… black data on white backgrounds" ([ZXing docs](https://zxing.github.io/zxing/apidocs/com/google/zxing/common/HybridBinarizer.html)).
  - Consequence: color animation is safe only if **luminance contrast** holds. Changing hue at constant lightness is fine. Animating lightness is risky.
- **Inverted codes (light on dark) are opt-in in some decoders.** jsQR's `inversionAttempts` defaults to `attemptBoth` but "will probably be default to `dontInvert` in future versions" ([jsQR README](https://github.com/cozmo/jsQR)). Default to dark-on-light.
- **Resolution floor.** ML Kit requires at least 2 px per module ([ML Kit guidelines](https://developers.google.com/ml-kit/vision/barcode-scanning/android)).

### 2.2 What must stay static and intact

| Region | Animate? | Why |
|---|---|---|
| Quiet zone (4 modules) | No. Keep it flat, light, and free of motion or particles | Separates the code from the background ([ISO §7.3](https://cdn.standards.iteh.ai/samples/30789/795f08fcf6c444eba142f8036ada6f8d/ISO-IEC-18004-2000.pdf)) |
| 3 finder patterns plus separators | Shape can be stylized, but keep the 1:1:3:1:1 profile and keep it static | Detection relies on that ratio ([Thonky](https://www.thonky.com/qr-code-tutorial/module-placement-matrix)) |
| Alignment patterns (V2+) | Static | Used to correct perspective (same source). AnimQR also never animates them ([AnimQR README](https://github.com/AnimQR/AnimQR.github.io)) |
| Timing patterns | Static, full contrast | Grid estimation (same). Exactly how much each decoder depends on them: unverified |
| Format info (both copies) and version info (V7+, both copies) | Static | BCH/Golay protected but tiny. Losing both copies kills the decode ([Thonky](https://www.thonky.com/qr-code-tutorial/format-version-information)) |
| Data and EC modules | Can animate within a per-block codeword budget | See §1 |

### 2.3 Techniques and prior art

| Technique | How it stays scannable | Source |
|---|---|---|
| Module shapes (dots, rounded, classy), gradients, and a logo with `hideBackgroundDots` | Module centers survive. The logo uses up EC budget | [qr-code-styling](https://github.com/kozakdenys/qr-code-styling) |
| Preset intro animations (MaterializeIn, RadialRipple…) on an SVG web component | Animates *into* a valid static code. Not every frame scans | [bitjson/qr-code](https://github.com/bitjson/qr-code) |
| Looping animations (pulse, wave, shimmer, rotate, color cycle, scan line, reveal, particles) | "Animations never touch the three finder patterns or the alignment patterns". Modules stay ≥75% size and ≥55% opacity. Color cycling keeps lightness constant. Reveal and particles only scan during their hold phase. A test decodes 10 frames for every shape × animation pair with jsQR | [AnimQR README](https://github.com/AnimQR/AnimQR.github.io) |
| QArt: picture made from the data/EC bits themselves | Reed–Solomon codewords can be XOR'd, so Gauss–Jordan elimination over a basis lets you choose pixel values. The mask is chosen up front, and the code is rotated to move fixed regions | [Russ Cox, QArt Codes](https://research.swtch.com/qart) |
| Halftone QR | Each module is split into sub-modules, guided by a learned readability model | [Chu et al., SIGGRAPH Asia 2013, ACM TOG 32(6)](https://dl.acm.org/doi/10.1145/2508363.2508408) |
| AI art (ControlNet QR Monster v2) | Conditioning image with a 16 px module size. Higher EC level helps. Use a gray (#808080) background to blend. "Not all generated codes might be readable", so raise the guidance scale for readability | [HF model card](https://huggingface.co/monster-labs/control_v1p_sd15_qrcode_monster) (license openrail++) |
| AI QR repair tooling | Diffs the generated image against the source matrix to find "misaligned pixels". Mask choice changes the composition. Some mismatches are fine thanks to EC | [antfu/qrcode-toolkit](https://github.com/antfu/qrcode-toolkit), [blog](https://antfu.me/posts/ai-qrcode-refine) |

### 2.4 How real scanners handle frames that move or change

- **ML Kit and CameraX drop frames while busy.** Docs say to "drop the frame" if one arrives during detection, and use `STRATEGY_KEEP_ONLY_LATEST` ([ML Kit](https://developers.google.com/ml-kit/vision/barcode-scanning/android)). The scanner sees an arbitrary subsample of your animation, so **every frame should decode on its own**. A frame that only scans in some phases will cost you scans.
- **Camera exposure spans display refreshes.** QRFerry holds each code for 2–4 display refreshes so "one remains stable during every display transition" ([deedy/qr-data-transfer README](https://github.com/deedy/qr-data-transfer)). A frame captured mid-transition is effectively a **blend of two frames**, so a validator should test blended frames too. (Applying this to decorative animation is my inference: unverified.)
- **Web:** the `BarcodeDetector` API is experimental and not Baseline ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/Barcode_Detection_API)). nimiq/qr-scanner uses it when present and otherwise falls back to a WebWorker decoder ([qr-scanner README](https://github.com/nimiq/qr-scanner)).
- **iOS Camera app, Google Lens, Apple Vision `VNDetectBarcodesRequest`:** their behavior on animated or changing codes (debounce, how many frames before triggering, color tolerance) is **unverified**. Apple's doc page wouldn't render, and Google doesn't document Lens internals. Test on real devices.
- **zbar:** its behavior with animated codes is **unverified**. Include it in the test matrix ([mchehab/zbar](https://github.com/mchehab/zbar)).

---

## 3. Interpretation B: multi-frame QR data streams

### 3.1 Coding schemes

| Scheme | Key facts | Source |
|---|---|---|
| LT (Luby Transform) | Rateless. The receiver can rebuild from any slightly-more-than-k symbols. Used by txqr (via `google/gofountain`), qifi/qrs, and BC-UR | [divan fountain post](https://divan.dev/posts/fountaincodes/), [qifi-dev/qrs](https://github.com/qifi-dev/qrs) |
| RaptorQ (RFC 6330) | A Raptor-family fountain code. QRFerry compiles it to WASM | [RFC 6330](https://www.rfc-editor.org/rfc/rfc6330), [deedy/qr-data-transfer](https://github.com/deedy/qr-data-transfer) |
| **BC-UR / Multipart UR (MUR)** | Format `ur:<type>/<seqNum>-<seqLen>/<fragment>`. The first `seqLen` parts are plain fragments (fixed-rate). Parts with `seqNum > seqLen` are XOR mixes. Which fragments go into a mix is derived from Xoshiro256** seeded by SHA-256(CRC-32 of message), so no extra metadata is needed. Degree is sampled with harmonic weights (1/1, 1/2 … 1/seqLen). Data is Bytewords-encoded and sent in **QR alphanumeric mode** | [BCR-2020-005](https://github.com/BlockchainCommons/Research/blob/master/papers/bcr-2020-005-ur.md), [BCR-2024-001 MUR guide](https://github.com/BlockchainCommons/Research/blob/master/papers/bcr-2024-001-multipart-ur.md) |
| BBQr (Coinkite) | Base32 or hex in alphanumeric mode, optional ZLIB (about 30% savings on PSBTs). Built for memory-limited hardware wallets | [coinkite/BBQr](https://github.com/coinkite/BBQr) |
| cimbar (not QR) | Color icon tiles with RS and wirehair fountain codes. Claims ~106 KB/s from a monitor to a phone | [sz3/libcimbar](https://github.com/sz3/libcimbar) |

### 3.2 Throughput numbers (all self-reported by authors)

| Project | Setup | Result |
|---|---|---|
| txqr (pre-fountain) | 6–7 FPS was optimal. 550–900 B chunks were reliable, 1,000 B "almost guaranteed miss of frames". ECC L | Typically 1–2 KB/s, best ~9 KB/s ([divan](https://divan.dev/posts/animatedqr/)) |
| txqr + LT | 12 FPS, 1,850 B/frame, ECC L | ~25 kbps record (13 KB in 501 ms as reported). Most decodes under 4 s ([divan](https://divan.dev/posts/fountaincodes/)). *The numbers reported in that post don't add up internally; recheck before quoting* |
| QRFerry | V30-L at 15–30 FPS. "Turbo 60" uses two alternating V30-L lanes | Nominal 1.40 Mbps optical channel "before camera loss" in the lab profile ([README](https://github.com/deedy/qr-data-transfer)). Real-world rate: unverified |
| bc-mur-ts example | `maxFragmentLen: 100`, `maxModules: 117`, 8 FPS GIF | Example config only ([bc-mur-ts](https://github.com/BlockchainCommons/bc-mur-ts)) |

The MUR guide declines to recommend a fixed fragment size. It depends on display size, camera resolution, frame rate, and distance ([BCR-2024-001](https://github.com/BlockchainCommons/Research/blob/master/papers/bcr-2024-001-multipart-ur.md)).

### 3.3 Ecosystem

- **Air-gapped wallets:** Keystone uses bc-ur for animated QR (UR 2.0) ([Keystone dev hub](https://github.com/KeystoneHQ/Keystone-developer-hub/blob/main/Integration_guide.md)). Others include Sparrow ([sparrowwallet/sparrow](https://github.com/sparrowwallet/sparrow), plus the Java UR lib [hummingbird](https://github.com/sparrowwallet/hummingbird)) and Specter-DIY ([repo](https://github.com/cryptoadvance/specter-diy)). Blockchain Commons says MURs are "adopted by over a dozen wallets" ([BC animated QRs](https://developer.blockchaincommons.com/animated-qrs/)).
- **UR libraries:** C++ [bc-ur](https://github.com/BlockchainCommons/bc-ur), JS [ngraveio/bc-ur](https://github.com/ngraveio/bc-ur) (MIT), Python [foundation-ur-py](https://github.com/Foundation-Devices/foundation-ur-py), TS generator [bc-mur-ts](https://github.com/BlockchainCommons/bc-mur-ts). bc-mur-ts supports GIF and ProRes export, logo overlay, and "density safety checks".
- **Generic file transfer:** [divan/txqr](https://github.com/divan/txqr) (MIT, 3.2k★, last push 2024-04), [qifi-dev/qrs](https://github.com/qifi-dev/qrs) (MIT, 1.7k★, active; exports GIF and **decodes the exported sequence before download** to verify it), [deedy/qr-data-transfer](https://github.com/deedy/qr-data-transfer) (no license), [xloem/qrstream](https://github.com/xloem/qrstream) (Android, no license), [n8fr8/qranime](https://github.com/n8fr8/qranime) (GPL-3.0, last push 2014).

---

## 4. OSS libraries (GitHub API, 2026-10-01)

| Lib | Role | License | ★ | Last push | Notes |
|---|---|---|---|---|---|
| [nayuki/QR-Code-generator](https://github.com/nayuki/QR-Code-generator) | Encoder (Java/TS/Py/Rust/C++/C) | MIT (per README; GitHub shows no SPDX) | 6.8k | 2026-08 | Clean reference encoder, exposes ECC tables |
| [soldair/node-qrcode](https://github.com/soldair/node-qrcode) | Encoder (JS) | MIT | 8.2k | 2024-08 | Popular, quiet lately |
| [kazuhikoarase/qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) | Encoder (multi-lang) | MIT | 2.4k | 2026-02 | Encoder that qr-code-styling uses (unverified) |
| [kozakdenys/qr-code-styling](https://github.com/kozakdenys/qr-code-styling) | Styled SVG/Canvas | MIT | 3.0k | 2026-02 | Dot and corner styles, logo. No animation |
| [bitjson/qr-code](https://github.com/bitjson/qr-code) | Animated SVG web component | MIT | 1.4k | 2023-02 | Intro/outro animations |
| [AnimQR](https://github.com/AnimQR/AnimQR.github.io) | Animated styled generator | MIT | 0 | 2026-09 | **Closest existing match.** Next.js app, not a library. Lottie/CSS export still on roadmap |
| [zxing/zxing](https://github.com/zxing/zxing) | Decoder (Java) | Apache-2.0 | 34k | 2026-09 | "Maintenance mode only" |
| [zxing-cpp/zxing-cpp](https://github.com/zxing-cpp/zxing-cpp) | Decoder/encoder (C++), WASM wrapper | Apache-2.0 | 2.0k | 2026-09 | Active, the best robustness choice (unverified ranking) |
| [Sec-ant/zxing-wasm](https://github.com/Sec-ant/zxing-wasm) | zxing-cpp packaged as WASM | MIT | 277 | 2026-09 | Good fit for a Node/browser validator |
| [zxing-js/library](https://github.com/zxing-js/library) | Decoder (TS) | Apache-2.0 | 2.9k | 2026-09 | "Maintenance mode only" |
| [cozmo/jsQR](https://github.com/cozmo/jsQR) | Decoder (JS) | Apache-2.0 | 4.0k | 2026-05 | Pure JS |
| [nimiq/qr-scanner](https://github.com/nimiq/qr-scanner) | Web camera scanner | MIT | 2.9k | 2024-03 | Uses BarcodeDetector, else a worker. ~16 kB gz |
| [mchehab/zbar](https://github.com/mchehab/zbar) | Decoder (C) | LGPL-2.1 | 1.4k | 2026-10 | Linux/CLI. LGPL, so link dynamically |
| [kennytm/qrcode-rust](https://github.com/kennytm/qrcode-rust) | Rust encoder | Apache-2.0 (dual MIT unverified) | 562 | 2025-08 | |
| [erwanvivien/fast_qr](https://github.com/erwanvivien/fast_qr) | Rust encoder, WASM + SVG | MIT | 294 | 2026-09 | "~6-7× faster than `qrcode`" |
| [WanzenBug/rqrr](https://github.com/WanzenBug/rqrr) | Rust decoder | Apache-2.0 | 84 | 2026-09 | Exposes `ecc_level` meta |
| [antfu/qrcode-toolkit](https://github.com/antfu/qrcode-toolkit) | AI-QR compare/repair | MIT | 1.3k | 2024-07 | |
| [rsc/qr](https://github.com/rsc/qr) | Go encoder + QArt | BSD-3 | 304 | 2022-10 | |
| [airbnb/lottie-web](https://github.com/airbnb/lottie-web) | Lottie player | MIT | 32k | 2025-09 | |

---

## 5. Output formats

| Format | Strengths | Weaknesses for QR | Where it works |
|---|---|---|---|
| **SVG + SMIL / CSS** | Vector and tiny. Crisp at any size. SMIL `<animate>` is "Baseline: Widely Available" ([MDN](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Element/animate)) | Email: CSS animation reaches ~32% of clients ([caniemail](https://www.caniemail.com/features/css-animation/)). Gmail rasterizes SVG to PNG ([caniemail](https://www.caniemail.com/features/image-svg/)) | Web and docs. Best default |
| **Lottie JSON** | Vector, plays in apps (lottie-web/iOS/Android) | Needs a player runtime. Not supported in email or social (unverified) | Apps, web |
| **GIF** | Plays everywhere. Fine for 1-bit QR art | 256 colors, 1-bit alpha ([MDN](https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Formats/Image_types)). Outlook 2007–2019 shows no animation, and O365 stops after 3 loops ([caniemail](https://www.caniemail.com/features/image-gif/)). **Design the first frame as the most scannable** | Email, chat, social |
| **APNG / animated WebP** | Full color, real alpha, smaller than GIF ([MDN](https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Formats/Image_types)) | Gmail converts WebP to JPG with no animation, and Outlook desktop doesn't support it ([caniemail](https://www.caniemail.com/features/image-webp/)) | Web, some chat apps |
| **MP4 / WebM** | Best for social video and data streams | Lossy chroma subsampling and compression can smear 1-px module edges (unverified; test it). Use high bitrate and integer px/module | Social, presentations, signage |
| **Canvas / WebGL** | Live, interactive, particles and shaders | Runtime only, so export through the formats above | Web apps, kiosks |
| **Print** | n/a | Animation is meaningless. Export a "hero" static frame | Print |

---

## 6. Gaps a new OSS project could fill

1. **Every frame provably decodes.** Today's tools either animate in and out (bitjson), accept non-scannable phases (AnimQR reveal/particles), or test a sample of frames (AnimQR uses 10 frames with only jsQR). Nobody **budgets EC per RS block per frame against the codeword map**.
2. **A scan-safety validator as a reusable library and CI tool**, not tied to one app: a multi-decoder matrix (zxing-cpp, jsQR, rqrr, zbar) × degradations (downscale to 2 px/module, blur, perspective, JPEG/H.264, **blends of adjacent frames**, low-contrast display gamma). qifi/qrs verifies exported data sequences, but nothing like this exists for styled visual codes.
3. **Library-first with multi-format export.** AnimQR is a web app, and Lottie/CSS export are still unchecked on its roadmap. There's room for an npm/WASM core with exporters for SVG+CSS, SMIL, Lottie, GIF, APNG/WebP, and MP4.
4. **Mask-aware and QArt-aware art direction.** Choose among the 8 masks (and QArt-style free bits) to put dark/light runs where the animation wants them ([QArt](https://research.swtch.com/qart), [antfu](https://antfu.me/posts/ai-qrcode-refine)).
5. **Design presets with a guaranteed contract**, e.g. "breathing", "liquid", "neon hue-cycle", "scan sweep", each tagged with its EC cost.
6. **Bridging A and B:** make data-stream codes (BC-UR, LT) look branded while each frame still decodes. bc-mur-ts has logo and density checks but no animation styling.

---

## 7. Recommended MVP

**Scope:** a single-payload *visual* animated QR library plus CLI. Leave data streaming to v2, with BC-UR compatibility for that through [ngraveio/bc-ur](https://github.com/ngraveio/bc-ur).

**Stack:**
- TypeScript core. Port or wrap [nayuki qrcodegen](https://github.com/nayuki/QR-Code-generator) (MIT), which gives the module matrix, mask, version, and ECC tables. Add your own **module→(block, codeword) map** by following the placement and interleaving rules ([Thonky](https://www.thonky.com/qr-code-tutorial/structure-final-message)).
- Renderer: a declarative scene graph that outputs SVG first (SMIL + CSS), with Canvas for raster export.
- Exporters: GIF via gifenc (also used by [bc-mur-ts](https://github.com/BlockchainCommons/bc-mur-ts)), APNG/WebP, and MP4 via ffmpeg/WebCodecs. Lottie export in v1.1.
- Validator: Node + [zxing-wasm](https://github.com/Sec-ant/zxing-wasm) + [jsQR](https://github.com/cozmo/jsQR), optionally [rqrr](https://github.com/WanzenBug/rqrr) (WASM) and the zbar CLI.

**The key trick: a per-frame "center-luminance invariant" plus a per-block EC budget.**
1. **Freeze the skeleton.** Quiet zone, finders and separators, alignment, timing, dark module, and format/version info render the same on every frame at full contrast. Style them, but don't animate them.
2. **Keep each module's center luminance fixed.** Animation can change a module's periphery, shape, scale (to ≥ ~60–75% of the module, per [AnimQR's](https://github.com/AnimQR/AnimQR.github.io) empirical 75%), rotation, and **hue at constant relative luminance** (jsQR's Rec.709 weights). A data module's center sample must stay on the correct side of the threshold with margin, e.g. ΔL ≥ 40% between dark and light (the threshold is my recommendation, unverified).
3. **Spend EC deliberately.** Any effect that breaks step 2 (particles, logo, morph, sweep) marks modules as "at risk". Map them to codewords and require **at-risk codewords per block ≤ 50% of ⌊e/2⌋** on every frame *and* on every 50/50 blend of consecutive frames. That leaves half the EC for real-world blur and glare. The 50% figure is a design choice, unverified.
4. **Start on a scannable frame.** Frame 0 is the most conservative state, because GIF in Outlook and print only show it.

**How to verify scannability automatically:**
- For every frame *and* every blend of adjacent frames: rasterize at 2, 3, and 4 px per module. Apply a degradation matrix: Gaussian blur σ 0.5–1 module, ±15° perspective, JPEG q=50 / H.264 crf 28, and gamma/contrast drop to 70%. Decode with zxing-cpp and jsQR (plus rqrr/zbar in CI). Assert that the payload matches and that the **decoded ECC level and mask match the encoder's**.
- Report a scan-safety score per preset: the worst-case per-block EC use across frames, and the decoder × degradation pass rate. Fail CI below the threshold.
- Run manual device QA on iOS Camera, Google Lens, and an ML Kit sample app before tagging a release. Their behavior on animated codes is unverified (§2.4).
