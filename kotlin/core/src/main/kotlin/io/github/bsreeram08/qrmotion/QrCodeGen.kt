/*
 * QR Code generator library (Kotlin port)
 *
 * Copyright (c) Project Nayuki. (MIT License)
 * https://www.nayuki.io/page/qr-code-generator-library
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 * - The above copyright notice and this permission notice shall be included in
 *   all copies or substantial portions of the Software.
 * - The Software is provided "as is", without warranty of any kind, express or
 *   implied, including but not limited to the warranties of merchantability,
 *   fitness for a particular purpose and noninfringement. In no event shall the
 *   authors or copyright holders be liable for any claim, damages or other
 *   liability, whether in an action of contract, tort or otherwise, arising from,
 *   out of or in connection with the Software or the use or other dealings in the
 *   Software.
 */

// qrmotion: ported from https://github.com/nayuki/QR-Code-generator (java/ and typescript-javascript/),
// trimmed to what encodeText() needs: numeric, alphanumeric and byte segments, automatic mask, ECC boost.
package io.github.bsreeram08.qrmotion

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Nayuki's level order (ordinal) with the format-info bits each level writes. */
internal enum class EccLevel(val formatBits: Int) { LOW(1), MEDIUM(0), QUARTILE(3), HIGH(2) }

private enum class Mode(val modeBits: Int, private val charCountBits: IntArray) {
    NUMERIC(0x1, intArrayOf(10, 12, 14)),
    ALPHANUMERIC(0x2, intArrayOf(9, 11, 13)),
    BYTE(0x4, intArrayOf(8, 16, 16));

    fun numCharCountBits(ver: Int): Int = charCountBits[(ver + 7) / 17]
}

private class BitBuffer {
    var bits = BooleanArray(64)
        private set
    var size = 0
        private set

    fun append(value: Int, len: Int) {
        require(len in 0..31 && value ushr len == 0) { "Value out of range" }
        for (i in len - 1 downTo 0) push((value ushr i) and 1 != 0)
    }

    fun appendAll(other: BitBuffer) {
        for (i in 0 until other.size) push(other.bits[i])
    }

    private fun push(bit: Boolean) {
        if (size == bits.size) bits = bits.copyOf(size * 2)
        bits[size++] = bit
    }
}

private class Segment(val mode: Mode, val numChars: Int, val data: BitBuffer)

private const val ALPHANUMERIC_CHARSET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"

private fun makeSegments(text: String): List<Segment> = when {
    text.isEmpty() -> emptyList()
    text.all { it in '0'..'9' } -> listOf(makeNumeric(text))
    text.all { it in ALPHANUMERIC_CHARSET } -> listOf(makeAlphanumeric(text))
    else -> listOf(makeBytes(text.encodeToByteArray()))
}

private fun makeNumeric(digits: String): Segment {
    val bb = BitBuffer()
    var i = 0
    while (i < digits.length) {
        val n = min(digits.length - i, 3)
        bb.append(digits.substring(i, i + n).toInt(), n * 3 + 1)
        i += n
    }
    return Segment(Mode.NUMERIC, digits.length, bb)
}

private fun makeAlphanumeric(text: String): Segment {
    val bb = BitBuffer()
    var i = 0
    while (i + 2 <= text.length) {
        bb.append(ALPHANUMERIC_CHARSET.indexOf(text[i]) * 45 + ALPHANUMERIC_CHARSET.indexOf(text[i + 1]), 11)
        i += 2
    }
    if (i < text.length) bb.append(ALPHANUMERIC_CHARSET.indexOf(text[i]), 6)
    return Segment(Mode.ALPHANUMERIC, text.length, bb)
}

private fun makeBytes(data: ByteArray): Segment {
    val bb = BitBuffer()
    for (b in data) bb.append(b.toInt() and 0xFF, 8)
    return Segment(Mode.BYTE, data.size, bb)
}

/** Bits needed for [segs] at [version], or null if a segment's length does not fit its count field. */
private fun totalBits(segs: List<Segment>, version: Int): Int? {
    var result = 0L
    for (seg in segs) {
        val ccBits = seg.mode.numCharCountBits(version)
        if (seg.numChars >= (1 shl ccBits)) return null
        result += 4L + ccBits + seg.data.size
        if (result > Int.MAX_VALUE) return null
    }
    return result.toInt()
}

/** An immutable QR Code symbol. Construct with [QrCode.encodeText]. */
internal class QrCode private constructor(val version: Int, val ecl: EccLevel, dataCodewords: ByteArray) {
    val size: Int = version * 4 + 17
    private val modules = Array(size) { BooleanArray(size) }
    private var isFunction: Array<BooleanArray>? = Array(size) { BooleanArray(size) }
    val mask: Int

