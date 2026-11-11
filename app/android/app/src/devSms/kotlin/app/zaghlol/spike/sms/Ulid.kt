package app.zaghlol.spike.sms

import java.security.SecureRandom

/**
 * ULIDs for spool entry names (Crockford base32, 26 chars: 48-bit ms time +
 * 80 random bits). Monotonic within the process, so entries written in the
 * same millisecond still sort in write order (drain is oldest first).
 */
class UlidGenerator(
    private val clock: () -> Long = System::currentTimeMillis,
    private val random: SecureRandom = SecureRandom(),
) {
    private var lastMs = -1L
    private val lastRandom = ByteArray(10)

    @Synchronized
    fun next(): String {
        val now = clock()
        if (now <= lastMs) {
            increment()
        } else {
            lastMs = now
            random.nextBytes(lastRandom)
            lastRandom[0] = (lastRandom[0].toInt() and 0x7F).toByte() // headroom for increments
        }
        return encode(lastMs, lastRandom)
    }

    private fun increment() {
        for (i in lastRandom.indices.reversed()) {
            val v = (lastRandom[i].toInt() and 0xFF) + 1
            lastRandom[i] = v.toByte()
            if (v <= 0xFF) return
        }
    }

    companion object {
        private const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
        val PATTERN = Regex("^[0-9A-HJKMNP-TV-Z]{26}$")

        fun isValid(id: String): Boolean = PATTERN.matches(id)

        internal fun encode(ms: Long, rnd: ByteArray): String {
            val out = CharArray(26)
            var t = ms
            for (i in 9 downTo 0) {
                out[i] = ALPHABET[(t and 31).toInt()]
                t = t ushr 5
            }
            // 80 random bits -> 16 chars.
            var acc = 0L
            var bits = 0
            var pos = 10
            for (b in rnd) {
                acc = (acc shl 8) or (b.toLong() and 0xFF)
                bits += 8
                while (bits >= 5) {
                    bits -= 5
                    out[pos++] = ALPHABET[((acc ushr bits) and 31).toInt()]
                }
            }
            return String(out)
        }
    }
}
