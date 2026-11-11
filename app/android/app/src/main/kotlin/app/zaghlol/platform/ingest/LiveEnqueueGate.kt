package app.zaghlol.platform.ingest

/**
 * Coalesces live-work enqueues (FU-108 security L-1 and code m-2, owner
 * T-040). With `APPEND_OR_REPLACE` every enqueue appends one more run to the
 * unique chain, so a burst of N messages queued N expedited runs (each
 * spending expedited quota on Android 12+ to find an empty spool). Here an
 * enqueue is **skipped while a live run is already waiting** (WorkManager
 * state `ENQUEUED` or `BLOCKED`): that run has not started, so it will
 * drain the entry the caller wrote before calling (the write always
 * precedes the check). A live run that is `RUNNING` is not waiting (its
 * drain may have passed the new entry), so the caller appends one successor.
 * Result: at most one waiting live run behind at most one running one.
 *
 * Fail towards draining: when the state can't be read ([waitingLive] returns
 * null or throws) the enqueue happens. On the main thread [enqueue] never
 * blocks (T-041): the state query would, so the caller's enqueue runs
 * without it. Off the main thread the check and the enqueue are serialized
 * in this process, so two intake threads can't both see "none waiting".
 */
class LiveEnqueueGate(
    /** True when a live run is `ENQUEUED`/`BLOCKED`; null when unknown. May block (bounded). */
    private val waitingLive: () -> Boolean?,
    /** The `APPEND_OR_REPLACE` enqueue (waits until persisted off the main thread). */
    private val enqueueLive: () -> Unit,
    private val onMainThread: () -> Boolean,
) {
    private val lock = Any()

    /** Returns true when a run was enqueued, false when a waiting run covers it. Throws what [enqueueLive] throws. */
    fun enqueue(): Boolean {
        if (onMainThread()) {
            enqueueLive()
            return true
        }
        synchronized(lock) {
            val waiting = try {
                waitingLive()
            } catch (_: Exception) {
                null
            }
            
            enqueueLive()
            return true
        }
    }

    override fun toString(): String = "LiveEnqueueGate"
}
