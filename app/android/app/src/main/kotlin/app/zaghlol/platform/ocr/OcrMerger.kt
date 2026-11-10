package app.zaghlol.platform.ocr

/**
 * Merges ML Kit Latin lines and Tesseract `ara` lines by bounding box
 * (ADR-009). Pure Kotlin.
 *
 * Rules, when both engines ran:
 * - Tesseract lines that contain an Arabic letter are kept.
 * - An ML Kit line whose box overlaps a kept Arabic line (intersection over the
 *   smaller box area >= [OVERLAP]) is dropped; its tokens that contain an ASCII
 *   digit and are missing from the Arabic line (compared after digit
 *   normalisation) are appended to that line, because ML Kit reads digits better.
 * - Every other ML Kit line is kept.
 * - Tesseract lines without Arabic letters are dropped (duplicates or noise).
 * When only one engine ran, its lines are returned unchanged. The result is
 * sorted top to bottom, then left to right.
 *
 * The thresholds are unvalidated (SPK-02 has no results yet).
 */
object OcrMerger {
    const val OVERLAP = 0.5

    fun merge(latin: List<RawLine>?, arabic: List<RawLine>?): List<RawLine> {
        val l = latin?.filter { it.text.isNotBlank() }
        val a = arabic?.filter { it.text.isNotBlank() }
        val merged = when {
            l == null && a == null -> emptyList()
            a == null -> l!!
            l == null -> a
            else -> mergeBoth(l, a.filter { hasArabicLetter(it.text) })
        }
        return merged.sortedWith(compareBy({ it.top }, { it.left }))
    }

    private fun mergeBoth(latin: List<RawLine>, arabic: List<RawLine>): List<RawLine> {
        val arabicText = arabic.map { it.text }.toTypedArray()
        val kept = ArrayList<RawLine>()
        for (line in latin) {
            val idx = arabic.indices
                .map { it to overlap(line, arabic[it]) }
                .filter { it.second >= OVERLAP }
                .maxByOrNull { it.second }?.first
            if (idx == null) {
                kept.add(line)
            } else {
                val have = normalizeDigits(arabicText[idx])
                val extra = line.text.split(WHITESPACE)
                    .filter { t -> t.any { it in '0'..'9' } && !have.contains(normalizeDigits(t)) }
                if (extra.isNotEmpty()) arabicText[idx] = arabicText[idx] + " " + extra.joinToString(" ")
            }
        }
        arabic.forEachIndexed { i, line -> kept.add(line.copy(text = arabicText[i])) }
        return kept
    }

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
