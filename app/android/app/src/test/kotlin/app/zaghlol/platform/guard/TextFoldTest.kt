package app.zaghlol.platform.guard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

class TextFoldTest {
    @Test
    fun foldKeyLinesWithSpacesIsFoldKeyOnRandomInput() {
        val alphabet = "aZ09 \t\n\r\u000B\u000C\u0085\u00A0\u2028\u2029\u202F\u2009\u200B\u200F\uFEFF\u0640\u064E\u0623\u0629\u0661\u06F5\u066B\u0130\u212A\uD83D\uDE00"
        val rnd = Random(38)
        repeat(3000) {
            val s = buildString { repeat(rnd.nextInt(0, 40)) { append(alphabet[rnd.nextInt(alphabet.length)]) } }
            val lines = TextFold.foldKeyLines(s)
            assertEquals(TextFold.foldKey(s), lines.replace('\n', ' '))
            assertFalse(lines.startsWith("\n") || lines.endsWith("\n"))
            assertFalse(lines.contains("\n\n") || lines.contains(" \n") || lines.contains("\n "))
        }
    }

    @Test
    fun lowercasesAsciiOnly() {
        assertEquals("abcxyz", TextFold.foldKey("ABCxyz"))
        // Turkish dotted I, Kelvin sign, Greek capitals and full-width letters stay.
        assertEquals("\u0130\u212A\u0395\uFF21", TextFold.foldKey("\u0130\u212A\u0395\uFF21"))
    }

    @Test
    fun worksOnCodeUnitsSoSurrogatePairsPassThrough() {
        assertEquals("\uD83D\uDE00 x", TextFold.foldKey("\uD83D\uDE00  X"))
        // A lone surrogate is kept as is (no code-point decoding).
        assertEquals("a\uD800b", TextFold.foldKey("A\uD800B"))
    }

    /** Dart's `String.trim()` set, probed with the Dart SDK over the whole BMP (T-038). */
    @Test
    fun dartTrimSetIsExactlyDarts() {
        val dart = setOf(
            0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680,
            0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
            0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
        )
        for (u in 0 until 0x10000) {
            assertEquals("U+${u.toString(16)}", u in dart, TextFold.isDartTrimWhitespace(u.toChar()))
        }
        assertEquals("x", TextFold.dartTrim("\uFEFF\u0085x\u3000"))
        assertEquals("\u001Cx\u001F", TextFold.dartTrim("\u001Cx\u001F"))
        // Kotlin's own trim differs on both counts: why it is never used.
        assertTrue("\uFEFFx".trim() != "x" && "\u001Cx".trim() == "x")
    }

    @Test
    fun lengthIsInUtf16Units() {
        val emoji = "\uD83D\uDE00"
        val body = emoji.repeat(2001)
        assertEquals(4002, body.length)
        val guard = CaptureGuard(GuardConfig.parse(GuardFixtures.t1Base, null).config)
        assertEquals(mapOf("decision" to "drop", "reason" to "too_long"), decision(guard.decide("sms", "NBE", body)))
    }
}
