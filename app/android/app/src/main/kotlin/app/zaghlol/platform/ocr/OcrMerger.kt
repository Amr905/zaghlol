package app.zaghlol.platform.ocr

/**
 * Merges ML Kit Latin lines and Tesseract `ara` lines by bounding box
 * (ADR-009, validated rule from T-273). Pure Kotlin.
 *
 * The `ara` model reads Latin text as Arabic-letter noise with wrong digits. Two
 * thresholds (ADR-009): a Tesseract line is a candidate when Arabic letters are the
 * majority of its letters and confidence >= [MIN_ARABIC_CONFIDENCE] (real Arabic lines
 * can score 0.45-0.6); where it overlaps a STRONG ML Kit line (real Latin words or an
 * amount, see [strongLatin]) it must reach [STRONG_OVERLAP_CONFIDENCE], because that
 * is where the noise happens. Rules, when both engines ran:
 * - Candidates that fail those bars are dropped.
 * - A credible Arabic line that overlaps a strong ML Kit line leaves it as it is and
 *   appends its Arabic words (2+ letters, mostly Arabic, no digits). If the ML Kit line
 *   has no ASCII digits, the Arabic line's amount-like digit tokens (normalised to ASCII,
 *   never a token mixing digit scripts) are appended too, so an amount is never lost.
 * - A credible Arabic line that overlaps only weak ML Kit lines (garbage) replaces them.
 *   ML Kit's digits win when it has any: the Arabic digit tokens are removed and the
 *   ML Kit digit tokens are appended.
 * - A credible Arabic line with no overlapping ML Kit line is kept as it is.
 * - Every other ML Kit line is kept.
 * When only one engine ran, its lines are returned unchanged. The result is
 * sorted top to bottom, then left to right. Recognised text is never logged.
 */
object OcrMerger {
    const val OVERLAP = 0.5

    /** Floor for any Arabic line (T-273 fix): real Arabic merchant and total lines can sit at 0.45-0.6. */
    const val MIN_ARABIC_CONFIDENCE = 0.45

    /** Needed only where the line overlaps a strong ML Kit line; PO photo: noise 0.00-0.56, real line 0.67. */
    const val STRONG_OVERLAP_CONFIDENCE = 0.60

    /** Gate only (FU-377): share of the smaller height two boxes must share vertically to count as one row. */
    const val GATE_ROW_OVERLAP = 0.3

    fun merge(latin: List<RawLine>?, arabic: List<RawLine>?): List<RawLine> {
        val l = latin?.filter { it.text.isNotBlank() }
        val a = arabic?.filter { it.text.isNotBlank() }
        val merged = when {
            l == null && a == null -> emptyList()
            a == null -> l!!
            l == null -> a
            else -> mergeBoth(l, a.filter { credibleArabic(it) }.filter { passesOverlapGate(it, l) })
        }
        return merged.sortedWith(compareBy({ it.top }, { it.left }))
    }

    /**
     * Below [STRONG_OVERLAP_CONFIDENCE] a line must not sit on a strong ML Kit line. The gate uses a
     * looser test than the merge match (FU-377): noise that drifted vertically still overlaps by
     * [GATE_ROW_OVERLAP] of the smaller height, so it counts; a real line on its own row does not.
     */
    private fun passesOverlapGate(line: RawLine, latin: List<RawLine>): Boolean =
        line.confidence >= STRONG_OVERLAP_CONFIDENCE ||
            latin.none { strongLatin(it.text) && sharesRow(it, line) }

    private fun sharesRow(a: RawLine, b: RawLine): Boolean {
        val w = minOf(a.right, b.right) - maxOf(a.left, b.left)
        val h = minOf(a.bottom, b.bottom) - maxOf(a.top, b.top)
        val smallerHeight = minOf(a.bottom - a.top, b.bottom - b.top)
        if (w <= 0 || h <= 0 || smallerHeight <= 0) return false
        return h.toDouble() / smallerHeight >= GATE_ROW_OVERLAP
    }

