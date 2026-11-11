package app.zaghlol.platform.ingest

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** T-041 design note section 3: what a run does with its result. */
class IngestRunTest {
    private class Queue : IngestWorkQueue {
        val log = ArrayList<String>()
        var fail = false

        override fun enqueue() {
            log += "live"
        }

        override fun enqueueRetry(attempt: Int, fromRetryRun: Boolean) {
            if (fail) throw IllegalStateException("wm")
            log += "retry$attempt${if (fromRetryRun) "/append" else "/keep"}"
        }

        override fun cancelRetry() {
            if (fail) throw IllegalStateException("wm")
            log += "cancel"
        }
    }

    private class LoopEnv(val result: () -> RunResult) : DrainEnvironment {
        override fun pendingCount(): Int? = when (result()) {
            RunResult.EMPTY -> 0
            RunResult.RETRY -> null
            RunResult.NO_RETRY -> 1
        }
        override fun uiAttached() = false
        override fun notifyUi() = Unit
        override suspend fun runHeadlessCycle(timeoutMs: Long) = CycleReport(CycleOutcome.NO_DATABASE)
        override suspend fun pause(ms: Long) = Unit
        override fun nowMs() = 0L
    }

    private val queue = Queue()
    private val after = ArrayList<Boolean>()

    private fun run(result: RunResult, attempt: Int, mutex: Mutex = Mutex()) = runBlocking {
        IngestRun(mutex, queue, { DrainLoop(LoopEnv { result }) }, { after += it }).run(attempt)
    }

    @Test
    fun liveRunThatEmptiesTheSpoolCancelsTheRetryWork() {
        assertEquals(RunResult.EMPTY, run(RunResult.EMPTY, 0))
        assertEquals(listOf("cancel"), queue.log)
        assertEquals(listOf(false), after)
    }

    @Test
    fun retryRunThatEmptiesTheSpoolDoesNotCancelItself() {
        run(RunResult.EMPTY, 3)
        assertEquals(emptyList<String>(), queue.log)
    }

    @Test
    fun liveRunThatFailsEnqueuesRetryOneWithKeep() {
        assertEquals(RunResult.RETRY, run(RunResult.RETRY, 0))
        assertEquals(listOf("retry1/keep"), queue.log)
    }

    @Test
    fun retryRunNEnqueuesNPlusOneAppended() {
        run(RunResult.RETRY, 4)
        assertEquals(listOf("retry5/append"), queue.log)
    }

    @Test
    fun theRetryChainStopsAfterAttemptEight() {
        run(RunResult.RETRY, 7)
        run(RunResult.RETRY, 8)
        assertEquals(listOf("retry8/append"), queue.log)
    }

    @Test
    fun noRetryResultsScheduleNothing() {
        run(RunResult.NO_RETRY, 0)
        run(RunResult.NO_RETRY, 2)
        assertEquals(emptyList<String>(), queue.log)
    }

    @Test
    fun aLoopThatThrowsCountsAsRetry() = runBlocking {
        val r = IngestRun(Mutex(), queue, { throw IllegalStateException("boom") }, { after += it }).run(0)
        assertEquals(RunResult.RETRY, r)
        assertEquals(listOf("retry1/keep"), queue.log)
    }

    @Test
    fun workManagerFailuresAreSwallowed() {
        queue.fail = true
        assertEquals(RunResult.RETRY, run(RunResult.RETRY, 0))
        assertEquals(RunResult.EMPTY, run(RunResult.EMPTY, 0))
        assertEquals(listOf(false, false), after)
    }

    /** A live and a retry run never interleave cycles. */
    @Test
    fun runsAreSerialisedByTheProcessWideMutex() = runBlocking {
        val mutex = Mutex()
        val gate = CompletableDeferred<Unit>()
        var active = 0
        var maxActive = 0
        val env = object : DrainEnvironment {
            var pending = 1
            override fun pendingCount() = pending
            override fun uiAttached() = false
            override fun notifyUi() = Unit
            override suspend fun runHeadlessCycle(timeoutMs: Long): CycleReport {
                active++
                maxActive = maxOf(maxActive, active)
                gate.await()
                delay(5)
                active--
                pending = 0
                return CycleReport(CycleOutcome.OK, drained = 1)
            }
            override suspend fun pause(ms: Long) = Unit
            override fun nowMs() = 0L
        }
        val a = async { IngestRun(mutex, queue, { DrainLoop(env) }, {}).run(0) }
        val b = async { IngestRun(mutex, queue, { env.pending = 1; DrainLoop(env) }, {}).run(1) }
        delay(20)
        gate.complete(Unit)
        a.await()
        b.await()
        assertEquals(1, maxActive)
    }

    /** A stopped work (quota, 10 min, cancel): afterRun still runs, flagged stopped (→ shutdown, never destroy). */
    @Test
    fun aStoppedRunStillSchedulesTheShutdown() = runBlocking {
        val started = CompletableDeferred<Unit>()
        val env = object : DrainEnvironment {
            override fun pendingCount() = 1
            override fun uiAttached() = false
            override fun notifyUi() = Unit
            override suspend fun runHeadlessCycle(timeoutMs: Long): CycleReport {
                started.complete(Unit)
                delay(60_000)
                return CycleReport(CycleOutcome.OK)
            }
            override suspend fun pause(ms: Long) = Unit
            override fun nowMs() = 0L
        }
        val job = launch { IngestRun(Mutex(), queue, { DrainLoop(env) }, { after += it }).run(0) }
        started.await()
        job.cancelAndJoin()
        assertEquals(listOf(true), after)
        assertTrue("no retry enqueued for a stopped run (WorkManager reschedules it)", queue.log.isEmpty())
    }
}