    init {
        drawFunctionPatterns()
        drawCodewords(addEccAndInterleave(dataCodewords))
        var best = 0
        var minPenalty = Int.MAX_VALUE
        for (i in 0 until 8) {
            applyMask(i)
            drawFormatBits(i)
            val penalty = penaltyScore()
            if (penalty < minPenalty) {
                best = i
                minPenalty = penalty
            }
            applyMask(i) // undo via XOR
        }
        mask = best
        applyMask(best)
        drawFormatBits(best)
        isFunction = null
    }

    fun getModule(x: Int, y: Int): Boolean = x in 0 until size && y in 0 until size && modules[y][x]

    private fun functions(): Array<BooleanArray> = checkNotNull(isFunction) { "construction finished" }

    private fun drawFunctionPatterns() {
        for (i in 0 until size) {
            setFunctionModule(6, i, i % 2 == 0)
            setFunctionModule(i, 6, i % 2 == 0)
        }
        drawFinderPattern(3, 3)
        drawFinderPattern(size - 4, 3)
        drawFinderPattern(3, size - 4)
        val pos = alignmentPatternPositions(version)
        val n = pos.size
        for (i in 0 until n) for (j in 0 until n) {
            if (!(i == 0 && j == 0 || i == 0 && j == n - 1 || i == n - 1 && j == 0)) drawAlignmentPattern(pos[i], pos[j])
        }
        drawFormatBits(0)
        drawVersion()
    }

    private fun drawFormatBits(msk: Int) {
        val data = ecl.formatBits shl 3 or msk
        var rem = data
        repeat(10) { rem = (rem shl 1) xor ((rem ushr 9) * 0x537) }
        val bits = (data shl 10 or rem) xor 0x5412
        check(bits ushr 15 == 0)
        for (i in 0..5) setFunctionModule(8, i, bit(bits, i))
        setFunctionModule(8, 7, bit(bits, 6))
        setFunctionModule(8, 8, bit(bits, 7))
        setFunctionModule(7, 8, bit(bits, 8))
        for (i in 9 until 15) setFunctionModule(14 - i, 8, bit(bits, i))
        for (i in 0 until 8) setFunctionModule(size - 1 - i, 8, bit(bits, i))
        for (i in 8 until 15) setFunctionModule(8, size - 15 + i, bit(bits, i))
        setFunctionModule(8, size - 8, true) // always dark
    }

    private fun drawVersion() {
        if (version < 7) return
        var rem = version
        repeat(12) { rem = (rem shl 1) xor ((rem ushr 11) * 0x1F25) }
        val bits = version shl 12 or rem
        check(bits ushr 18 == 0)
        for (i in 0 until 18) {
            val color = bit(bits, i)
            val a = size - 11 + i % 3
            val b = i / 3
            setFunctionModule(a, b, color)
            setFunctionModule(b, a, color)
        }
    }

    private fun drawFinderPattern(x: Int, y: Int) {
        for (dy in -4..4) for (dx in -4..4) {
            val dist = max(abs(dx), abs(dy))
            val xx = x + dx
            val yy = y + dy
            if (xx in 0 until size && yy in 0 until size) setFunctionModule(xx, yy, dist != 2 && dist != 4)
        }
    }

    private fun drawAlignmentPattern(x: Int, y: Int) {
        for (dy in -2..2) for (dx in -2..2) setFunctionModule(x + dx, y + dy, max(abs(dx), abs(dy)) != 1)
    }

    private fun setFunctionModule(x: Int, y: Int, isDark: Boolean) {
        modules[y][x] = isDark
        functions()[y][x] = true
    }

    private fun addEccAndInterleave(data: ByteArray): ByteArray {
        require(data.size == numDataCodewords(version, ecl)) { "Invalid argument" }
        val numBlocks = NUM_ERROR_CORRECTION_BLOCKS[ecl.ordinal][version]
        val blockEccLen = ECC_CODEWORDS_PER_BLOCK[ecl.ordinal][version]
        val rawCodewords = numRawDataModules(version) / 8
        val numShortBlocks = numBlocks - rawCodewords % numBlocks
        val shortBlockLen = rawCodewords / numBlocks

        val rsDiv = reedSolomonComputeDivisor(blockEccLen)
        var k = 0
        val blocks = Array(numBlocks) { i ->
            val datLen = shortBlockLen - blockEccLen + if (i < numShortBlocks) 0 else 1
            val dat = data.copyOfRange(k, k + datLen)
            k += datLen
            val block = dat.copyOf(shortBlockLen + 1)
            reedSolomonComputeRemainder(dat, rsDiv).copyInto(block, block.size - blockEccLen)
            block
        }

        val result = ByteArray(rawCodewords)
        var idx = 0
        for (i in blocks[0].indices) for (j in blocks.indices) {
            if (i != shortBlockLen - blockEccLen || j >= numShortBlocks) result[idx++] = blocks[j][i]
        }
        check(idx == rawCodewords)
        return result
    }

