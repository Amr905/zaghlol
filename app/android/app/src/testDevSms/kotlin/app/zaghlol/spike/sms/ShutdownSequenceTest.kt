package app.zaghlol.spike.sms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Review F1: the headless engine is destroyed only after the drain reply and Dart's `close`. */
class ShutdownSequenceTest {
    private class ManualTimers : MainTimers {
        var now = 0L
        private val tasks = ArrayList<Pair<Long, Runnable>>()

        override fun postDelayed(task: Runnable, delayMs: Long) {
            tasks += (now + delayMs) to task
        }

        override fun cancel(task: Runnable) {
            tasks.removeAll { it.second === task }
        }

        fun advance(ms: Long) {
            now += ms
            while (true) {
                val due = tasks.filter { it.first <= now }.minByOrNull { it.first } ?: return
                tasks.remove(due)
                due.second.run()
            }
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
        assertEquals("bounds cancelled", 0, h.timers.pending())
    }

    @Test
    fun uiEngineAttachesMidDrainNothingIsClosedOrDestroyedBeforeTheDrainReply() {
        val h = Harness()
        h.seq.drainSent()
        h.seq.request() // SpikeEngineHook.attach → HeadlessEngine.shutdown()
        h.seq.request() // a second request (onTrimMemory, linger) changes nothing
        assertEquals(ShutdownSequence.State.WAITING_DRAIN, h.seq.state)
        h.timers.advance(999)
        assertTrue("no close or destroy while the drain runs", h.events.isEmpty())
        h.seq.drainAnswered()
        assertEquals(listOf("close"), h.events)
        h.closeReply!!()
        assertEquals(listOf("close", "destroy"), h.events)
    }

    @Test
    fun aDrainThatNeverAnswersIsWaitedForUpToTheBoundThenClosed() {
        val h = Harness()
        h.seq.drainSent()
        h.seq.request()
        h.timers.advance(1_000)
        assertEquals(listOf("close"), h.events)
        h.timers.advance(199)
        assertEquals(listOf("close"), h.events)
        h.timers.advance(1)
        assertEquals("close bound reached", listOf("close", "destroy"), h.events)
        h.closeReply!!() // late reply: destroyed exactly once
        h.seq.drainAnswered()
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
        assertTrue(ShutdownSequence.CLOSE_WAIT_MS in 1_000..10_000)
    }

    @Test
    fun onlyTheShutdownSequenceDestroysTheHeadlessEngine() {
        val dir = File("src/devSms/kotlin/app/zaghlol/spike/sms")
        val engine = File(dir, "HeadlessEngine.kt").readText()
        assertEquals("one FlutterEngine.destroy() call", 1, Regex("\\.destroy\\(\\)").findAll(engine).count())
        val teardown = engine.substringAfter("private fun teardown()").substringBefore("private fun ensureEngine")
        assertTrue(teardown.contains("e.destroy()"))
        assertTrue(engine.contains("ShutdownSequence(timers, ::sendClose, ::teardown)"))
        assertFalse("no public destroy", engine.contains("fun destroy("))
        val hook = File(dir, "SpikeEngineHook.kt").readText()
        assertTrue(hook.contains("rt.headless.shutdown()"))
    }
}
