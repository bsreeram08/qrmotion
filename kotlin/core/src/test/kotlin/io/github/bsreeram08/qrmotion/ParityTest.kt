package io.github.bsreeram08.qrmotion

import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

/** Output must match fixtures/parity.json, generated from the TypeScript reference by scripts/fixtures.ts. */
class ParityTest {
    private val fixture: Map<String, Any?> by lazy {
        val file = generateSequence(File(System.getProperty("user.dir")).absoluteFile) { it.parentFile }
            .map { File(it, "fixtures/parity.json") }
            .firstOrNull { it.isFile }
            ?: fail("fixtures/parity.json not found above ${System.getProperty("user.dir")}")
        @Suppress("UNCHECKED_CAST")
        Json(file.readText()).parse() as Map<String, Any?>
    }

    private fun list(key: String): List<Map<String, Any?>> {
        @Suppress("UNCHECKED_CAST")
        return fixture[key] as List<Map<String, Any?>>
    }

    private fun Qr.bits(at: Qr.(Int, Int) -> Boolean): String = buildString {
        for (r in 0 until size) for (c in 0 until size) append(if (at(r, c)) '1' else '0')
    }

    @Test
    fun matrices() {
        val matrices = list("matrices")
        assertEquals(6, matrices.size)
        for (m in matrices) {
            val text = m["text"] as String
            val qr = encode(text, Ecc.valueOf(m["eccRequested"] as String))
            assertEquals(m["ecc"], qr.ecc.name, "ecc for $text")
            assertEquals((m["version"] as Double).toInt(), qr.version, "version for $text")
            assertEquals((m["size"] as Double).toInt(), qr.size, "size for $text")
            assertEquals(m["dark"], qr.bits(Qr::isDark), "dark for $text")
            assertEquals(m["fixed"], qr.bits(Qr::isFixed), "fixed for $text")
        }
    }

    @Test
    fun frames() {
        val frames = list("frames")
        assertEquals(21, frames.size)
        for (f in frames) {
            val qr = encode(f["text"] as String, Ecc.valueOf(f["ecc"] as String))
            val effect = Effects.named(f["effect"] as String)
            val t = f["t"] as Double
            val options = RenderOptions(effect = effect, seed = (f["seed"] as Double).toInt(), duration = f["duration"] as Double)
            val actual = frameShapes(qr, options, t)

            @Suppress("UNCHECKED_CAST")
            val expected = f["shapes"] as List<List<Double>>
            assertEquals(expected.size, actual.size, "shape count for ${effect.name} @ $t")
            actual.zip(expected).forEachIndexed { i, (s, e) ->
                val got = listOf(s.cx, s.cy, s.w, s.h, s.rot, s.r, s.fill.r, s.fill.g, s.fill.b)
                for (k in 0 until 9) {
                    val tolerance = if (k < 6) 1e-4 else 0.5
                    if (abs(got[k] - e[k]) > tolerance) fail("${effect.name} @ $t shape $i field $k: expected ${e[k]}, got ${got[k]}")
                }
            }
        }
    }

    @Test
    fun verifyResults() {
        val qr = encode("https://example.com", Ecc.Q)
        for (v in list("verify")) {
            val effect = Effects.named(v["effect"] as String)
            val frames = (v["frames"] as Double).toInt()
            val result = verify(qr, RenderOptions(effect = effect), frames)
            assertEquals(v["ok"], result.ok, effect.name)
            assertEquals((v["worst"] as Double).toInt(), result.worst, effect.name)
            assertEquals(frames, result.frames, effect.name)
        }
    }

    @Test
    fun builtInsScanOnLargeAndHighEcc() {
        for (ecc in listOf(Ecc.L, Ecc.H)) {
            val qr = encode("https://example.com/animated-qr?ref=qrmotion", ecc)
            for (effect in Effects.all) assertTrue(verify(qr, RenderOptions(effect = effect)).ok, "${effect.name} @ $ecc")
        }
    }

