package app.zaghlol.platform.ocr

/**
 * Merges ML Kit Latin lines and Tesseract `ara` lines by bounding box
 * (ADR-009, validated rule from T-273). Pure Kotlin.
 *
 * The `ara` model reads Latin text as Arabic-letter noise with wrong digits, so
 * a Tesseract line is only trusted when it is credibly Arabic ([credibleArabic]:
 * confidence >= [MIN_ARABIC_CONFIDENCE] and Arabic letters are the majority of
 * its letters). Rules, when both engines ran:
 * - Tesseract lines that are not credibly Arabic are dropped, whether or not an
 *   ML Kit line overlaps them.
 * - A credible Arabic line that overlaps only strong ML Kit lines ([strongLatin]:
 *   at least 3 Latin letters in words of 2+ letters, or no letters at all, i.e.
 *   digits or an amount) leaves those lines as they are and only contributes its
 *   Arabic words (tokens with 2+ letters, mostly Arabic, no digits), appended.
 * - A credible Arabic line that overlaps a weak ML Kit line (garbage) replaces it.
 *   ML Kit's digits win: the Arabic line's digit tokens are removed and the ML Kit
 *   digit tokens are appended.
 * - A credible Arabic line with no overlapping ML Kit line is kept as it is.
 * - Every other ML Kit line is kept.
 * When only one engine ran, its lines are returned unchanged. The result is
 * sorted top to bottom, then left to right. Recognised text is never logged.
 */
object OcrMerger {
    const val OVERLAP = 0.5

    /** Measured on the PO photo (T-273): noise lines 0.00-0.56, the one real Arabic line 0.67. */
    const val MIN_ARABIC_CONFIDENCE = 0.60

    fun merge(latin: List<RawLine>?, arabic: List<RawLine>?): List<RawLine> {
        val l = latin?.filter { it.text.isNotBlank() }
        val a = arabic?.filter { it.text.isNotBlank() }
        val merged = when {
            l == null && a == null -> emptyList()
            a == null -> l!!
            l == null -> a
            else -> mergeBoth(l, a.filter { credibleArabic(it) })
        }
        return merged.sortedWith(compareBy({ it.top }, { it.left }))
    }

    private fun mergeBoth(latin: List<RawLine>, arabic: List<RawLine>): List<RawLine> {
        val match = latin.map { line ->
            arabic.indices
                .map { it to overlap(line, arabic[it]) }
                .filter { it.second >= OVERLAP }
                .maxByOrNull { it.second }?.first
        }
        val replacing = HashSet<Int>()
        latin.indices.forEach { i -> match[i]?.let { if (!strongLatin(latin[i].text)) replacing.add(it) } }
        val latinText = latin.map { it.text }.toTypedArray()
        val arabicText = arabic.map { it.text }.toTypedArray()
        val appended = HashSet<Int>()
        val digitsWin = HashMap<Int, MutableList<String>>()
        val kept = ArrayList<RawLine>()
        for ((i, line) in latin.withIndex()) {
            val idx = match[i]
            when {
                idx == null -> kept.add(line)
                idx in replacing -> {
                    if (strongLatin(line.text)) {
                        kept.add(line)
                    } else {
                        val d = digitTokens(line.text)
                        if (d.isNotEmpty()) digitsWin.getOrPut(idx) { ArrayList() }.addAll(d)
                    }
                }
                else -> {
                    val words = if (idx in appended) emptyList() else arabicWords(arabicText[idx], latinText[i])
                    appended.add(idx)
                    kept.add(if (words.isEmpty()) line else line.copy(text = line.text + " " + words.joinToString(" ")))
                }
            }
        }
        for ((i, digits) in digitsWin) {
            val own = arabicText[i].split(WHITESPACE).filter { t -> !t.any { isDigit(it) } }
            arabicText[i] = (own + digits).joinToString(" ")
        }
        arabic.forEachIndexed { i, line ->
            val overlapped = match.any { it == i }
            if (!overlapped || i in replacing) kept.add(line.copy(text = arabicText[i]))
        }
        return kept
    }

    /** Confidence at or above the threshold and Arabic letters are the majority of the letters. */
    fun credibleArabic(line: RawLine): Boolean =
        line.confidence >= MIN_ARABIC_CONFIDENCE && arabicMajority(line.text)

    fun arabicMajority(s: String): Boolean {
        val letters = s.count { it.isLetter() }
        if (letters == 0) return false
        return s.count { isArabicLetter(it) } * 2 > letters
    }

    /** At least 3 Latin letters in words of 2+ letters, or no letters at all (digits and amounts only). */
    fun strongLatin(s: String): Boolean {
        if (s.none { it.isLetter() }) return true
        val n = s.split(WHITESPACE).sumOf { w ->
            val c = w.count { it in 'A'..'Z' || it in 'a'..'z' }
            if (c >= 2) c else 0
        }
        return n >= 3
    }

    private fun digitTokens(s: String): List<String> = s.split(WHITESPACE).filter { t -> t.any { it in '0'..'9' } }

    private fun isDigit(c: Char) = c in '0'..'9' || c in '٠'..'٩' || c in '۰'..'۹'

    /** Arabic words of a credible line that the ML Kit line does not have; never a token with digits. */
    private fun arabicWords(arabicLine: String, latinLine: String): List<String> =
        arabicLine.split(WHITESPACE)
            .map { it.filter { c -> c != '\u200E' && c != '\u200F' }.trim(':', ')', '(', ',', '.') }
            .filter { t ->
                t.none { isDigit(it) } && t.count { isArabicLetter(it) } >= 2 &&
                    arabicMajority(t) && !latinLine.contains(t)
            }

    private fun isArabicLetter(c: Char) = hasArabicLetter(c.toString())

    fun hasArabicLetter(s: String): Boolean = s.any {
        it in 'ء'..'ي' || it in 'ٮ'..'ۓ' || it in 'ݐ'..'ݿ' || it in 'ﭐ'..'﷿' || it in 'ﹰ'..'ﻼ'
    }

    /** Arabic-Indic and Persian digits and separators to ASCII, for comparison only. */
    fun normalizeDigits(s: String): String = buildString(s.length) {
        for (c in s) {
            append(
                when (c) {
                    in '٠'..'٩' -> '0' + (c - '٠')
                    in '۰'..'۹' -> '0' + (c - '۰')
                    '٫' -> '.'
                    '٬' -> ','
                    else -> c
                },
            )
        }
    }

    private fun overlap(a: RawLine, b: RawLine): Double {
        val w = minOf(a.right, b.right) - maxOf(a.left, b.left)
        val h = minOf(a.bottom, b.bottom) - maxOf(a.top, b.top)
        if (w <= 0 || h <= 0) return 0.0
        val smaller = minOf(a.width.toLong() * a.height, b.width.toLong() * b.height)
        if (smaller <= 0) return 0.0
        return (w.toLong() * h).toDouble() / smaller
    }

    private val WHITESPACE = Regex("\\s+")
}
