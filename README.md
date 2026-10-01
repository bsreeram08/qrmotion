# qrmotion

`@bsreeram08/qrmotion` on npm. The command is `qrmotion`.

Animated QR codes where every frame still scans. Boxes slide, jiggle, flip, ripple, spin and change color, and a built-in verifier checks every frame before you ship it.

- **Zero runtime dependencies.** Nothing to audit but this package. The QR encoder is [Project Nayuki's](https://www.nayuki.io/page/qr-code-generator-library) (MIT), vendored.
- **Outputs:** animated SVG, canvas frames, raw RGBA, and terminal text.
- **AI-ready:** a JSON-Schema tool definition for any LLM SDK, and a built-in MCP server.
- Works in Bun, Node 18+, Deno and browsers.

## Install

```sh
bun add @bsreeram08/qrmotion      # or: npm i @bsreeram08/qrmotion
```

## Use

```ts
import { animatedQR } from '@bsreeram08/qrmotion';

const svg = animatedQR('https://example.com', { effect: 'slide' });
// drop it in a page, save it as .svg, or return it from an API
```

More control:

```ts
import { encode, toSVG, drawFrame, toTerminal, verify } from '@bsreeram08/qrmotion';

const qr = encode('https://example.com', 'Q');        // L | M | Q | H
const opts = { effect: 'flip', ink: '#0b3a40', paper: '#f5f2ea', duration: 2.4 } as const;

verify(qr, opts);              // { ok: true, frames: 48, worst: 0, worstAt: 0 }
toSVG(qr, opts);               // animated SVG string (CSS keyframes, honors prefers-reduced-motion)
drawFrame(ctx, qr, opts, t);   // draw time t (seconds) onto a 2D canvas
toTerminal(qr, { ...opts, color: true }, t);  // one frame as ANSI text
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

### Why it scans

Scanners read the middle of each module. qrmotion never animates the finder eyes, timing lines, alignment squares, format/version info or quiet zone. Every other box keeps the middle of its own module covered (center ±0.2 modules) and stays out of its neighbors' middles. In practice that limits sideways movement to about a quarter of a module.

`verify()` renders frames and checks a 3×3 grid of points inside every module. The test suite also decodes every frame of every effect with [jsQR](https://github.com/cozmo/jsQR), a separate decoder. Bring your own effect by passing an object with `size`, `radius`, `phase()` and `pose()`, then run `verify()` on it.

Built-in effects have only been machine-tested so far. Test with iPhone Camera and Google Lens before relying on them in print.

## CLI

```sh
npx @bsreeram08/qrmotion https://example.com              # animates in your terminal (Ctrl+C to stop)
npx @bsreeram08/qrmotion https://example.com -e jiggle --svg code.svg
npx @bsreeram08/qrmotion https://example.com --json       # { version, size, ecc, effect, verified, svg }
npx @bsreeram08/qrmotion https://example.com --once       # one static frame, also the default when piped
```

Terminal output uses half-block characters with 24-bit color (`--mono` for plain text, `NO_COLOR` is respected). Each module is 2 columns wide, so a short URL needs about 60–70 columns.

## AI agents and LLM tools

`tool` is a plain JSON-Schema tool definition and `runTool()` validates the model's input and runs it.

```ts
import { tool, runTool } from '@bsreeram08/qrmotion';

// Anthropic
const tools = [{ name: tool.name, description: tool.description, input_schema: tool.inputSchema }];
// when the model calls it:
const { output, verified } = runTool(toolUse.input);   // output is SVG markup

// OpenAI: { type: 'function', function: { name: tool.name, description: tool.description, parameters: tool.inputSchema } }
// Vercel AI SDK: tool({ description: tool.description, inputSchema: jsonSchema(tool.inputSchema), execute: runTool })
```

### MCP server

```sh
claude mcp add @bsreeram08/qrmotion -- npx -y @bsreeram08/qrmotion mcp
```

opencode (`opencode.json`):

```json
{ "mcp": { "qrmotion": { "type": "local", "command": ["npx", "-y", "@bsreeram08/qrmotion", "mcp"] } } }
```

The server exposes one tool, `animated_qr`. It returns SVG, or a text preview with `format: "terminal"`. Agent UIs such as Claude Code and opencode show tool output as static text, so the animation plays when you run `qrmotion` in a real terminal or open the SVG.

## License

MIT
