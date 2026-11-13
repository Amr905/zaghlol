package app.zaghlol.platform.capture

import java.nio.ByteBuffer
import java.security.MessageDigest

/**
 * In-memory repeat filter for notifications (T-043 design note section 6).
 * Apps re-post the same notification (progress, re-alerts, reboot restore);
 * the DB's `body_hash` is the final dedupe, this only saves spool writes and
 * worker runs. Keys are the first 16 bytes of `SHA-256(pkg || 0x00 || body)`
 * (an update with a new body is a new key, so it is stored). Never persisted,
 * never printed; resets with the process. LRU [capacity], entries expire
 * after [ttlMs] (provisional constants). The caller records a message only
 * after the spool write succeeded, so a refused or failed write is retried by
 * the app's next re-post. Single intake thread; still synchronized.
 */
class RecentNotifications(
    private val monoClockMs: () -> Long,
    private val capacity: Int = CAPACITY,
    private val ttlMs: Long = TTL_MS,
) {
    private val seen = object : LinkedHashMap<ByteBuffer, Long>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<ByteBuffer, Long>?): Boolean = size > capacity
    }

    /** True when the same package and body were stored within the TTL. */
    @Synchronized
    fun isRepeat(packageName: String, body: String): Boolean {
        val key = keyOf(packageName, body)
        val at = seen[key] ?: return false
        if (monoClockMs() - at < ttlMs) return true
        seen.remove(key)
        return false
    }

    /** Remember a message that was written to the spool. */
    @Synchronized
    fun remember(packageName: String, body: String) {
        seen[keyOf(packageName, body)] = monoClockMs()
    }

    override fun toString(): String = "RecentNotifications"

    companion object {
        const val CAPACITY = 128
        const val TTL_MS = 15L * 60_000L

        private fun keyOf(packageName: String, body: String): ByteBuffer {
            val md = MessageDigest.getInstance("SHA-256")
            md.update(packageName.toByteArray(Charsets.UTF_8))
            md.update(0)
            md.update(body.toByteArray(Charsets.UTF_8))
            return ByteBuffer.wrap(md.digest().copyOf(16))
        }
    }
}
