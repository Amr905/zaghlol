package app.zaghlol.spike.sms

/**
 * Process-wide drain claim (design note section 4): spool entries are handed
 * to one engine at a time, so the UI and headless engines never process the
 * same entry concurrently. The claim belongs to the engine whose host drained
 * last; it is released when that engine acks everything it drained, when the
 * engine detaches, or [ttlMs] after the last drain.
 *
 * All capture components run in the app's default process, so a JVM lock is
 * enough (the same assumption as SpoolKey, FU-068).
 */
class SpoolClaim(
    private val clock: () -> Long = System::currentTimeMillis,
    private val ttlMs: Long = TTL_MS,
) {
    private var owner: Long? = null
    private var expiresAt = 0L
    private val held = HashSet<String>()

    /**
     * Tries to take (or renew) the claim for [engine]. Returns false while
     * another engine holds an unexpired claim.
     */
    @Synchronized
    fun acquire(engine: Long): Boolean {
        val current = owner
        if (current != null && current != engine && clock() < expiresAt) return false
        if (current != engine) held.clear()
        owner = engine
        expiresAt = clock() + ttlMs
        return true
    }

    /** Records the ids [engine] just drained. Ignored unless it owns the claim. */
    @Synchronized
    fun hold(engine: Long, ids: Collection<String>) {
        if (owner != engine) return
        held.addAll(ids)
        if (held.isEmpty()) release(engine)
    }

    /** [engine] acked [ids]; the claim is released once nothing it drained is left. */
    @Synchronized
    fun acked(engine: Long, ids: Collection<String>) {
        if (owner != engine) return
        held.removeAll(ids.toSet())
        if (held.isEmpty()) release(engine)
    }

    /** Engine detached (or gave up): drops its claim, never another engine's. */
    @Synchronized
    fun release(engine: Long) {
        if (owner != engine) return
        owner = null
        held.clear()
        expiresAt = 0L
    }

    @Synchronized
    fun ownerOrNull(): Long? {
        val current = owner ?: return null
        if (clock() >= expiresAt) {
            owner = null
            held.clear()
            return null
        }
        return current
    }

    companion object {
        const val TTL_MS = 60_000L
    }
}
