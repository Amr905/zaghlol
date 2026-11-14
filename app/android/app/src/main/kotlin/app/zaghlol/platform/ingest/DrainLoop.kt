package app.zaghlol.platform.ingest

/** The answer of one headless drain cycle (Dart `IngestOutcome`, plus two native-only outcomes). */
enum class CycleOutcome {
    /** Everything drained was committed and acked or held (or the spool was empty, or only stuck entries are left). */
    OK,

    /** No database file yet: the UI engine creates it and drains at start; keep the spool. */
    NO_DATABASE,

    /** The database needs the UI engine (migration pending, create/wipe needed). */
    DEFERRED,

    /** Transient (DB unavailable or busy, commit or ack failed): try again later. */
    RETRY,

    /** Native only: no answer within the time left, or the engine could not start. */
    TIMEOUT,

    /**
     * Native only (T-041 design note section 4, F3): a UI engine attached
     * between the loop's check and the engine start; no engine was started.
     */
    UI_TOOK_OVER,

    /**
     * Native only (FU-194): a restore holds the drain ([DrainHold]); no engine
     * was started or reused. The entries stay in the spool for the retry work.
     */
    HELD,
}

/** One cycle's report: counts and a code only, never content. */
class CycleReport(
    val outcome: CycleOutcome,
    val drained: Long = 0,
    val inserted: Long = 0,
    val stuck: Long = 0,
    val held: Long = 0,
    val code: String? = null,
) {
    override fun toString(): String = "CycleReport($outcome, drained=$drained, stuck=$stuck, held=$held, code=$code)"

    companion object {
        fun of(r: IngestCycleReport?): CycleReport {
            if (r == null) return CycleReport(CycleOutcome.RETRY)
            val outcome = when (r.outcome) {
                IngestOutcome.OK -> CycleOutcome.OK
                IngestOutcome.NO_DATABASE -> CycleOutcome.NO_DATABASE
                IngestOutcome.DEFERRED -> CycleOutcome.DEFERRED
                IngestOutcome.RETRY -> CycleOutcome.RETRY
            }
            return CycleReport(outcome, r.drained, r.inserted, r.stuck, r.held, r.code)
        }
    }
}

/** How a worker run ends (T-041 design note section 3). */
enum class RunResult {
    /** The spool is empty: cancel the retry work. */
    EMPTY,

    /** Something is left, but retrying won't help now (no DB yet, deferred, only stuck entries, UI engine draining). */
    NO_RETRY,

    /** Enqueue the next retry work. */
    RETRY,
}

/** What [DrainLoop] needs from the platform; faked in JVM tests. */
interface DrainEnvironment {
    /** Pending entries; null when the spool can't be listed now. */
    fun pendingCount(): Int?

    fun uiAttached(): Boolean

    /** Tells the UI engine to drain (`CaptureEventsApi.onSpoolChanged`, coalesced). */
    fun notifyUi()

    /** Runs one headless drain cycle, waiting at most [timeoutMs]. Never throws. */
    suspend fun runHeadlessCycle(timeoutMs: Long): CycleReport

    suspend fun pause(ms: Long)

    fun nowMs(): Long
}

/**
 * The IngestionWorker's loop (T-041 design note sections 3-4): drain until
 * the spool is empty or [budgetMs] has passed.
 *
 * - UI engine attached: never start a second engine; notify it once and poll
 *   until the spool is empty. Out of time while it is attached: [RunResult.NO_RETRY]
 *   (it was told and drains on its own).
 * - Otherwise headless cycles, by outcome:
 *   - `OK` with the spool now empty → loop (ends [RunResult.EMPTY]);
 *   - `OK` with stuck entries → [RunResult.NO_RETRY] (they stay; the next
 *     enqueue or app open retries them);
 *   - `OK` with nothing drained while entries are pending (claim held
 *     elsewhere, entries unreadable now) → [RunResult.RETRY];
 *   - `NO_DATABASE`, `DEFERRED` → [RunResult.NO_RETRY];
 *   - `RETRY`, `TIMEOUT` → [RunResult.RETRY], unless a UI engine attached
 *     meanwhile (then the UI branch above);
 *   - `UI_TOOK_OVER` → the UI branch;
 *   - `HELD` (FU-194 restore hold) → [RunResult.RETRY], unless a UI engine is attached.
 * - Spool unlistable → [RunResult.RETRY]. Out of time without a UI engine → [RunResult.RETRY].
 */
class DrainLoop(private val env: DrainEnvironment, private val budgetMs: Long = BUDGET_MS) {
    suspend fun run(): RunResult {
        val deadline = env.nowMs() + budgetMs
        var notified = false
        while (true) {
            val pending = env.pendingCount() ?: return RunResult.RETRY
            if (pending == 0) return RunResult.EMPTY
            val left = deadline - env.nowMs()
            if (left <= 0) return if (env.uiAttached()) RunResult.NO_RETRY else RunResult.RETRY
            if (env.uiAttached()) {
                if (!notified) {
                    env.notifyUi()
                    notified = true
                }
                env.pause(minOf(UI_POLL_MS, left))
                continue
            }
            notified = false
            val report = env.runHeadlessCycle(left)
            when (report.outcome) {
                CycleOutcome.OK -> {
                    if (report.stuck > 0) return RunResult.NO_RETRY
                    if (report.drained == 0L && report.held == 0L) {
                        // Nothing handed out although entries are pending:
                        // the UI engine holds the claim (poll it), or retry later.
                        if (!env.uiAttached()) return RunResult.RETRY
                    }
                    // Loop: messages may have arrived meanwhile.
                }
                CycleOutcome.NO_DATABASE, CycleOutcome.DEFERRED -> return RunResult.NO_RETRY
                CycleOutcome.RETRY, CycleOutcome.TIMEOUT -> {
                    // The UI engine took over (it shuts the headless one down): let it drain.
                    if (!env.uiAttached()) return RunResult.RETRY
                }
                CycleOutcome.UI_TOOK_OVER -> Unit
                // FU-194: a restore is swapping the database; the retry work (back-off) drains after it.
                CycleOutcome.HELD -> if (!env.uiAttached()) return RunResult.RETRY
            }
        }
    }

    companion object {
        const val BUDGET_MS = 60_000L
        const val UI_POLL_MS = 250L
    }
}