    /** A strong ML Kit line with an amount-like token (not any digit) on the same box: its digits win over the Arabic line's (FU-376). */
    private fun strongAmountOverlaps(arabicLine: RawLine, latin: List<RawLine>): Boolean =
        latin.any {
            strongLatin(it.text) && digitTokens(it.text).any { t -> amountLike(t) } &&
                overlap(it, arabicLine) >= OVERLAP
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
        val strongKept = HashMap<Int, MutableList<String>>()
        val kept = ArrayList<RawLine>()
        for ((i, line) in latin.withIndex()) {
            val idx = match[i]
            when {
                idx == null -> kept.add(line)
                idx in replacing -> {
                    if (strongLatin(line.text)) {
                        kept.add(line)
                        strongKept.getOrPut(idx) { ArrayList() }.add(line.text)
                    } else {
                        val d = digitTokens(line.text)
                        if (d.isNotEmpty()) digitsWin.getOrPut(idx) { ArrayList() }.addAll(d)
                    }
                }
                else -> {
                    val extra = if (idx in appended) {
                        emptyList()
                    } else {
                        arabicWords(arabicText[idx], latinText[i]) +
                            if (digitTokens(line.text).isEmpty() && !strongAmountOverlaps(arabic[idx], latin)) {
                                arabicAmountTokens(arabicText[idx])
                            } else {
                                emptyList()
                            }
                    }
                    appended.add(idx)
                    kept.add(if (extra.isEmpty()) line else line.copy(text = line.text + " " + extra.joinToString(" ")))
                }
            }
        }
        for ((i, digits) in digitsWin) {
            val own = arabicText[i].split(WHITESPACE).filter { t -> !t.any { isDigit(it) } }
            arabicText[i] = (own + digits).joinToString(" ")
        }
        arabic.forEachIndexed { i, line ->
            val overlapped = match.any { it == i }
            if (!overlapped) {
                kept.add(line.copy(text = arabicText[i]))
            } else if (i in replacing) {
                // FU-371: words a kept strong ML Kit line already has must not appear twice.
                // Whole-token equality only (a substring match lost real amounts: "436" inside "1436").
                val strongTokens = strongKept[i].orEmpty()
                    .flatMap { it.split(WHITESPACE) }
                    .map { normalizeDigits(it.trim(':', ')', '(', ',', '.')) }
                    .filter { it.isNotEmpty() }
                    .toSet()
                val text = arabicText[i].split(WHITESPACE).filter { t ->
                    val bare = normalizeDigits(t.trim(':', ')', '(', ',', '.'))
                    bare.isEmpty() || bare !in strongTokens
                }.joinToString(" ")
                if (text.isNotBlank()) kept.add(line.copy(text = text))
            }
        }
        return kept
    }

    /** Confidence at or above [MIN_ARABIC_CONFIDENCE] and Arabic letters are the majority of the letters. */
    fun credibleArabic(line: RawLine): Boolean =
        line.confidence >= MIN_ARABIC_CONFIDENCE && arabicMajority(line.text)

    fun arabicMajority(s: String): Boolean {
        val letters = s.count { it.isLetter() }
        if (letters == 0) return false
        return s.count { isArabicLetter(it) } * 2 > letters
    }

    /**
     * A real Latin read: no letters at all (digits or an amount), or at least one word-like token
     * (3+ Latin letters, a vowel, no consonant-only start such as "Jl") that is backed by a second
     * word-like token, a token of 5+ letters, or another token with a digit or Arabic letter.
     * ML Kit's usual garbage on Arabic script ("Jlaa Jlj", "Jl J", "lall", "JI plw") is weak.
     */
    fun strongLatin(s: String): Boolean {
        if (s.none { it.isLetter() }) return true
        val tokens = s.split(WHITESPACE).filter { it.isNotEmpty() }
        val words = tokens.filter { wordLike(it) }
        // A currency code next to an amount ("KWD 5.000", "CHF 20.00") is a real read: the code must never be lost.
        val hasDigitToken = tokens.any { t -> t.any { c -> c in '0'..'9' } }
        if (hasDigitToken && tokens.any { t -> t.length == 3 && t.all { c -> c in 'A'..'Z' } }) return true
        if (words.isEmpty()) return false
        if (words.size >= 2 || words.any { latinLetters(it).length >= 5 }) return true
        return tokens.any { t -> t !in words && (t.any { isDigit(it) } || hasArabicLetter(t)) }
    }

    private fun latinLetters(t: String): String = t.filter { it in 'A'..'Z' || it in 'a'..'z' }

    private fun wordLike(t: String): Boolean {
        val w = latinLetters(t).lowercase()
        if (w.length < 3 || w.none { it in VOWELS }) return false
        if (w[0] !in VOWELS && w[1] !in VOWELS && w.substring(0, 2) !in CLUSTERS) return false
        return true
    }

    private val VOWELS = "aeiouy"
    private val CLUSTERS = setOf(
        "ch", "sh", "th", "wh", "ph", "st", "tr", "pr", "pl", "br", "cr", "dr", "fr", "gr",
        "cl", "bl", "fl", "gl", "sl", "sp", "sc", "sk", "sm", "sn", "sw", "tw", "kn", "wr", "qu",
    )

    /** Amount-like tokens of an Arabic line as ASCII; never a token that mixes digit scripts. */
    private fun arabicAmountTokens(arabicLine: String): List<String> =
        arabicLine.split(WHITESPACE)
            .map { it.filter { c -> c != '\u200E' && c != '\u200F' }.trim(':', ')', '(', ',', '.', '/') }
            .filter { t ->
                t.any { isDigit(it) } && t.none { it.isLetter() } &&
                    !(t.any { it in '0'..'9' } && t.any { it in '٠'..'٩' || it in '۰'..'۹' })
            }
            .map { normalizeDigits(it) }
            .filter { AMOUNT.matches(it) }

    /** FU-392: a decimal amount ("85.50") or three or more digits ("1436"); "Ref 12" is not one. */
    private fun amountLike(token: String): Boolean {
        val t = token.trim(':', ')', '(', ',', '.', '/')
        if (!AMOUNT.matches(t)) return false
        return t.any { it == '.' || it == ',' } && t.last().isDigit() || t.count { it in '0'..'9' } >= 3
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
    private val AMOUNT = Regex("\\d+([.,]\\d+)*")
}