    private fun drawCodewords(data: ByteArray) {
        require(data.size == numRawDataModules(version) / 8) { "Invalid argument" }
        val fn = functions()
        var i = 0
        var right = size - 1
        while (right >= 1) {
            if (right == 6) right = 5
            for (vert in 0 until size) for (j in 0 until 2) {
                val x = right - j
                val upward = (right + 1) and 2 == 0
                val y = if (upward) size - 1 - vert else vert
                if (!fn[y][x] && i < data.size * 8) {
                    modules[y][x] = bit(data[i ushr 3].toInt(), 7 - (i and 7))
                    i++
                }
            }
            right -= 2
        }
        check(i == data.size * 8)
    }

    private fun applyMask(msk: Int) {
        val fn = functions()
        for (y in 0 until size) for (x in 0 until size) {
            val invert = when (msk) {
                0 -> (x + y) % 2 == 0
                1 -> y % 2 == 0
                2 -> x % 3 == 0
                3 -> (x + y) % 3 == 0
                4 -> (x / 3 + y / 2) % 2 == 0
                5 -> x * y % 2 + x * y % 3 == 0
                6 -> (x * y % 2 + x * y % 3) % 2 == 0
                7 -> ((x + y) % 2 + x * y % 3) % 2 == 0
                else -> throw IllegalArgumentException("Mask value out of range")
            }
            if (!fn[y][x] && invert) modules[y][x] = !modules[y][x]
        }
    }

    private fun penaltyScore(): Int {
        var result = 0
        for (y in 0 until size) result += linePenalty { modules[y][it] }
        for (x in 0 until size) result += linePenalty { modules[it][x] }
        for (y in 0 until size - 1) for (x in 0 until size - 1) {
            val color = modules[y][x]
            if (color == modules[y][x + 1] && color == modules[y + 1][x] && color == modules[y + 1][x + 1]) result += PENALTY_N2
        }
        val dark = modules.sumOf { row -> row.count { it } }
        val total = size * size
        // smallest k >= 0 such that (45-5k)% <= dark/total <= (55+5k)%
        val k = (abs(dark * 20 - total * 10) + total - 1) / total - 1
        check(k in 0..9)
        result += k * PENALTY_N4
        check(result in 0..2568888)
        return result
    }

    /** Run-length and finder-like penalties for one row or column. */
    private inline fun linePenalty(at: (Int) -> Boolean): Int {
        var result = 0
        var runColor = false
        var run = 0
        val history = IntArray(7)
        for (i in 0 until size) {
            if (at(i) == runColor) {
                run++
                if (run == 5) result += PENALTY_N1 else if (run > 5) result++
            } else {
                addHistory(run, history)
                if (!runColor) result += countPatterns(history) * PENALTY_N3
                runColor = at(i)
                run = 1
            }
        }
        if (runColor) {
            addHistory(run, history)
            run = 0
        }
        addHistory(run + size, history)
        return result + countPatterns(history) * PENALTY_N3
    }

    private fun countPatterns(h: IntArray): Int {
        val n = h[1]
        check(n <= size * 3)
        val core = n > 0 && h[2] == n && h[3] == n * 3 && h[4] == n && h[5] == n
        return (if (core && h[0] >= n * 4 && h[6] >= n) 1 else 0) + (if (core && h[6] >= n * 4 && h[0] >= n) 1 else 0)
    }

    private fun addHistory(runLength: Int, h: IntArray) {
        val len = if (h[0] == 0) runLength + size else runLength
        h.copyInto(h, 1, 0, h.size - 1)
        h[0] = len
    }

