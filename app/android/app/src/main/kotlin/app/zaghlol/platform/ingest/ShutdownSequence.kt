package app.zaghlol.platform.ingest

/** Delayed callbacks on the main thread ([android.os.Handler] in the app, a manual clock in tests). */
interface MainTimers {
    fun postDelayed(task: Runnable, delayMs: Long)

    fun cancel(task: Runnable)
}

/**
 * The shutdown of one headless engine (T-008 review F1; T-041 design note
 * section 5). Main thread only.
 *
 * The engine is never destroyed while a drain reply is pending or before
 * Dart has closed the database:
 * 1. [request] sends `close` at once ([sendClose]), even while a drain is
 *    pending: Dart stops the running cycle after its current batch, waits
 *    for it, awaits the database close and then answers. So an attaching UI
 *    engine waits for one batch, not a whole cycle (T-041).
 * 2. [teardown] (`FlutterEngine.destroy`) runs exactly once, after **both**
 *    the close reply and any pending drain reply (Dart answers the drain
 *    first), or when the bound passes: [drainWaitMs] + [closeWaitMs] when a
 *    drain was pending at the request, else [closeWaitMs].
 *
 * The bounds exist only for a Dart side that never answers (hung isolate);
 * then the engine is destroyed anyway (FU-093 N4: nothing acked is lost; an
 * unacked batch is re-delivered and deduped by `body_hash`). [abort] skips
 * the sequence for an engine whose Dart side never started.
 */
class ShutdownSequence(
    private val timers: MainTimers,
    private val sendClose: (onReply: () -> Unit) -> Unit,
    private val teardown: () -> Unit,
    private val drainWaitMs: Long = DRAIN_WAIT_MS,
    private val closeWaitMs: Long = CLOSE_WAIT_MS,
) {
    enum class State { RUNNING, CLOSING, GONE }

    var state = State.RUNNING
        private set

    private var drainPending = false
    private var closeAnswered = false
    private val bound = Runnable { finish() }

    /** True when a drain may be sent to this engine. */
    fun acceptsDrain(): Boolean = state == State.RUNNING

    /** A drain command was sent; its reply is pending. */
    fun drainSent() {
        drainPending = true
    }

    /** The pending drain was answered (or abandoned). */
    fun drainAnswered() {
        drainPending = false
        maybeFinish()
    }

    /** Starts the shutdown (idempotent): `close` goes out now. */
    fun request() {
        if (state != State.RUNNING) return
        state = State.CLOSING
        timers.postDelayed(bound, if (drainPending) drainWaitMs + closeWaitMs else closeWaitMs)
        try {
            sendClose {
                closeAnswered = true
                maybeFinish()
            }
        } catch (_: Exception) {
            finish()
        }
    }

    /** Destroys at once: the engine failed before its Dart side could run. */
    fun abort() = finish()

    private fun maybeFinish() {
        if (state == State.CLOSING && closeAnswered && !drainPending) finish()
    }

    private fun finish() {
        if (state == State.GONE) return
        timers.cancel(bound)
        state = State.GONE
        teardown()
    }

    companion object {
        /** Longer than a Dart cycle (kCycleBudget, 50 s): a hung isolate only. */
        const val DRAIN_WAIT_MS = 55_000L

        /** Dart's close waits for the current batch and the DB close. */
        const val CLOSE_WAIT_MS = 5_000L
    }
}
