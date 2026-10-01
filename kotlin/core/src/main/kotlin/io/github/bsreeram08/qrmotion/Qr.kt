package io.github.bsreeram08.qrmotion

import kotlin.math.max
import kotlin.math.min

/** Error correction level. */
public enum class Ecc(internal val level: EccLevel) {
    L(EccLevel.LOW),
    M(EccLevel.MEDIUM),
    Q(EccLevel.QUARTILE),
    H(EccLevel.HIGH),
}

/** An encoded QR symbol plus a map of which modules must never move. */
public class Qr internal constructor(
    public val text: String,
    /** Modules per side (21 for version 1, up to 177). */
    public val size: Int,
    public val version: Int,
    /** Actual level used. May be higher than requested when it fits for free. */
    public val ecc: Ecc,
    private val dark: BooleanArray,
    private val fixed: BooleanArray,
) {
    /** True for a dark module at row [r], column [c]. */
    public fun isDark(r: Int, c: Int): Boolean = dark[r * size + c]

    /** True for function patterns (finder, separator, timing, alignment, format/version info). Never animated. */
    public fun isFixed(r: Int, c: Int): Boolean = fixed[r * size + c]

    /** True for modules inside one of the three 7x7 finder squares. */
    public fun isFinder(r: Int, c: Int): Boolean =
        (r < 7 && c < 7) || (r < 7 && c >= size - 7) || (r >= size - 7 && c < 7)
}

/** Encode [text] as UTF-8. Throws [IllegalArgumentException] when it does not fit in version 40 at [ecc]. */
public fun encode(text: String, ecc: Ecc = Ecc.Q): Qr {
    val code = QrCode.encodeText(text, ecc.level)
    val n = code.size
    val v = code.version
    val dark = BooleanArray(n * n) { code.getModule(it % n, it / n) }
    val fixed = BooleanArray(n * n)

    fun mark(r0: Int, c0: Int, h: Int, w: Int) {
        for (r in max(0, r0) until min(n, r0 + h)) for (c in max(0, c0) until min(n, c0 + w)) fixed[r * n + c] = true
    }
    // finders + separators + format info; the always-dark module sits inside the bottom-left block
    mark(0, 0, 9, 9)
    mark(0, n - 8, 9, 8)
    mark(n - 8, 0, 8, 9)
    mark(6, 0, 1, n) // timing
    mark(0, 6, n, 1)
    val align = QrCode.alignmentPatternPositions(v)
    for (a in align) for (b in align) {
        if ((a < 9 && b < 9) || (a < 9 && b > n - 10) || (a > n - 10 && b < 9)) continue
        mark(a - 2, b - 2, 5, 5)
    }
    if (v >= 7) { // version info
        mark(0, n - 11, 6, 3)
        mark(n - 11, 0, 3, 6)
    }
    val actual = Ecc.entries.first { it.level == code.ecl }
    return Qr(text, n, v, actual, dark, fixed)
}
