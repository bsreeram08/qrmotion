package io.github.bsreeram08.qrmotion

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.round
import kotlin.math.sin

/** An sRGB color with channels in 0..255. Tinted colors may be fractional. */
public data class Rgb(val r: Double, val g: Double, val b: Double) {
    /** Relative luminance (Rec. 709 / sRGB). */
    public val luminance: Double
        get() = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)

    public companion object {
        private val HEX = Regex("^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")

        /** Parse #rgb or #rrggbb. */
        public fun hex(s: String): Rgb {
            val m = HEX.matchEntire(s.trim())
                ?: throw IllegalArgumentException("color must be #rgb or #rrggbb (got $s)")
            val h = m.groupValues[1].let { if (it.length == 3) it.map { ch -> "$ch$ch" }.joinToString("") else it }
            return Rgb(h.substring(0, 2).toInt(16).toDouble(), h.substring(2, 4).toInt(16).toDouble(), h.substring(4, 6).toInt(16).toDouble())
        }

        private fun linear(channel: Double): Double {
            val v = channel / 255
            return if (v <= 0.04045) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
        }
    }
}

public val DefaultInk: Rgb = Rgb.hex("#17132a")
public val DefaultPaper: Rgb = Rgb.hex("#f5f2ea")

/** Rendering options. Validated on construction; throws [IllegalArgumentException] for unscannable or invalid input. */
public data class RenderOptions(
    /** Built-in (see [Effects]) or custom effect. */
    val effect: Effect = Effects.Slide,
    val ink: Rgb = DefaultInk,
    val paper: Rgb = DefaultPaper,
    /** Seconds per animation cycle. */
    val duration: Double = 2.4,
    /** Quiet zone in modules. Default 4 (the spec minimum). */
    val quiet: Int = 4,
    /** Seed for per-module randomness, so output is reproducible. */
    val seed: Int = 1,
) {
    init {
        require(paper.luminance - ink.luminance >= 0.4) {
            "ink must be much darker than paper (luminance gap of at least 0.4) or the code will not scan"
        }
        require(duration > 0) { "duration must be a positive number of seconds" }
        require(quiet >= 0) { "quiet must be a non-negative integer" }
    }
}

/** One filled rounded box, in module units of the full canvas (quiet zone included). */
public data class Shape(
    val cx: Double,
    val cy: Double,
    val w: Double,
    val h: Double,
    /** Degrees. */
    val rot: Double,
    /** Corner radius in modules. */
    val r: Double,
    val fill: Rgb,
)

/** RGBA pixels, row-major, 4 bytes per pixel. */
public class Raster(public val width: Int, public val height: Int, public val data: ByteArray) {
    public fun rgb(x: Int, y: Int): Rgb {
        val k = (y * width + x) * 4
        return Rgb((data[k].toInt() and 0xFF).toDouble(), (data[k + 1].toInt() and 0xFF).toDouble(), (data[k + 2].toInt() and 0xFF).toDouble())
    }
}

public data class VerifyResult(
    val ok: Boolean,
    /** Frames checked. */
    val frames: Int,
    /** Most wrong modules seen in any one frame. */
    val worst: Int,
    /** Time (seconds) of the worst frame. */
    val worstAt: Double,
)

/** A QR code bound to render options. Reuse it across frames: per-module randomness is computed once. */
public class QrAnimation(public val qr: Qr, public val options: RenderOptions = RenderOptions()) {
    /** Canvas side in modules, quiet zone included. */
    public val modules: Int = qr.size + options.quiet * 2

    // Float32 like the reference, so phases match bit for bit
    private val rand = FloatArray(qr.size * qr.size).also { out ->
        var s = options.seed
        for (i in out.indices) { // mulberry32
            s += 0x6d2b79f5
            var t = (s xor (s ushr 15)) * (1 or s)
            t = (t + (t xor (t ushr 7)) * (61 or t)) xor t
            out[i] = (((t xor (t ushr 14)).toLong() and 0xFFFFFFFFL).toDouble() / 4294967296.0).toFloat()
        }
    }