    @Test
    fun verifyCatchesUnsafeEffect() {
        val drift = object : Effect {
            override val name = "drift"
            override val size = 0.9
            override val radius = 0.5
            override fun phase(r: Int, c: Int, d: Double, rand: Double) = rand
            override fun pose(u: Double) = Pose(dx = 0.6 * cos(2 * PI * u), dy = 0.6 * sin(2 * PI * u))
        }
        val v = verify(encode("https://example.com/animated-qr?ref=qrmotion"), RenderOptions(effect = drift), 12)
        assertFalse(v.ok)
        assertTrue(v.worst > 0)
    }

    @Test
    fun negativeHueWraps() {
        fun hued(hue: Double) = object : Effect {
            override val size = 0.9
            override val radius = 0.1
            override fun phase(r: Int, c: Int, d: Double, rand: Double) = 0.0
            override fun pose(u: Double) = Pose(hue = hue)
        }
        val qr = encode("hi")
        val fills = { hue: Double -> frameShapes(qr, RenderOptions(effect = hued(hue))).map { it.fill } }
        fills(-30.0).zip(fills(330.0)).forEach { (a, b) ->
            assertTrue(abs(a.r - b.r) < 1e-9 && abs(a.g - b.g) < 1e-9 && abs(a.b - b.b) < 1e-9, "$a vs $b")
        }
    }

    @Test
    fun rejectsBadInput() {
        val low = assertFailsWith<IllegalArgumentException> { RenderOptions(ink = Rgb.hex("#999"), paper = Rgb.hex("#aaa")) }
        assertTrue("darker" in low.message.orEmpty())
        val color = assertFailsWith<IllegalArgumentException> { Rgb.hex("red") }
        assertTrue("#rgb" in color.message.orEmpty())
        assertFailsWith<IllegalArgumentException> { encode("x".repeat(5000)) }
        val unknown = assertFailsWith<IllegalArgumentException> { Effects.named("nope") }
        assertTrue("unknown effect" in unknown.message.orEmpty())
        assertFailsWith<IllegalArgumentException> { RenderOptions(duration = 0.0) }
        assertFailsWith<IllegalArgumentException> { RenderOptions(quiet = -1) }
    }
}

/** Minimal JSON reader for the fixture: objects, arrays, strings, numbers (as Double), booleans, null. */
private class Json(private val s: String) {
    private var i = 0

    fun parse(): Any? = value().also { ws(); check(i == s.length) { "trailing data at $i" } }

    private fun ws() {
        while (i < s.length && s[i].isWhitespace()) i++
    }

    private fun value(): Any? {
        ws()
        return when (val ch = s[i]) {
            '{' -> obj()
            '[' -> arr()
            '"' -> str()
            't' -> literal("true", true)
            'f' -> literal("false", false)
            'n' -> literal("null", null)
            else -> if (ch == '-' || ch.isDigit()) num() else error("unexpected '$ch' at $i")
        }
    }

    private fun literal(word: String, v: Any?): Any? {
        check(s.startsWith(word, i)) { "bad literal at $i" }
        i += word.length
        return v
    }

    private fun obj(): Map<String, Any?> {
        val out = LinkedHashMap<String, Any?>()
        i++
        ws()
        if (s[i] == '}') return out.also { i++ }
        while (true) {
            ws()
            val k = str()
            ws()
            check(s[i++] == ':')
            out[k] = value()
            ws()
            if (s[i++] == '}') return out
        }
    }

    private fun arr(): List<Any?> {
        val out = ArrayList<Any?>()
        i++
        ws()
        if (s[i] == ']') return out.also { i++ }
        while (true) {
            out += value()
            ws()
            if (s[i++] == ']') return out
        }
    }

    private fun str(): String {
        check(s[i++] == '"')
        val sb = StringBuilder()
        while (true) {
            when (val ch = s[i++]) {
                '"' -> return sb.toString()
                '\\' -> when (val e = s[i++]) {
                    'n' -> sb.append('\n')
                    't' -> sb.append('\t')
                    'r' -> sb.append('\r')
                    'b' -> sb.append('\b')
                    'f' -> sb.append('\u000C')
                    'u' -> sb.append(s.substring(i, i + 4).toInt(16).toChar()).also { i += 4 }
                    else -> sb.append(e)
                }
                else -> sb.append(ch)
            }
        }
    }

    private fun num(): Double {
        val start = i
        while (i < s.length && (s[i].isDigit() || s[i] in "+-.eE")) i++
        return s.substring(start, i).toDouble()
    }
}
