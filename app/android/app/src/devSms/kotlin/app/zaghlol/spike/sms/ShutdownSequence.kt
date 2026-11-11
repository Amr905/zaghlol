package app.zaghlol.spike.sms

/** Delayed callbacks on the main thread ([android.os.Handler] in the app, a manual clock in tests). */
interface MainTimers {
    fun postDelayed(task: Runnable, delayMs: Long)

    fun cancel(task: Runnable)
}

/**
 * The shutdown of one headless engine (review F1). Main thread only.
 *
 * The engine is never destroyed while a drain reply is pending or before
 * Dart has closed the database:
 * 1. [request] while a drain is pending: wait for its reply, at most
 *    [drainWaitMs] (the cycle commits and acks first, or is abandoned
 *    without an ack, which loses nothing).
 * 2. Send `close` ([sendClose]); Dart waits for any running cycle, awaits the
 *    database close and replies. Wait at most [closeWaitMs].
 * 3. [teardown] (FlutterEngine.destroy), exactly once.
 *
 * The bounds exist only for a Dart side that never answers (hung isolate);
 * then the engine is destroyed anyway, as before this fix. [abort] skips the
 * sequence for an engine whose Dart side never started (nothing to close).
 */
class ShutdownSequence(
    private val timers: MainTimers,
    private val sendClose: (onReply: () -> Unit) -> Unit,
    private val teardown: () -> Unit,
    private val drainWaitMs: Long = DRAIN_WAIT_MS,
    private val closeWaitMs: Long = CLOSE_WAIT_MS,
) {
    enum class State { RUNNING, WAITING_DRAIN, CLOSING, GONE }

    var state = State.RUNNING
        private set

    private var drainPending = false
    private val drainBound = Runnable { if (state == State.WAITING_DRAIN) startClose() }
    private val closeBound = Runnable { finish() }

    /** True when a drain may be sent to this engine. */
    fun acceptsDrain(): Boolean = state == State.RUNNING

    /** A drain command was sent; its reply is pending. */
    fun drainSent() {
        drainPending = true
    }

    /** The pending drain was answered (or abandoned). */
    fun drainAnswered() {
        drainPending = false
        if (state == State.WAITING_DRAIN) startClose()
    }

    /** Starts the shutdown (idempotent). */
    fun request() {
        if (state != State.RUNNING) return
        if (drainPending) {
            state = State.WAITING_DRAIN
            timers.postDelayed(drainBound, drainWaitMs)
        } else {
            startClose()
        }
    }

    /** Destroys at once: the engine failed before its Dart side could run. */
    fun abort() = finish()

    private fun startClose() {
        timers.cancel(drainBound)
        state = State.CLOSING
        timers.postDelayed(closeBound, closeWaitMs)
        try {
            sendClose { finish() }
        } catch (_: Exception) {
            finish()
        }
    }

    private fun finish() {
        if (state == State.GONE) return
        timers.cancel(drainBound)
        timers.cancel(closeBound)
        state = State.GONE
        teardown()
    }

    companion object {
        /** Covers one cycle's own budget (kCycleBudget, 50 s; 1-3 s on the emulators). */
        const val DRAIN_WAIT_MS = 55_000L

        /** Closing the database is milliseconds; this only guards a hung isolate. */
        const val CLOSE_WAIT_MS = 5_000L
    }
}