    /** Shapes for the frame at time [t] (seconds), in draw order. Paper background is not included. */
    public fun shapes(t: Double = 0.0): List<Shape> {
        val n = qr.size
        val q = options.quiet
        val e = options.effect
        val mid = (n - 1) / 2.0
        val ink = options.ink
        val out = ArrayList<Shape>()
        for (r in 0 until n) for (c in 0 until n) {
            if (!qr.isDark(r, c) || qr.isFinder(r, c)) continue
            val cx = c + q + 0.5
            val cy = r + q + 0.5
            if (qr.isFixed(r, c)) {
                out += Shape(cx, cy, 1.0, 1.0, 0.0, 0.0, ink)
                continue
            }
            val phase = e.phase(r, c, hypot(r - mid, c - mid), rand[r * n + c].toDouble())
            val p = e.pose(frac(t / options.duration + phase))
            val w = e.size * p.sx
            val h = e.size * p.sy
            out += Shape(cx + p.dx, cy + p.dy, w, h, p.rot, e.radius * min(w, h), tint(ink, p.hue, p.shade))
        }
        for ((r, c) in listOf(0 to 0, 0 to n - 7, n - 7 to 0)) eye(r + q, c + q, out)
        return out
    }

    // concentric 7/5/3 rounded squares keep the 1:1:3:1:1 finder ratio
    private fun eye(r: Int, c: Int, out: MutableList<Shape>) {
        fun at(side: Double, rad: Double, fill: Rgb) = Shape(c + 3.5, r + 3.5, side, side, 0.0, rad, fill)
        out += at(7.0, 1.0, options.ink)
        out += at(5.0, 0.9, options.paper)
        out += at(3.0, 0.7, options.ink)
    }

    /** Rasterize the frame at [t] to RGBA, [scale] pixels per module, no anti-aliasing (point sampled at pixel centers). */
    public fun rasterize(t: Double = 0.0, scale: Int = 8): Raster {
        require(scale >= 1) { "scale must be a positive integer" }
        val w = modules * scale
        val data = ByteArray(w * w * 4)
        val paper = byteArrayOf(clamp8(options.paper.r), clamp8(options.paper.g), clamp8(options.paper.b), -1)
        for (i in 0 until w * w) paper.copyInto(data, i * 4)
        for (s in shapes(t)) fillShape(data, w, s, scale)
        return Raster(w, w, data)
    }

    /**
     * Check that the middle of every module has the right color on every sampled frame. Real decoders
     * don't hit the exact center, so a 3x3 grid of points at 0.3, 0.5 and 0.7 of a module must all be right.
     * Strict: zero wrong modules on every frame.
     */
    public fun verify(frames: Int = 48): VerifyResult {
        val s = 5 // pixel centers 1..3 sit at 0.3, 0.5, 0.7 of a module
        val n = qr.size
        val q = options.quiet
        val threshold = (options.ink.luminance + options.paper.luminance) / 2
        var worst = 0
        var worstAt = 0.0
        for (f in 0 until frames) {
            val t = f.toDouble() / frames * options.duration
            val img = rasterize(t, s)
            var wrong = 0
            for (r in 0 until n) for (c in 0 until n) {
                val want = qr.isDark(r, c)
                val bad = (1..3).any { y ->
                    (1..3).any { x -> (img.rgb((c + q) * s + x, (r + q) * s + y).luminance < threshold) != want }
                }
                if (bad) wrong++
            }
            if (wrong > worst) {
                worst = wrong
                worstAt = t
            }
        }
        return VerifyResult(ok = worst == 0, frames = frames, worst = worst, worstAt = worstAt)
    }
}

/** Shapes for a single frame at time [t] (seconds). */
public fun frameShapes(qr: Qr, options: RenderOptions = RenderOptions(), t: Double = 0.0): List<Shape> =
    QrAnimation(qr, options).shapes(t)

