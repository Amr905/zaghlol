package app.zaghlol.spike.sms

/** The answer of one Dart drain cycle (ingestion_cycle.dart `CycleOutcome`). */
enum class CycleOutcome {
    /** Everything drained was committed and acked (or the spool was empty). */
    OK,

    /** No database file yet: the UI engine creates it; keep the spool. */
    NO_DATABASE,

    /** The database needs the UI engine (migration pending, create/wipe needed). */
    DEFERRED,

    /** Transient (DB unavailable, commit or ack failed): try again later. */
    RETRY,

    /** No answer within the time left, or the engine could not start. */
    TIMEOUT;

    companion object {
        fun parse(s: Any?): CycleOutcome = values().firstOrNull { it.name == s } ?: RETRY
    }
}

/** What [DrainLoop] needs from the platform; faked in JVM tests. */
interface DrainEnvironment {
    fun pendingCount(): Int

    fun uiAttached(): Boolean

    /** Tells the UI engine to drain (CaptureEventsApi.onSpoolChanged). */
    fun notifyUi(pending: Int)

    /** Runs one headless drain cycle, waiting at most [timeoutMs]. */
    suspend fun runHeadlessCycle(timeoutMs: Long): CycleOutcome

    suspend fun pause(ms: Long)

    fun nowMs(): Long
}

/**
 * The IngestionWorker's loop (design note section 5): drain until the spool
 * is empty or [budgetMs] has passed. Returns true for `success`, false for
 * `retry`.
 *
 * - UI engine attached: never start a second engine; notify it and wait for
 *   the spool to empty.
 * - Otherwise: headless cycles. `NO_DATABASE` ends the run as success (the
 *   spool is kept; the UI engine drains when it starts). `DEFERRED`, `RETRY`
 *   and `TIMEOUT` end it as retry (WorkManager back-off).
 * - Still non-empty at the deadline: retry.
 */
class DrainLoop(private val env: DrainEnvironment, private val budgetMs: Long = BUDGET_MS) {
    suspend fun run(): Boolean {
        val deadline = env.nowMs() + budgetMs
        var notified = false
        while (true) {
            val pending = env.pendingCount()
            if (pending == 0) return true
            val left = deadline - env.nowMs()
            if (left <= 0) return false
            if (env.uiAttached()) {
                if (!notified) {
                    env.notifyUi(pending)
                    notified = true
                }
                env.pause(minOf(UI_POLL_MS, left))
                continue
            }
            notified = false
            when (env.runHeadlessCycle(left)) {
                CycleOutcome.OK -> {
                    // Loop: messages may have arrived meanwhile. If nothing was
                    // drained (e.g. claimed by another engine), wait a little.
                    if (env.pendingCount() == pending) env.pause(minOf(UI_POLL_MS, maxOf(0, deadline - env.nowMs())))
                }
                CycleOutcome.NO_DATABASE -> return true
                CycleOutcome.DEFERRED, CycleOutcome.RETRY, CycleOutcome.TIMEOUT -> {
                    // The UI engine took over (it destroys the headless one): let it drain.
                    if (!env.uiAttached()) return false
                }
            }
        }
    }

    companion object {
        const val BUDGET_MS = 60_000L
        const val UI_POLL_MS = 250L
    }
}
