package app.zaghlol.platform.ocr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OcrMergerTest {
    private fun line(text: String, l: Int, t: Int, r: Int, b: Int, c: Double = 0.9) = RawLine(text, c, l, t, r, b)

    @Test
    fun singleEngineIsReturnedSortedAndBlankLinesDropped() {
        val out = OcrMerger.merge(
            latin = listOf(line("B", 0, 50, 10, 60), line("  ", 0, 30, 10, 40), line("A", 0, 10, 10, 20)),
            arabic = null,
        )
        assertEquals(listOf("A", "B"), out.map { it.text })
    }

    @Test
    fun arabicOnlyRunKeepsLinesWithoutArabicLetters() {
        val out = OcrMerger.merge(latin = null, arabic = listOf(line("123", 0, 0, 50, 10)))
        assertEquals(listOf("123"), out.map { it.text })
    }

    @Test
    fun arabicLineReplacesOverlappingLatinGarbage() {
        val out = OcrMerger.merge(
            latin = listOf(line("Jlaa Jlj", 100, 10, 300, 40, 0.3)),
            arabic = listOf(line("تم تحويل المبلغ", 98, 8, 302, 42)),
        )
        assertEquals(listOf("تم تحويل المبلغ"), out.map { it.text })
    }

    @Test
    fun digitsFromLatinAreAppendedWhenArabicMissedThemAfterNormalisation() {
        val out = OcrMerger.merge(
            latin = listOf(line("EGP 1,250.00 ref 99812", 0, 0, 400, 30)),
            arabic = listOf(line("المبلغ ١٬٢٥٠٫٠٠", 0, 0, 400, 30)),
        )
        // "1,250.00" is already present as Arabic-Indic digits, so only the rest is added.
        assertEquals("المبلغ ١٬٢٥٠٫٠٠ 99812", out.single().text)
    }

    @Test
    fun nonOverlappingLinesFromBothEnginesAreKept() {
        val out = OcrMerger.merge(
            latin = listOf(line("Ref 5555", 0, 100, 200, 130)),
            arabic = listOf(line("المرسل", 0, 0, 200, 30), line("noise", 0, 200, 200, 230)),
        )
        assertEquals(listOf("المرسل", "Ref 5555"), out.map { it.text })
    }

    @Test
    fun smallOverlapIsNotAMatch() {
        val out = OcrMerger.merge(
            latin = listOf(line("Latin 1", 0, 0, 100, 100)),
            arabic = listOf(line("عربي", 0, 90, 100, 190)),
        )
        assertEquals(2, out.size)
    }

    @Test
    fun zeroAreaBoxesNeverOverlap() {
        val out = OcrMerger.merge(
            latin = listOf(line("x 1", 5, 5, 5, 5)),
            arabic = listOf(line("عربي", 0, 0, 10, 10)),
        )
        assertEquals(2, out.size)
    }

    @Test
    fun arabicLetterDetection() {
        assertTrue(OcrMerger.hasArabicLetter("abc ع"))
        assertFalse(OcrMerger.hasArabicLetter("123 ٠١٢ abc"))
    }

    @Test
    fun digitNormalisationCoversArabicIndicAndPersianDigits() {
        assertEquals("0123456789.,", OcrMerger.normalizeDigits("٠١٢٣٤٥٦٧٨٩٫٬"))
        assertEquals("45", OcrMerger.normalizeDigits("۴۵"))
    }

    @Test
    fun sampleSizeKeepsDecodedPixelsUnderTheCap() {
        assertEquals(1, OcrLimits.sampleSizeFor(1080, 2400))
        assertEquals(1, OcrLimits.sampleSizeFor(2000, 4000))
        assertEquals(2, OcrLimits.sampleSizeFor(4000, 4001))
        val s = OcrLimits.sampleSizeFor(8000, 8000) // 64 MP
        assertEquals(4, s)
        assertTrue((8000L / s) * (8000L / s) <= OcrLimits.DECODE_MAX_PIXELS)
        assertEquals(1, OcrLimits.sampleSizeFor(1, 1))
    }
}
