package app.zaghlol.spike.sms

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DrainLoopTest {
    private class Env(
        var pending: Int,
        var ui: Boolean = false,
        val outcomes: ArrayDeque<CycleOutcome> = ArrayDeque(),
        val drainPerCycle: Int = Int.MAX_VALUE,
    ) : DrainEnvironment {
        var now = 0L
        var cycles = 0
        var notified = 0
        val timeouts = ArrayList<Long>()
        var onPause: (Env) -> Unit = {}

        override fun pendingCount() = pending
        override fun uiAttached() = ui
        override fun notifyUi(pending: Int) {
            notified++
        }

        override suspend fun runHeadlessCycle(timeoutMs: Long): CycleOutcome {
            cycles++
            timeouts += timeoutMs
            now += 100
            val o = outcomes.removeFirstOrNull() ?: CycleOutcome.OK
            if (o == CycleOutcome.OK) pending = maxOf(0, pending - drainPerCycle)
            return o
        }

        override suspend fun pause(ms: Long) {
            now += ms
            onPause(this)
        }

        override fun nowMs() = now
    }

    @Test
    fun emptySpoolIsSuccessWithoutAnEngine() = runBlocking {
        val env = Env(pending = 0)
        assertTrue(DrainLoop(env).run())
        assertEquals(0, env.cycles)
    }

    @Test
    fun drainsUntilEmpty() = runBlocking {
        val env = Env(pending = 5, drainPerCycle = 2)
        assertTrue(DrainLoop(env).run())
        assertEquals(3, env.cycles)
        assertTrue(env.timeouts.all { it <= DrainLoop.BUDGET_MS })
    }

    @Test
    fun timeoutDeferredAndRetryAreRetry() = runBlocking {
        for (o in listOf(CycleOutcome.TIMEOUT, CycleOutcome.DEFERRED, CycleOutcome.RETRY)) {
            assertFalse(DrainLoop(Env(pending = 1, outcomes = ArrayDeque(listOf(o)))).run())
        }
    }

    @Test
    fun noDatabaseIsSuccessAndKeepsTheSpool() = runBlocking {
        val env = Env(pending = 1, outcomes = ArrayDeque(listOf(CycleOutcome.NO_DATABASE)))
        assertTrue(DrainLoop(env).run())
        assertEquals(1, env.pending)
    }

    @Test
    fun uiAttachedNeverStartsAnEngineAndNotifiesOnce() = runBlocking {
        val env = Env(pending = 2, ui = true)
        env.onPause = { if (it.now >= 1_000) it.pending = 0 }
        assertTrue(DrainLoop(env).run())
        assertEquals(0, env.cycles)
        assertEquals(1, env.notified)
    }

    @Test
    fun stillPendingAtTheDeadlineIsRetry() = runBlocking {
        val env = Env(pending = 2, ui = true)
        assertFalse(DrainLoop(env, budgetMs = 2_000).run())
        assertEquals(0, env.cycles)
    }

    @Test
    fun uiTakeoverAfterAnAbandonedCycleLetsTheUiDrain() = runBlocking {
        val env = Env(pending = 1, outcomes = ArrayDeque(listOf(CycleOutcome.RETRY)))
        env.onPause = { it.pending = 0 }
        // The UI attaches while the headless cycle runs (it destroys the engine).
        val loop = DrainLoop(object : DrainEnvironment by env {
            override suspend fun runHeadlessCycle(timeoutMs: Long): CycleOutcome {
                val o = env.runHeadlessCycle(timeoutMs)
                env.ui = true
                return o
            }
        })
        assertTrue(loop.run())
        assertEquals(1, env.notified)
    }

    @Test
    fun outcomeParsingIsClosed() {
        assertEquals(CycleOutcome.OK, CycleOutcome.parse("OK"))
        assertEquals(CycleOutcome.RETRY, CycleOutcome.parse("ok"))
        assertEquals(CycleOutcome.RETRY, CycleOutcome.parse(null))
        assertEquals(CycleOutcome.RETRY, CycleOutcome.parse(42))
    }
}
