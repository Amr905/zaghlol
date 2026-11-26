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
    fun strongLatinLineKeepsItsDigitsAndGainsTheArabicWord() {
        val out = OcrMerger.merge(
            latin = listOf(line("EGP 1,250.00 ref 99812", 0, 0, 400, 30)),
            arabic = listOf(line("المبلغ ١٬٢٥٠٫٠٠", 0, 0, 400, 30)),
        )
        // "EGP" is a strong Latin read: ML Kit's line and digits win, the Arabic word is appended.
        assertEquals("EGP 1,250.00 ref 99812 المبلغ", out.single().text)
    }

    @Test
    fun weakLatinLineIsReplacedAndMlKitDigitsWin() {
        val out = OcrMerger.merge(
            latin = listOf(line("Jl 1,250.00", 0, 0, 400, 30)),
            arabic = listOf(line("المبلغ ١٢٥٠٠٠", 0, 0, 400, 30)),
        )
        assertEquals("المبلغ 1,250.00", out.single().text)
    }

    // Synthetic copies of the PO receipt (T-273): ML Kit reads the Latin lines, the ara model
    // returns Arabic-letter noise with wrong digits and low confidence.
    private val latinReceipt = listOf(
        line("Name: عميل", 0, 100, 500, 140, 0.9),
        line("Net Sales 382.46", 0, 300, 500, 340, 0.95),
        line("VAT 53.54", 0, 350, 500, 390, 0.95),
        line("Amount Due 436.00", 0, 400, 500, 440, 0.95),
        line("Visa 436.00", 0, 450, 500, 490, 0.95),
        line("Hotline: 19256", 0, 500, 500, 540, 0.9),
        line("WhatsApp on: 01200003680", 0, 550, 500, 590, 0.9),
    )
    private val araNoise = listOf(
        line("321146 535 أول١ا", 0, 302, 500, 338, 0.47),
        line("5.54 آم", 0, 352, 500, 388, 0.52),
        line("44600 ونا 11نا 481710", 0, 402, 500, 438, 0.22),
        line("0 وهم", 0, 452, 500, 488, 0.48),
        line("6 :01106", 0, 502, 500, 538, 0.48),
        line("1220 010 مم8 )12لا /", 0, 552, 500, 588, 0.48),
        line("عميل نقدى 1١5206:", 0, 98, 500, 142, 0.67),
    )

    @Test
    fun latinReceiptKeepsTheMlKitLines() {
        val out = OcrMerger.merge(latinReceipt, araNoise).map { it.text }
        for (t in listOf("Net Sales 382.46", "VAT 53.54", "Amount Due 436.00", "Visa 436.00", "Hotline: 19256")) {
            assertTrue(t, t in out)
        }
        assertEquals(latinReceipt.size, out.size)
        assertFalse(out.any { it.contains("44600") || it.contains("321146") || it.contains("1220") })
    }

    @Test
    fun mixedLineKeepsLatinAndAppendsCredibleArabicWordsWithoutArabicDigits() {
        val out = OcrMerger.merge(latinReceipt, araNoise).first().text
        assertEquals("Name: عميل نقدى", out)
        assertFalse(out.contains("5206"))
    }

    @Test
    fun lowConfidenceArabicWithoutOverlapIsDropped() {
        val out = OcrMerger.merge(
            latin = listOf(line("Ref 5555", 0, 0, 200, 30)),
            arabic = listOf(line("ممم ونا", 0, 100, 200, 130, 0.4)),
        )
        assertEquals(listOf("Ref 5555"), out.map { it.text })
    }

    @Test
    fun arabicReceiptIsUnchangedAndDigitsComeFromMlKit() {
        val out = OcrMerger.merge(
            latin = listOf(line("Jl 85.50", 0, 0, 400, 30), line("12", 0, 40, 400, 70)),
            arabic = listOf(
                line("الإجمالي ٨٥٫٥٠", 0, 0, 400, 30, 0.85),
                line("صيدلية النور", 0, 40, 400, 70, 0.9),
            ),
        )
        assertEquals(listOf("الإجمالي 85.50", "12 صيدلية النور"), out.map { it.text })
    }

    @Test
    fun arabicLineAtMidConfidenceWithoutOverlapIsKept() {
        val out = OcrMerger.merge(
            latin = listOf(line("Ref 5555", 0, 100, 200, 130)),
            arabic = listOf(line("الإجمالي ٨٥٫٥٠", 0, 0, 200, 30, 0.52)),
        )
        assertEquals(listOf("الإجمالي ٨٥٫٥٠", "Ref 5555"), out.map { it.text })
    }

    @Test
    fun arabicLineOverWeakGarbageIsKeptWithItsAmount() {
        val out = OcrMerger.merge(
            latin = listOf(line("Jlaa Jlj", 0, 0, 200, 30, 0.3)),
            arabic = listOf(line("الإجمالي ٨٥٫٥٠", 0, 0, 200, 30, 0.52)),
        )
        assertEquals(listOf("الإجمالي ٨٥٫٥٠"), out.map { it.text })
    }

    @Test
    fun arabicAmountIsAppendedWhenStrongMlKitLineHasNoDigits() {
        val out = OcrMerger.merge(
            latin = listOf(line("Total Amount", 0, 0, 200, 30)),
            arabic = listOf(line("الإجمالي ٨٥٫٥٠", 0, 0, 200, 30, 0.85)),
        )
        assertEquals(listOf("Total Amount الإجمالي 85.50"), out.map { it.text })
    }

    @Test
    fun arabicLineOverStrongAndWeakLinesDoesNotRepeatTheStrongLinesWords() {
        val out = OcrMerger.merge(
            latin = listOf(line("Total الكلي", 0, 0, 200, 30), line("Jl", 0, 30, 200, 60, 0.3)),
            arabic = listOf(line("الكلي المجموع", 0, 0, 200, 60, 0.85)),
        )
        val all = out.joinToString(" ") { it.text }
        assertEquals(1, Regex("الكلي").findAll(all).count())
        assertTrue(all.contains("المجموع"))
        assertTrue(all.contains("Total"))
    }

    @Test
    fun arabicNoiseDigitsDoNotDisagreeWithAStrongMlKitAmountOnTheSameBox() {
        val out = OcrMerger.merge(
            latin = listOf(line("Net Sales", 0, 300, 300, 340), line("382.46", 310, 300, 500, 340)),
            arabic = listOf(line("321146 535 أول١ا", 0, 302, 500, 338, 0.62)),
        )
        assertEquals(listOf("Net Sales", "382.46"), out.map { it.text })
    }

    @Test
    fun noiseDriftedVerticallyOverAStrongLineIsDroppedButARealRowBelowIsKept() {
        val out = OcrMerger.merge(
            latin = listOf(line("Net Sales 382.46", 0, 0, 500, 40)),
            arabic = listOf(
                line("أول١ا ممم", 0, 25, 500, 65, 0.5), // 0.375 of the height, 0.375 of the area: below 0.5
                line("الإجمالي", 0, 80, 500, 120, 0.5),
            ),
        )
        assertEquals(listOf("Net Sales 382.46", "الإجمالي"), out.map { it.text })
    }

    @Test
    fun confidenceBarsAreInclusiveAtExactly045AndExactly060() {
        val kept = OcrMerger.merge(
            latin = listOf(line("Ref 5555", 0, 100, 200, 130)),
            arabic = listOf(line("الإجمالي", 0, 0, 200, 30, 0.45)),
        )
        assertEquals(listOf("الإجمالي", "Ref 5555"), kept.map { it.text })
        val gate = OcrMerger.merge(
            latin = listOf(line("Total Amount", 0, 0, 200, 30)),
            arabic = listOf(line("الإجمالي كامل", 0, 0, 200, 30, 0.60)),
        )
        assertEquals(listOf("Total Amount الإجمالي كامل"), gate.map { it.text })
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
        assertTrue(OcrMerger.arabicMajority("عميل a"))
        assertFalse(OcrMerger.arabicMajority("44600 ab cd ع"))
        assertTrue(OcrMerger.strongLatin("Visa 436.00"))
        assertTrue(OcrMerger.strongLatin("436.00"))
        assertFalse(OcrMerger.strongLatin("Jl J"))
        assertFalse(OcrMerger.strongLatin("Jlaa Jlj"))
        assertFalse(OcrMerger.strongLatin("lall"))
        assertFalse(OcrMerger.strongLatin("JI plw"))
        assertTrue(OcrMerger.strongLatin("Amount Due"))
        assertTrue(OcrMerger.strongLatin("VAT 53.54"))
        assertTrue(OcrMerger.strongLatin("Name: عميل"))
        assertTrue(OcrMerger.strongLatin("KWD 5.000"))
        assertTrue(OcrMerger.strongLatin("CHF 20.00"))
        assertFalse(OcrMerger.strongLatin("KWD"))
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
