/**
 * How one data module looks at cycle position u. Offsets are in modules, rotation in degrees.
 * Safety rule every built-in effect follows: the box always covers the middle of its own module
 * (center ±0.2 modules) and never reaches the middle of a neighbor's. `verify()` checks it.
 * In practice that caps sideways movement at about a quarter of a module.
 */
export interface Pose {
  dx: number;
  dy: number;
  sx: number;
  sy: number;
  rot: number;
  /** Hue rotation in degrees applied to the ink. Lightness is kept. */
  hue?: number;
  /** Lightness change applied to the ink, e.g. -0.05. */
  shade?: number;
}

export interface Effect {
  name: string;
  description: string;
  /** Box side as a fraction of a module. */
  size: number;
  /** Corner radius as a fraction of the box side (0.5 = circle). */
  radius: number;
  /** Cycle offset for a module. d = distance from the symbol center in modules, rand = stable random 0..1. */
  phase(r: number, c: number, d: number, rand: number): number;
  /** Pose at cycle position u in [0, 1). Must be periodic. */
  pose(u: number): Pose;
}

const TAU = Math.PI * 2;
const still: Pose = { dx: 0, dy: 0, sx: 1, sy: 1, rot: 0 };

export const EFFECTS = {
  slide: {
    name: 'slide',
    description: 'Rows of boxes glide left and right in opposite directions, in a wave.',
    size: 0.92, radius: 0.12,
    phase: (r) => r * 0.07 + (r % 2) * 0.5,
    pose: (u) => ({ ...still, dx: 0.25 * Math.sin(TAU * u) }),
  },
  jiggle: {
    name: 'jiggle',
    description: 'Each box shakes and tilts on its own rhythm.',
    size: 0.9, radius: 0.1,
    phase: (_r, _c, _d, rand) => rand,
    pose: (u) => ({ ...still, dx: 0.18 * Math.sin(TAU * u), dy: 0.18 * Math.sin(2 * TAU * u + 1), rot: 8 * Math.sin(3 * TAU * u) }),
  },
  flip: {
    name: 'flip',
    description: 'Boxes turn like tiles in a diagonal wave, stopping before they go edge-on.',
    size: 0.92, radius: 0.1,
    phase: (r, c) => -(r + c) * 0.045,
    pose: (u) => {
      const k = Math.cos(TAU * u);
      return { ...still, sx: 0.5 + 0.5 * Math.abs(k), shade: k < 0 ? 0.06 : 0 };
    },
  },
  ripple: {
    name: 'ripple',
    description: 'Round dots swell and shrink in a wave from the center.',
    size: 1, radius: 0.5,
    phase: (_r, _c, d) => -d * 0.1,
    pose: (u) => {
      const s = 0.7 + 0.3 * (0.5 + 0.5 * Math.sin(TAU * u));
      return { ...still, sx: s, sy: s };
    },
  },
  spectrum: {
    name: 'spectrum',
    description: 'Hue flows across the code while lightness stays fixed.',
    size: 0.9, radius: 0.32,
    phase: (r, c) => (r + c) * 0.017,
    pose: (u) => ({ ...still, hue: 360 * u }),
  },
  morph: {
    name: 'morph',
    description: 'Boxes spin and pulse in a wave from the center.',
    size: 0.82, radius: 0.25,
    phase: (_r, _c, d) => d * 0.04,
    pose: (u) => {
      const s = 0.9 + 0.1 * Math.sin(TAU * u);
      return { ...still, sx: s, sy: s, rot: 360 * u };
    },
  },
  none: {
    name: 'none',
    description: 'No animation. A plain styled QR code.',
    size: 1, radius: 0,
    phase: () => 0,
    pose: () => still,
  },
} satisfies Record<string, Effect>;

export type EffectName = keyof typeof EFFECTS;
export const EFFECT_NAMES = Object.keys(EFFECTS) as EffectName[];

export function resolveEffect(effect: EffectName | Effect | undefined): Effect {
  if (effect === undefined) return EFFECTS.slide;
  if (typeof effect === 'string') {
    const e = (EFFECTS as Record<string, Effect>)[effect];
    if (!e) throw new TypeError(`unknown effect "${effect}". Use one of: ${EFFECT_NAMES.join(', ')}`);
    return e;
  }
  return effect;
}