    companion object {
        private const val PENALTY_N1 = 3
        private const val PENALTY_N2 = 3
        private const val PENALTY_N3 = 40
        private const val PENALTY_N4 = 10

        /** Smallest version that fits, with the ECC level boosted while it fits for free. */
        fun encodeText(text: String, ecl: EccLevel): QrCode {
            val segs = makeSegments(text)
            var version = 1
            var dataUsedBits: Int
            while (true) {
                val used = totalBits(segs, version)
                if (used != null && used <= numDataCodewords(version, ecl) * 8) {
                    dataUsedBits = used
                    break
                }
                if (version >= 40) throw IllegalArgumentException("Data too long")
                version++
            }
            var level = ecl
            for (newEcl in listOf(EccLevel.MEDIUM, EccLevel.QUARTILE, EccLevel.HIGH)) {
                if (dataUsedBits <= numDataCodewords(version, newEcl) * 8) level = newEcl
            }

            val bb = BitBuffer()
            for (seg in segs) {
                bb.append(seg.mode.modeBits, 4)
                bb.append(seg.numChars, seg.mode.numCharCountBits(version))
                bb.appendAll(seg.data)
            }
            check(bb.size == dataUsedBits)
            val capacity = numDataCodewords(version, level) * 8
            bb.append(0, min(4, capacity - bb.size))
            bb.append(0, (8 - bb.size % 8) % 8)
            var pad = 0xEC
            while (bb.size < capacity) {
                bb.append(pad, 8)
                pad = pad xor (0xEC xor 0x11)
            }

            val codewords = ByteArray(bb.size / 8)
            for (i in 0 until bb.size) {
                if (bb.bits[i]) codewords[i ushr 3] = (codewords[i ushr 3].toInt() or (1 shl (7 - (i and 7)))).toByte()
            }
            return QrCode(version, level, codewords)
        }

        fun alignmentPatternPositions(version: Int): IntArray {
            if (version == 1) return IntArray(0)
            val numAlign = version / 7 + 2
            val step = (version * 8 + numAlign * 3 + 5) / (numAlign * 4 - 4) * 2
            val result = IntArray(numAlign)
            result[0] = 6
            var pos = version * 4 + 17 - 7
            for (i in numAlign - 1 downTo 1) {
                result[i] = pos
                pos -= step
            }
            return result
        }

        private fun numRawDataModules(ver: Int): Int {
            require(ver in 1..40) { "Version number out of range" }
            var result = (16 * ver + 128) * ver + 64
            if (ver >= 2) {
                val numAlign = ver / 7 + 2
                result -= (25 * numAlign - 10) * numAlign - 55
                if (ver >= 7) result -= 36
            }
            check(result in 208..29648)
            return result
        }

        private fun numDataCodewords(ver: Int, ecl: EccLevel): Int =
            numRawDataModules(ver) / 8 -
                ECC_CODEWORDS_PER_BLOCK[ecl.ordinal][ver] * NUM_ERROR_CORRECTION_BLOCKS[ecl.ordinal][ver]

        private fun reedSolomonComputeDivisor(degree: Int): IntArray {
            require(degree in 1..255) { "Degree out of range" }
            val result = IntArray(degree)
            result[degree - 1] = 1
            var root = 1
            repeat(degree) {
                for (j in result.indices) {
                    result[j] = reedSolomonMultiply(result[j], root)
                    if (j + 1 < result.size) result[j] = result[j] xor result[j + 1]
                }
                root = reedSolomonMultiply(root, 0x02)
            }
            return result
        }

        private fun reedSolomonComputeRemainder(data: ByteArray, divisor: IntArray): ByteArray {
            val result = IntArray(divisor.size)
            for (b in data) {
                val factor = (b.toInt() and 0xFF) xor result[0]
                result.copyInto(result, 0, 1)
                result[result.size - 1] = 0
                for (i in result.indices) result[i] = result[i] xor reedSolomonMultiply(divisor[i], factor)
            }
            return ByteArray(result.size) { result[it].toByte() }
        }

        private fun reedSolomonMultiply(x: Int, y: Int): Int {
            var z = 0
            for (i in 7 downTo 0) {
                z = (z shl 1) xor ((z ushr 7) * 0x11D)
                z = z xor ((y ushr i) and 1) * x
            }
            check(z ushr 8 == 0)
            return z
        }

        private fun bit(x: Int, i: Int): Boolean = (x ushr i) and 1 != 0

        private val ECC_CODEWORDS_PER_BLOCK = arrayOf(
            // Version: (index 0 is padding and set to an illegal value)
            //0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40
            intArrayOf(-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30), // Low
            intArrayOf(-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28), // Medium
            intArrayOf(-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30), // Quartile
            intArrayOf(-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30), // High
        )

        private val NUM_ERROR_CORRECTION_BLOCKS = arrayOf(
            //0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40
            intArrayOf(-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25), // Low
            intArrayOf(-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49), // Medium
            intArrayOf(-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68), // Quartile
            intArrayOf(-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81), // High
        )
    }
}
