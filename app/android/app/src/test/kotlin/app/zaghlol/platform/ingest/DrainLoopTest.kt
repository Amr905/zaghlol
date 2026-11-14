package app.zaghlol.platform.ingest

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** T-041 design note sections 3-4: one test per row of the outcome table. */
class DrainLoopTest {
    private class Env(
        var pending: Int?,
        var ui: Boolean = false,
        val reports: ArrayDeque<CycleReport> = ArrayDeque(),
        val drainPerCycle: Int = Int.MAX_VALUE,
    ) : DrainEnvironment {
        var now = 0L
        var cycles = 0
        var notified = 0
        val timeouts = ArrayList<Long>()
        var onPause: (Env) -> Unit = {}
        var onCycle: (Env) -> Unit = {}

        override fun pendingCount() = pending
        override fun uiAttached() = ui
        override fun notifyUi() {
            notified++
        }

        override suspend fun runHeadlessCycle(timeoutMs: Long): CycleReport {
            cycles++
            timeouts += timeoutMs
            now += 100
            onCycle(this)
            val r = reports.removeFirstOrNull()
            if (r != null) return r
            val p = pending ?: 0
            val n = minOf(p, drainPerCycle)
            pending = p - n
            return CycleReport(CycleOutcome.OK, drained = n.toLong())
        }

        override suspend fun pause(ms: Long) {
            now += ms
            onPause(this)
        }

        override fun nowMs() = now
    }

    private fun run(env: Env) = runBlocking { DrainLoop(env).run() }

    /** FU-194: a restore holds the drain; the retry work drains after it. */
    @Test
    fun heldIsARetry() {
        val env = Env(pending = 2, reports = ArrayDeque(listOf(CycleReport(CycleOutcome.HELD))))
        assertEquals(RunResult.RETRY, run(env))
        assertEquals(1, env.cycles)
        assertEquals(2, env.pending)
    }

    @Test
    fun emptySpoolEndsEmptyWithoutAnEngine() {
        val env = Env(pending = 0)
        assertEquals(RunResult.EMPTY, run(env))
        assertEquals(0, env.cycles)
    }

    @Test
    fun okAndEmptyEndsEmpty() {
        val env = Env(pending = 5, drainPerCycle = 2)
        assertEquals(RunResult.EMPTY, run(env))
        assertEquals(3, env.cycles)
        assertTrue(env.timeouts.all { it <= DrainLoop.BUDGET_MS })
    }

    @Test
    fun okWithOnlyStuckEntriesEndsWithoutRetry() {
        val env = Env(pending = 2, reports = ArrayDeque(listOf(CycleReport(CycleOutcome.OK, drained = 2, stuck = 2, code = "INGEST_MSG_UNSTORABLE"))))
        assertEquals(RunResult.NO_RETRY, run(env))
        assertEquals(1, env.cycles)
    }

    @Test
    fun okWithHeldEntriesLoopsOnAndEndsEmpty() {
        val env = Env(pending = 1)
        env.reports += CycleReport(CycleOutcome.OK, drained = 1, held = 1)
        env.onCycle = { it.pending = 0 } // held entries are not pending
        assertEquals(RunResult.EMPTY, run(env))
    }

    @Test
    fun noDatabaseEndsWithoutRetry() {
        val env = Env(pending = 3, reports = ArrayDeque(listOf(CycleReport(CycleOutcome.NO_DATABASE))))
        assertEquals(RunResult.NO_RETRY, run(env))
        assertEquals(3, env.pending)
    }

    @Test
    fun deferredEndsWithoutRetry() {
        val env = Env(pending = 3, reports = ArrayDeque(listOf(CycleReport(CycleOutcome.DEFERRED, code = "DB_MIGRATION_PENDING"))))
        assertEquals(RunResult.NO_RETRY, run(env))
    }

    @Test
    fun retryOutcomeEndsWithRetry() {
        val env = Env(pending = 3, reports = ArrayDeque(listOf(CycleReport(CycleOutcome.RETRY, code = "DB_WRITE_FAILED"))))
        assertEquals(RunResult.RETRY, run(env))
        assertEquals(1, env.cycles)
    }

    @Test
    fun timeoutEndsWithRetry() {
        val env = Env(pending = 3, reports = ArrayDeque(listOf(CycleReport(CycleOutcome.TIMEOUT))))
        assertEquals(RunResult.RETRY, run(env))
    }

    /** Claim held elsewhere or entries unreadable now: nothing handed out → retry work. */
    @Test
    fun okWithNothingDrainedWhilePendingAndNoUiEndsWithRetry() {
        val env = Env(pending = 3, reports = ArrayDeque(listOf(CycleReport(CycleOutcome.OK, drained = 0))))
        assertEquals(RunResult.RETRY, run(env))
        assertEquals(1, env.cycles)
    }

    @Test
    fun anUnlistableSpoolEndsWithRetry() {
        assertEquals(RunResult.RETRY, run(Env(pending = null)))
    }

    @Test
    fun outOfTimeWithoutUiEndsWithRetry() {
        val env = Env(pending = 100, drainPerCycle = 1)
        env.onCycle = { it.now += 10_000 }
        assertEquals(RunResult.RETRY, run(env))
        assertTrue(env.cycles in 5..7)
    }

    @Test
    fun uiAttachedNotifiesOnceAndWaitsUntilEmptyWithoutAnEngine() {
        val env = Env(pending = 4, ui = true)
        var polls = 0
        env.onPause = { if (++polls == 3) it.pending = 0 }
        assertEquals(RunResult.EMPTY, run(env))
        assertEquals(0, env.cycles)
        assertEquals(1, env.notified)
    }

    @Test
    fun uiAttachedOutOfTimeEndsWithoutRetry() {
        val env = Env(pending = 4, ui = true)
        assertEquals(RunResult.NO_RETRY, run(env))
        assertEquals(0, env.cycles)
    }

    /** F3: the engine refused to start because a UI engine attached after the loop's check. */
    @Test
    fun uiTookOverIsHandledLikeTheUiBranch() {
        val env = Env(pending = 2, reports = ArrayDeque(listOf(CycleReport(CycleOutcome.UI_TOOK_OVER))))
        env.onCycle = { it.ui = true }
        env.onPause = { it.pending = 0 }
        assertEquals(RunResult.EMPTY, run(env))
        assertEquals(1, env.cycles)
        assertEquals(1, env.notified)
    }

    @Test
    fun aRetryWhileTheUiAttachedLetsTheUiDrain() {
        val env = Env(pending = 2, reports = ArrayDeque(listOf(CycleReport(CycleOutcome.RETRY))))
        env.onCycle = { it.ui = true }
        env.onPause = { it.pending = 0 }
        assertEquals(RunResult.EMPTY, run(env))
    }
}
