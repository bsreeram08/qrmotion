import { encode, type Ecc } from './qr.js';
import { EFFECTS, EFFECT_NAMES, type EffectName } from './effects.js';
import { toSVG, toTerminal, verify } from './render.js';

export const VERSION = '0.1.2';

/**
 * Tool definition for LLM function calling. `inputSchema` is plain JSON Schema, so it plugs into
 * MCP as is, the Anthropic API as `input_schema`, OpenAI as `parameters`, and the Vercel AI SDK
 * through `jsonSchema()`.
 */
export const tool = {
  name: 'animated_qr',
  description:
    'Create an animated QR code that stays scannable on every frame. Returns SVG markup (or terminal text). '
    + 'Effects: ' + EFFECT_NAMES.map((n) => `${n} (${EFFECTS[n].description})`).join(' '),
  inputSchema: {
    type: 'object',
    properties: {
      text: { type: 'string', minLength: 1, maxLength: 2953, description: 'Text or URL to encode.' },
      effect: { type: 'string', enum: EFFECT_NAMES, default: 'slide', description: 'Animation style.' },
      ecc: { type: 'string', enum: ['L', 'M', 'Q', 'H'], default: 'Q', description: 'Error correction level. Higher is sturdier but denser.' },
      ink: { type: 'string', pattern: '^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$', default: '#17132a', description: 'Dark color. Must be much darker than paper.' },
      paper: { type: 'string', pattern: '^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$', default: '#f5f2ea', description: 'Light background color.' },
      duration: { type: 'number', minimum: 0.2, maximum: 60, default: 2.4, description: 'Seconds per animation loop.' },
      format: { type: 'string', enum: ['svg', 'terminal'], default: 'svg', description: 'svg for web pages and files, terminal for a plain-text preview.' },
    },
    required: ['text'],
    additionalProperties: false,
  },
} as const;

export interface ToolInput {
  text: string;
  effect?: EffectName;
  ecc?: Ecc;
  ink?: string;
  paper?: string;
  duration?: number;
  format?: 'svg' | 'terminal';
}

export interface ToolOutput {
  /** SVG markup or terminal text, depending on format. */
  output: string;
  format: 'svg' | 'terminal';
  version: number;
  size: number;
  ecc: Ecc;
  effect: EffectName;
  /** True when every sampled frame decodes to the exact text. */
  verified: boolean;
}

/** Run the tool. Validates input (it may come from a model) and throws a TypeError/RangeError with a fixable message. */
export function runTool(input: unknown): ToolOutput {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new TypeError('input must be an object with at least { text }');
  const allowed = Object.keys(tool.inputSchema.properties);
  for (const k of Object.keys(input)) if (!allowed.includes(k)) throw new TypeError(`unknown field "${k}". Allowed: ${allowed.join(', ')}`);
  const i = input as ToolInput;
  if (typeof i.text !== 'string' || !i.text) throw new TypeError('text must be a non-empty string');
  if (i.duration !== undefined && !(typeof i.duration === 'number' && i.duration >= 0.2 && i.duration <= 60))
    throw new RangeError('duration must be a number between 0.2 and 60');
  const format = i.format ?? 'svg';
  if (format !== 'svg' && format !== 'terminal') throw new TypeError('format must be "svg" or "terminal"');
  const effect = i.effect ?? 'slide';
  const qr = encode(i.text, i.ecc ?? 'Q');
  const opts = { effect, ink: i.ink, paper: i.paper, duration: i.duration };
  const output = format === 'svg' ? toSVG(qr, opts) : toTerminal(qr, opts);
  return { output, format, version: qr.version, size: qr.size, ecc: qr.ecc, effect, verified: verify(qr, opts, 24).ok };
}
