package app.zaghlol.platform.guard

/**
 * Kotlin port of `foldKey` / `foldKeyLines` from
 * `packages/zaghlol_parsing/lib/normalize/text_normalizer.dart` (T-013, T-035
 * fix round 2), plus Dart's `String.trim()` whitespace set.
 *
 * Port rules (T-038 design note section 2), each pinned by the golden `fold`
 * vectors: the loop runs over [Char] (UTF-16 code units) exactly like Dart's
 * `_transform`; the tables are copied from it; ASCII `A..Z` is lowercased by
 * `+ 0x20` only. Never `lowercase()`, `java.text.Normalizer` or a [java.util.Locale]
 * (Turkish dotted I, Kelvin sign and Greek look-alikes must stay as they are).
 */
internal object TextFold {
    private const val SPACE = ' '
    private const val LINE_FEED = '\n'

    /** Digits, separators, invisible marks, tatweel/harakat, letter variants, ASCII lowercase, whitespace runs to one space, trimmed. */
    fun foldKey(input: String): String = transform(input, lines = false)

    /**
     * [foldKey], except a whitespace run that contains a line break becomes one
     * `\n`. `foldKeyLines(x).replace('\n', ' ') == foldKey(x)` for every `x`
     * (tested). Used only for the global drop patterns.
     */
    fun foldKeyLines(input: String): String = transform(input, lines = true)

    /**
     * Dart's `String.trim()`: removes leading and trailing code units of
     * Dart's whitespace set ([isDartTrimWhitespace]). Kotlin's `trim()` uses
     * [Char.isWhitespace], a different set (it trims U+001C..001F and keeps
     * U+0085 and U+FEFF), so it is never used on a Guard source.
     */
    fun dartTrim(input: String): String {
        var start = 0
        var end = input.length
        while (start < end && isDartTrimWhitespace(input[start])) start++
        while (end > start && isDartTrimWhitespace(input[end - 1])) end--
        return if (start == 0 && end == input.length) input else input.substring(start, end)
    }

    /** The code units Dart's `String.trim()` removes (Dart SDK `_isWhitespace`; probed over all of the BMP). */
    fun isDartTrimWhitespace(c: Char): Boolean {
        val u = c.code
        return (u in 0x09..0x0D) ||
            u == 0x20 ||
            u == 0x85 ||
            u == 0xA0 ||
            u == 0x1680 ||
            (u in 0x2000..0x200A) ||
            u == 0x2028 ||
            u == 0x2029 ||
            u == 0x202F ||
            u == 0x205F ||
            u == 0x3000 ||
            u == 0xFEFF
    }

    private fun transform(input: String, lines: Boolean): String {
        val out = StringBuilder(input.length)
        var pendingSpace = false
        var pendingBreak = false
        var wroteAny = false
        for (i in 0 until input.length) {
            val c = input[i]
            if (isSpace(c)) {
                pendingSpace = true
                if (lines && isLineBreak(c)) pendingBreak = true
                continue
            }
            if (isInvisible(c) || isMatchingMark(c)) continue
            if (pendingSpace && wroteAny) out.append(if (pendingBreak) LINE_FEED else SPACE)
            pendingSpace = false
            pendingBreak = false
            wroteAny = true
            out.append(foldLetter(mapChar(c)))
        }
        return out.toString()
    }

    private fun isSpace(c: Char): Boolean {
        val u = c.code
        return u == 0x20 ||
            (u in 0x09..0x0D) ||
            u == 0x85 ||
            u == 0xA0 ||
            u == 0x202F ||
            u == 0x2009 ||
            u == 0x2028 ||
            u == 0x2029
    }

    /** LF, VT, FF, CR, NEL, LINE SEPARATOR, PARAGRAPH SEPARATOR. Tab is not one. */
    private fun isLineBreak(c: Char): Boolean {
        val u = c.code
        return (u in 0x0A..0x0D) || u == 0x85 || u == 0x2028 || u == 0x2029
    }

    private fun isInvisible(c: Char): Boolean {
        val u = c.code
        return (u in 0x200B..0x200F) ||
            (u in 0x202A..0x202E) ||
            (u in 0x2066..0x2069) ||
            u == 0x061C ||
            u == 0x2060 ||
            u == 0x00AD ||
            u == 0xFEFF
    }

    private fun isMatchingMark(c: Char): Boolean {
        val u = c.code
        return u == 0x0640 || (u in 0x064B..0x0652) || u == 0x0670
    }

    private fun mapChar(c: Char): Char {
        val u = c.code
        return when {
            u in 0x0660..0x0669 -> (0x30 + (u - 0x0660)).toChar()
            u in 0x06F0..0x06F9 -> (0x30 + (u - 0x06F0)).toChar()
            u == 0x066B -> '.'
            u == 0x066C -> ','
            else -> c
        }
    }

    private fun foldLetter(c: Char): Char {
        val u = c.code
        return when {
            u == 0x0623 || u == 0x0625 || u == 0x0622 || u == 0x0671 -> '\u0627'
            u == 0x0649 -> '\u064A'
            u == 0x0629 -> '\u0647'
            u in 0x41..0x5A -> (u + 0x20).toChar()
            else -> c
        }
    }
}
