package app.zaghlol.platform.ingest

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * FU-108 security L-1 / code m-2 (owner T-040): live enqueues are coalesced
 * against a fake WorkManager unique chain (`APPEND_OR_REPLACE` semantics:
 * the first request of an idle chain is `ENQUEUED`, every later one is
 * appended `BLOCKED` behind the last).
 */
class LiveEnqueueGateTest {
    private enum class State { ENQUEUED, BLOCKED, RUNNING, SUCCEEDED }

    /** A unique work chain with WorkManager's states. */
    private class FakeChain {
        private val lock = Any()
        val runs = ArrayList<State>()
        var probeFails = false
        var probeUnknown = false
        var probes = 0

        fun enqueue() = synchronized(lock) {
            val open = runs.any { it != State.SUCCEEDED }
            runs += if (open) State.BLOCKED else State.ENQUEUED
        }

        fun waiting(): Boolean? = synchronized(lock) {
            probes++
            if (probeFails) throw IllegalStateException("wm db")
            if (probeUnknown) return null
            runs.any { it == State.ENQUEUED || it == State.BLOCKED }
        }

        fun waitingCount() = synchronized(lock) { runs.count { it == State.ENQUEUED || it == State.BLOCKED } }

        /** The head starts running (WorkManager picked it up). */
        fun start() = synchronized(lock) {
            val i = runs.indexOfFirst { it == State.ENQUEUED }
            if (i >= 0) runs[i] = State.RUNNING
        }

        /** The running run ends; the next blocked one becomes enqueued. */
        fun finish() = synchronized(lock) {
            val i = runs.indexOfFirst { it == State.RUNNING }
            if (i >= 0) runs[i] = State.SUCCEEDED
            val j = runs.indexOfFirst { it == State.BLOCKED }
            if (j >= 0) runs[j] = State.ENQUEUED
        }
    }

    private val chain = FakeChain()
    private var main = false
    private val gate = LiveEnqueueGate(chain::waiting, chain::enqueue) { main }

    @Test
    fun fiftyCallsLeaveAtMostOneWaitingRun() {
        repeat(50) { gate.enqueue() }
        assertEquals(1, chain.runs.size)
        assertEquals(1, chain.waitingCount())
    }

    @Test
    fun whileARunIsRunningOneSuccessorIsAppendedAndNoMore() {
        gate.enqueue()
        chain.start()
        repeat(50) { gate.enqueue() }
        assertEquals(listOf(State.RUNNING, State.BLOCKED), chain.runs)
        assertEquals(1, chain.waitingCount())
        chain.finish()
        chain.start()
        chain.finish()
        // Idle again: the next message enqueues a new run.
        assertTrue(gate.enqueue())
        assertEquals(1, chain.waitingCount())
    }

    @Test
    fun concurrentIntakeThreadsStillLeaveAtMostOneWaiting() {
        val pool = Executors.newFixedThreadPool(8)
        val go = CountDownLatch(1)
        val done = CountDownLatch(8)
        repeat(8) {
            pool.execute {
                go.await()
                repeat(50) { gate.enqueue() }
                done.countDown()
            }
        }
        go.countDown()
        assertTrue(done.await(10, TimeUnit.SECONDS))
        assertEquals(1, chain.waitingCount())
        pool.shutdown()
    }

    @Test
    fun anUnknownStateEnqueues() {
        gate.enqueue()
        chain.probeUnknown = true
        assertTrue(gate.enqueue())
        chain.probeUnknown = false
        chain.probeFails = true
        assertTrue(gate.enqueue())
        assertEquals(3, chain.runs.size)
    }

    @Test
    fun theMainThreadNeverProbes() {
        main = true
        gate.enqueue()
        gate.enqueue()
        assertEquals(0, chain.probes)
        assertEquals(2, chain.runs.size)
    }

    @Test
    fun aSkippedEnqueueReportsFalseAndAnEnqueueFailurePropagates() {
        assertTrue(gate.enqueue())
        assertFalse(gate.enqueue())
        val failing = LiveEnqueueGate({ false }, { throw IllegalStateException("wm") }, { false })
        try {
            failing.enqueue()
            throw AssertionError("swallowed")
        } catch (e: IllegalStateException) {
            assertEquals("wm", e.message)
        }
    }

    @Test
    fun onlyEnqueuedAndBlockedCountAsWaiting() {
        val waiting = androidx.work.WorkInfo.State.entries.filter { WorkManagerIngestScheduler.isWaiting(it) }
        assertEquals(setOf(androidx.work.WorkInfo.State.ENQUEUED, androidx.work.WorkInfo.State.BLOCKED), waiting.toSet())
    }
}
