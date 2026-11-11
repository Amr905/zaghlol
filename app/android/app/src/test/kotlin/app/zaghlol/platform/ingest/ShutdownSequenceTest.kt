package app.zaghlol.platform.ingest

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** T-008 review F1, T-041 section 5: `close` at once, destroy after the close and drain replies, bounded. */
class ShutdownSequenceTest {
    internal class ManualTimers : MainTimers {
        var now = 0L
        private val tasks = ArrayList<Pair<Long, Runnable>>()

        override fun postDelayed(task: Runnable, delayMs: Long) {
            tasks += (now + delayMs) to task
        }

        override fun cancel(task: Runnable) {
            tasks.removeAll { it.second === task }
        }

        fun advance(ms: Long) {
            val target = now + ms
            while (true) {
                val due = tasks.filter { it.first <= target }.minByOrNull { it.first } ?: break
                tasks.remove(due)
                now = due.first
                due.second.run()
            }
            now = target
        }

        fun pending() = tasks.size
    }

    private class Harness {
        val timers = ManualTimers()
        val events = ArrayList<String>()
        var closeReply: (() -> Unit)? = null
        val seq = ShutdownSequence(
            timers,
            sendClose = { onReply ->
                events += "close"
                closeReply = onReply
            },
            teardown = { events += "destroy" },
            drainWaitMs = 1_000,
            closeWaitMs = 200,
        )
    }

    @Test
    fun idleEngineSendsCloseAndIsDestroyedOnlyAfterTheReply() {
        val h = Harness()
        h.seq.request()
        assertEquals(listOf("close"), h.events)
        assertFalse(h.seq.acceptsDrain())
        h.timers.advance(100)
        assertEquals("not before the reply", listOf("close"), h.events)
        h.closeReply!!()
        assertEquals(listOf("close", "destroy"), h.events)
        assertEquals(ShutdownSequence.State.GONE, h.seq.state)
        assertEquals("bound cancelled", 0, h.timers.pending())
    }

    /** T-041: the UI engine attaches mid-drain → `close` goes out at once (Dart stops after the batch). */
    @Test
    fun closeIsSentAtOnceWhileADrainIsPending() {
        val h = Harness()
        h.seq.drainSent()
        h.seq.request() // CaptureRuntime.attachUi → HeadlessEngine.shutdown()
        h.seq.request() // a second request (onTrimMemory, linger) changes nothing
        assertEquals(ShutdownSequence.State.CLOSING, h.seq.state)
        assertEquals("close sent before the drain reply", listOf("close"), h.events)
    }

    /** Dart answers the drain first, then close: destroy only after both. */
    @Test
    fun destroyWaitsForTheDrainReplyAndTheCloseReplyInDartOrder() {
        val h = Harness()
        h.seq.drainSent()
        h.seq.request()
        h.seq.drainAnswered()
        assertEquals("drain answered, close not yet", listOf("close"), h.events)
        h.closeReply!!()
        assertEquals(listOf("close", "destroy"), h.events)
    }

    @Test
    fun aCloseReplyBeforeTheDrainReplyStillWaitsForTheDrain() {
        val h = Harness()
        h.seq.drainSent()
        h.seq.request()
        h.closeReply!!()
        assertEquals(listOf("close"), h.events)
        h.seq.drainAnswered()
        assertEquals(listOf("close", "destroy"), h.events)
    }

    @Test
    fun withADrainPendingTheBoundIsDrainPlusClose() {
        val h = Harness()
        h.seq.drainSent()
        h.seq.request()
        h.timers.advance(1_199)
        assertEquals(listOf("close"), h.events)
        h.timers.advance(1)
        assertEquals("bound reached (hung isolate)", listOf("close", "destroy"), h.events)
        h.closeReply!!() // late replies: destroyed exactly once
        h.seq.drainAnswered()
        assertEquals(listOf("close", "destroy"), h.events)
    }

    @Test
    fun withoutADrainTheBoundIsCloseOnly() {
        val h = Harness()
        h.seq.request()
        h.timers.advance(199)
        assertEquals(listOf("close"), h.events)
        h.timers.advance(1)
        assertEquals(listOf("close", "destroy"), h.events)
    }

    @Test
    fun aFailingCloseSendStillDestroysOnce() {
        val timers = ManualTimers()
        var destroyed = 0
        val seq = ShutdownSequence(timers, { throw IllegalStateException("channel gone") }, { destroyed++ })
        seq.request()
        timers.advance(ShutdownSequence.CLOSE_WAIT_MS)
        assertEquals(1, destroyed)
    }

    @Test
    fun abortDestroysAtOnceForAnEngineThatNeverStarted() {
        val h = Harness()
        h.seq.abort()
        h.seq.request()
        assertEquals(listOf("destroy"), h.events)
    }

    @Test
    fun boundsCoverACycleAndAHungIsolate() {
        // kCycleBudget is 50 s (ingestion_config.dart); the drain wait must exceed it.
        val config = File("../../lib/ingestion/ingestion_config.dart").readText()
        val budget = Regex("kCycleBudget = Duration\\(seconds: (\\d+)\\)").find(config)!!.groupValues[1].toLong()
        assertTrue(ShutdownSequence.DRAIN_WAIT_MS > budget * 1_000)
        assertEquals(55_000L, ShutdownSequence.DRAIN_WAIT_MS)
        assertEquals(5_000L, ShutdownSequence.CLOSE_WAIT_MS)
    }
}
