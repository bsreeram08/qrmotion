package io.github.bsreeram08.qrmotion

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/**
 * How one data module looks at a cycle position. Offsets are in modules, rotation in degrees.
 * Safety rule every built-in effect follows: the box always covers the middle of its own module
 * (center ±0.2 modules) and never reaches the middle of a neighbor's. [verify] checks it.
 * In practice that caps sideways movement at about a quarter of a module.
 */
public data class Pose(
    val dx: Double = 0.0,
    val dy: Double = 0.0,
    val sx: Double = 1.0,
    val sy: Double = 1.0,
    val rot: Double = 0.0,
    /** Hue rotation in degrees applied to the ink. Lightness is kept. */
    val hue: Double = 0.0,
    /** Lightness change applied to the ink, e.g. -0.05. */
    val shade: Double = 0.0,
)

/** An animation. Implement it for a custom effect, then run [verify] on it. */
public interface Effect {
    public val name: String get() = "custom"

    /** Box side as a fraction of a module. */
    public val size: Double

    /** Corner radius as a fraction of the box side (0.5 = circle). */
    public val radius: Double

    /** Cycle offset for a module. [d] = distance from the symbol center in modules, [rand] = stable random 0..1. */
    public fun phase(r: Int, c: Int, d: Double, rand: Double): Double

    /** Pose at cycle position [u] in [0, 1). Must be periodic. */
    public fun pose(u: Double): Pose
}

private const val TAU = PI * 2
private val still = Pose()

private class BuiltIn(
    override val name: String,
    override val size: Double,
    override val radius: Double,
    private val phaseFn: (r: Int, c: Int, d: Double, rand: Double) -> Double,
    private val poseFn: (u: Double) -> Pose,
) : Effect {
    override fun phase(r: Int, c: Int, d: Double, rand: Double): Double = phaseFn(r, c, d, rand)
    override fun pose(u: Double): Pose = poseFn(u)
    override fun toString(): String = "Effect($name)"
}

/** Built-in effects. Each one passes [verify] with zero wrong modules. */
public object Effects {
    /** Rows of boxes glide left and right in opposite directions, in a wave. */
    public val Slide: Effect = BuiltIn("slide", 0.92, 0.12, { r, _, _, _ -> r * 0.07 + (r % 2) * 0.5 }) { u ->
        still.copy(dx = 0.25 * sin(TAU * u))
    }

    /** Each box shakes and tilts on its own rhythm. */
    public val Jiggle: Effect = BuiltIn("jiggle", 0.9, 0.1, { _, _, _, rand -> rand }) { u ->
        still.copy(dx = 0.18 * sin(TAU * u), dy = 0.18 * sin(2 * TAU * u + 1), rot = 8 * sin(3 * TAU * u))
    }

    /** Boxes turn like tiles in a diagonal wave, stopping before they go edge-on. */
    public val Flip: Effect = BuiltIn("flip", 0.92, 0.1, { r, c, _, _ -> -(r + c) * 0.045 }) { u ->
        val k = cos(TAU * u)
        still.copy(sx = 0.5 + 0.5 * abs(k), shade = if (k < 0) 0.06 else 0.0)
    }

    /** Round dots swell and shrink in a wave from the center. */
    public val Ripple: Effect = BuiltIn("ripple", 1.0, 0.5, { _, _, d, _ -> -d * 0.1 }) { u ->
        val s = 0.7 + 0.3 * (0.5 + 0.5 * sin(TAU * u))
        still.copy(sx = s, sy = s)
    }

    /** Hue flows across the code while lightness stays fixed. */
    public val Spectrum: Effect = BuiltIn("spectrum", 0.9, 0.32, { r, c, _, _ -> (r + c) * 0.017 }) { u ->
        still.copy(hue = 360 * u)
    }

    /** Boxes spin and pulse in a wave from the center. */
    public val Morph: Effect = BuiltIn("morph", 0.82, 0.25, { _, _, d, _ -> d * 0.04 }) { u ->
        val s = 0.9 + 0.1 * sin(TAU * u)
        still.copy(sx = s, sy = s, rot = 360 * u)
    }

    /** No animation. A plain styled QR code. */
    public val None: Effect = BuiltIn("none", 1.0, 0.0, { _, _, _, _ -> 0.0 }) { still }

    public val all: List<Effect> = listOf(Slide, Jiggle, Flip, Ripple, Spectrum, Morph, None)

    /** Look up a built-in effect by its name ("slide", "jiggle", ...). */
    public fun named(name: String): Effect =
        all.firstOrNull { it.name == name }
            ?: throw IllegalArgumentException("unknown effect \"$name\". Use one of: ${all.joinToString { it.name }}")
}
