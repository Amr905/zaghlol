package app.zaghlol.platform.capture.inbox

import java.util.zip.CRC32

/**
 * The opaque paging token of [InboxReader] (T-042 design note section 3):
 * `v1.<chunk>.<lastId>.<crc32>`, where `crc32` covers the bound sender
 * variants (in query order) and the requested `since`. A token from another
 * query (other senders, other `since`, another Guard allowlist) or a
 * malformed one decodes to null, which the reader reports as
 * `INVALID_ARGUMENT`; it never silently skips or restarts.
 *
 * Not a security boundary: a forged token can only move the `_id` floor
 * inside the same allowlisted query.
 */
internal object InboxCursor {
    class Position(val chunk: Int, val lastId: Long) {
        override fun toString(): String = "InboxCursor.Position($chunk, $lastId)"
    }

    private const val MAX_TOKEN_LENGTH = 64
    private val FORMAT = Regex("""v1\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,18})\.([0-9a-f]{8})""")

    /** Hex and decimals are built without locale formatting (ASCII digits in every locale). */
    fun encode(chunk: Int, lastId: Long, crc: Long): String =
        "v1." + chunk.toString() + "." + lastId.toString() + "." + crc.toString(16).padStart(8, '0')

    /** Null when malformed, from another query ([crc]) or pointing past [chunks]. */
    fun decode(token: String, crc: Long, chunks: Int): Position? {
        if (token.length > MAX_TOKEN_LENGTH) return null
        val m = FORMAT.matchEntire(token) ?: return null
        val chunk = m.groupValues[1].toInt()
        val lastId = m.groupValues[2].toLongOrNull() ?: return null
        val tokenCrc = m.groupValues[3].toLong(16)
        if (tokenCrc != crc || chunk >= chunks) return null
        return Position(chunk, lastId)
    }

    /** Over the variants of every chunk, in order (chunk boundaries included), and [since]. */
    fun crcOf(chunks: List<List<String>>, since: Long): Long {
        val crc = CRC32()
        for (chunk in chunks) {
            for (v in chunk) {
                crc.update(v.toByteArray(Charsets.UTF_8))
                crc.update(0)
            }
            crc.update(1)
        }
        for (i in 7 downTo 0) crc.update((since ushr (i * 8)).toInt() and 0xff)
        return crc.value
    }
}