/** Rasterize one frame to RGBA pixels. */
public fun rasterize(qr: Qr, options: RenderOptions = RenderOptions(), t: Double = 0.0, scale: Int = 8): Raster =
    QrAnimation(qr, options).rasterize(t, scale)

/** Check every sampled frame scans. See [QrAnimation.verify]. */
public fun verify(qr: Qr, options: RenderOptions = RenderOptions(), frames: Int = 48): VerifyResult =
    QrAnimation(qr, options).verify(frames)

private fun frac(x: Double): Double = ((x % 1) + 1) % 1

/** Rounded-rect signed distance, sampled at pixel centers. */
private fun fillShape(data: ByteArray, w: Int, s: Shape, scale: Int) {
    val cx = s.cx * scale
    val cy = s.cy * scale
    val hw = s.w * scale / 2
    val hh = s.h * scale / 2
    val rr = minOf(s.r * scale, hw, hh)
    val a = s.rot * PI / 180
    val cos = cos(a)
    val sin = sin(a)
    val reach = hypot(hw, hh)
    val x0 = max(0, floor(cx - reach).toInt())
    val x1 = min(w - 1, ceil(cx + reach).toInt())
    val y0 = max(0, floor(cy - reach).toInt())
    val y1 = min(w - 1, ceil(cy + reach).toInt())
    val r = clamp8(s.fill.r)
    val g = clamp8(s.fill.g)
    val b = clamp8(s.fill.b)
    for (y in y0..y1) for (x in x0..x1) {
        val dx = x + 0.5 - cx
        val dy = y + 0.5 - cy
        val lx = abs(cos * dx + sin * dy)
        val ly = abs(-sin * dx + cos * dy)
        val qx = lx - (hw - rr)
        val qy = ly - (hh - rr)
        val outside = hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - rr
        if (outside > 0) continue
        val k = (y * w + x) * 4
        data[k] = r
        data[k + 1] = g
        data[k + 2] = b
    }
}

/** Same conversion as a JS Uint8ClampedArray store: clamp, round half to even. */
private fun clamp8(v: Double): Byte = round(v.coerceIn(0.0, 255.0)).toInt().toByte()

private fun tint(rgb: Rgb, hue: Double, shade: Double): Rgb {
    if (hue == 0.0 && shade == 0.0) return rgb
    var (h, s, l) = toHsl(rgb)
    if (hue != 0.0) s = max(s, 0.65)
    return fromHsl(((h + hue) % 360 + 360) % 360, s, min(1.0, max(0.0, l + shade)))
}

private fun toHsl(rgb: Rgb): Triple<Double, Double, Double> {
    val r = rgb.r / 255
    val g = rgb.g / 255
    val b = rgb.b / 255
    val mx = maxOf(r, g, b)
    val mn = minOf(r, g, b)
    val l = (mx + mn) / 2
    val d = mx - mn
    if (d == 0.0) return Triple(0.0, 0.0, l)
    val s = d / (1 - abs(2 * l - 1))
    val h = when (mx) {
        r -> ((g - b) / d + 6) % 6
        g -> (b - r) / d + 2
        else -> (r - g) / d + 4
    }
    return Triple(h * 60, s, l)
}

private fun fromHsl(h: Double, s: Double, l: Double): Rgb {
    val c = (1 - abs(2 * l - 1)) * s
    val x = c * (1 - abs((h / 60) % 2 - 1))
    val m = l - c / 2
    val (r, g, b) = when {
        h < 60 -> Triple(c, x, 0.0)
        h < 120 -> Triple(x, c, 0.0)
        h < 180 -> Triple(0.0, c, x)
        h < 240 -> Triple(0.0, x, c)
        h < 300 -> Triple(x, 0.0, c)
        else -> Triple(c, 0.0, x)
    }
    return Rgb((r + m) * 255, (g + m) * 255, (b + m) * 255)
}
