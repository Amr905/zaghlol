package app.zaghlol.platform.guard

/**
 * A strict RFC 8259 JSON reader for the Guard config (T-038 design note
 * section 3), matching Dart's `jsonDecode` on everything the config reader can
 * observe:
 * - objects are [LinkedHashMap] (`String` keys, insertion order); a duplicate
 *   key keeps its first position and takes the last value, like Dart's map;
 * - a number without fraction or exponent that fits in a [Long] is a [Long];
 *   any other number is a [Double] (Dart: `4.0`, `1e2` and integers beyond
 *   64 bits are `double`), so the reader's integer check rejects it;
 * - a lone surrogate escape (`"\ud800"`) is accepted, as in Dart;
 * - no trailing commas, single quotes, unquoted names, leading zeros,
 *   comments, raw control characters in strings, or `NaN`/`Infinity`; only
 *   space, tab, LF and CR are whitespace (a U+FEFF inside the text is an
 *   error; the byte-order mark is handled by the caller like Dart's
 *   `Utf8Decoder`).
 *
 * Nesting deeper than [MAX_DEPTH] is an error (no deep recursion on hostile
 * input; Dart has no limit, but no valid config is deeper than 4).
 * `org.json` is not used: it is lenient and a stub in JVM tests.
 *
 * Errors are [StrictJsonException] with a fixed message and never echo input.
 */
internal object StrictJson {
    const val MAX_DEPTH = 16

    fun parse(text: String): Any? {
        val p = Parser(text)
        p.skipWs()
        val v = p.value(0)
        p.skipWs()
        if (p.pos != text.length) throw StrictJsonException()
        return v
    }

    private class Parser(private val s: String) {
        var pos = 0

        fun skipWs() {
            while (pos < s.length) {
                val c = s[pos]
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') pos++ else return
            }
        }

        fun value(depth: Int): Any? {
            if (pos >= s.length) throw StrictJsonException()
            return when (val c = s[pos]) {
                '{' -> obj(depth + 1)
                '[' -> arr(depth + 1)
                '"' -> str()
                't' -> literal("true", true)
                'f' -> literal("false", false)
                'n' -> literal("null", null)
                else -> if (c == '-' || c in '0'..'9') num() else throw StrictJsonException()
            }
        }

        private fun literal(word: String, v: Any?): Any? {
            if (!s.startsWith(word, pos)) throw StrictJsonException()
            pos += word.length
            return v
        }

        private fun obj(depth: Int): Map<String, Any?> {
            if (depth > MAX_DEPTH) throw StrictJsonException()
            pos++ // {
            val map = LinkedHashMap<String, Any?>()
            skipWs()
            if (peek() == '}') {
                pos++
                return map
            }
            while (true) {
                skipWs()
                if (peek() != '"') throw StrictJsonException()
                val key = str()
                skipWs()
                if (peek() != ':') throw StrictJsonException()
                pos++
                skipWs()
                map[key] = value(depth)
                skipWs()
                when (peek()) {
                    ',' -> pos++
                    '}' -> {
                        pos++
                        return map
                    }
                    else -> throw StrictJsonException()
                }
            }
        }

        private fun arr(depth: Int): List<Any?> {
            if (depth > MAX_DEPTH) throw StrictJsonException()
            pos++ // [
            val list = ArrayList<Any?>()
            skipWs()
            if (peek() == ']') {
                pos++
                return list
            }
            while (true) {
                skipWs()
                list.add(value(depth))
                skipWs()
                when (peek()) {
                    ',' -> pos++
                    ']' -> {
                        pos++
                        return list
                    }
                    else -> throw StrictJsonException()
                }
            }
        }

        private fun peek(): Char = if (pos < s.length) s[pos] else throw StrictJsonException()

        private fun str(): String {
            pos++ // opening quote
            val out = StringBuilder()
            while (true) {
                if (pos >= s.length) throw StrictJsonException()
                val c = s[pos++]
                when {
                    c == '"' -> return out.toString()
                    c == '\\' -> {
                        if (pos >= s.length) throw StrictJsonException()
                        when (s[pos++]) {
                            '"' -> out.append('"')
                            '\\' -> out.append('\\')
                            '/' -> out.append('/')
                            'b' -> out.append('\b')
                            'f' -> out.append('\u000C')
                            'n' -> out.append('\n')
                            'r' -> out.append('\r')
                            't' -> out.append('\t')
                            'u' -> out.append(hex4())
                            else -> throw StrictJsonException()
                        }
                    }
                    c.code < 0x20 -> throw StrictJsonException()
                    else -> out.append(c)
                }
            }
        }

        private fun hex4(): Char {
            if (pos + 4 > s.length) throw StrictJsonException()
            var v = 0
            for (i in 0 until 4) {
                val d = Character.digit(s[pos + i], 16)
                // Character.digit accepts non-ASCII digits; JSON allows only ASCII hex.
                if (d < 0 || s[pos + i].code > 0x7F) throw StrictJsonException()
                v = v * 16 + d
            }
            pos += 4
            return v.toChar()
        }

        private fun num(): Any {
            val start = pos
            if (s[pos] == '-') pos++
            if (pos >= s.length) throw StrictJsonException()
            if (s[pos] == '0') {
                pos++
            } else if (s[pos] in '1'..'9') {
                while (pos < s.length && s[pos] in '0'..'9') pos++
            } else {
                throw StrictJsonException()
            }
            var integral = true
            if (pos < s.length && s[pos] == '.') {
                integral = false
                pos++
                digits()
            }
            if (pos < s.length && (s[pos] == 'e' || s[pos] == 'E')) {
                integral = false
                pos++
                if (pos < s.length && (s[pos] == '+' || s[pos] == '-')) pos++
                digits()
            }
            val text = s.substring(start, pos)
            if (integral) {
                text.toLongOrNull()?.let { return it }
            }
            return text.toDouble()
        }

        private fun digits() {
            val start = pos
            while (pos < s.length && s[pos] in '0'..'9') pos++
            if (pos == start) throw StrictJsonException()
        }
    }
}

/** Malformed JSON. The message is fixed: never any part of the input. */
internal class StrictJsonException : RuntimeException("invalid JSON") {
    override fun fillInStackTrace(): Throwable = this
}
