package app.zaghlol.platform.ingest

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.Executors

/** A single-thread "main thread" with manually advanced timers. */
internal class FakeMain : MainThread {
    val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "fake-main").apply { isDaemon = true } }
    override val dispatcher: CoroutineDispatcher = executor.asCoroutineDispatcher()
    private val delayed = ArrayList<Pair<Long, Runnable>>()
    var now = 0L

    override fun post(task: Runnable) = executor.execute(task)

    override fun postDelayed(task: Runnable, delayMs: Long) {
        synchronized(delayed) { delayed += (now + delayMs) to task }
    }

    override fun cancel(task: Runnable) {
        synchronized(delayed) { delayed.removeAll { it.second === task } }
    }

    /** Runs [block] on the main thread and waits for it. */
    fun <T> onMain(block: () -> T): T = executor.submit<T> { block() }.get()

    /** Advances time and runs due tasks on the main thread. */
    fun advance(ms: Long) {
        val target = now + ms
        while (true) {
            val due = synchronized(delayed) { delayed.filter { it.first <= target }.minByOrNull { it.first }?.also { delayed.remove(it) } } ?: break
            now = due.first
            onMain { due.second.run() }
        }
        now = target
    }

    /** Lets posted work run. */
    fun flush() = onMain { }

    fun shutdown() {
        executor.shutdownNow()
    }
}

internal class FakeHandle(private val main: FakeMain) : HeadlessHandle {
    val drains = ArrayList<(CycleReport) -> Unit>()
    val closes = ArrayList<() -> Unit>()
    var destroyed = 0
    val log = ArrayList<String>()

    override fun drain(onReply: (CycleReport) -> Unit) {
        log += "drain"
        drains += onReply
    }

    override fun close(onReply: () -> Unit) {
        log += "close"
        closes += onReply
    }

    override fun destroy() {
        log += "destroy"
        destroyed++
    }

    /** Dart answers the oldest drain (on the main thread). */
    fun answerDrain(report: CycleReport = CycleReport(CycleOutcome.OK, drained = 1)) = main.onMain { drains.removeAt(0)(report) }

    fun answerClose() = main.onMain { closes.removeAt(0)() }
}

internal class FakeStarter(private val main: FakeMain, var readyResult: Boolean? = true) : HeadlessStarter {
    val handles = ArrayList<FakeHandle>()
    var pendingReady: ((Boolean) -> Unit)? = null

    override fun start(onReady: (Boolean) -> Unit): HeadlessHandle {
        val h = FakeHandle(main)
        handles += h
        val r = readyResult
        if (r != null) main.post { onReady(r) } else pendingReady = onReady
        return h
    }
}

class HeadlessEngineTest {
    private val main = FakeMain()
    private val starter = FakeStarter(main)
    private var gone = 0
    private val engine = HeadlessEngine(starter, main, onGone = { gone++ })

    @After
    fun stop() = main.shutdown()

    /** Waits (real time, bounded) until [cond] holds on the main thread. */
    private fun await(cond: () -> Boolean) {
        repeat(200) {
            if (main.onMain(cond)) return
            Thread.sleep(5)
        }
        throw AssertionError("condition not reached")
    }

    @Test
    fun aCycleStartsOneEngineAndALaterCycleReusesIt() = runBlocking {
        val first = async(Dispatchers.Default) { engine.runCycle(10_000) { false } }
        await { starter.handles.size == 1 && starter.handles[0].drains.size == 1 }
        starter.handles[0].answerDrain(CycleReport(CycleOutcome.OK, drained = 3))
        assertEquals(3L, first.await().drained)
        assertFalse(engine.isIdle())
        val second = async(Dispatchers.Default) { engine.runCycle(10_000) { false } }
        await { starter.handles[0].drains.size == 1 }
        starter.handles[0].answerDrain()
        assertEquals(CycleOutcome.OK, second.await().outcome)
        assertEquals("reused", 1, starter.handles.size)
    }

    /** F3: the UI engine attached between the drain loop's check and the start. */
    @Test
    fun aUiEngineSeenOnTheMainThreadPreventsTheStart() = runBlocking {
        val report = engine.runCycle(10_000) { true }
        assertEquals(CycleOutcome.UI_TOOK_OVER, report.outcome)
        assertEquals("no engine started", 0, starter.handles.size)
        assertTrue(engine.isIdle())
    }

    @Test
    fun theUiCheckRunsOnTheMainThread() = runBlocking {
        var thread: String? = null
        engine.runCycle(10_000) { thread = Thread.currentThread().name; true }
        // With -ea (Gradle) kotlinx.coroutines debug mode appends " @coroutine#n".
        assertEquals("fake-main", thread?.substringBefore(" @coroutine#"))
    }

    /** UI attach mid-drain: close at once, the drain reply first, destroy after close, exactly once. */
    @Test
    fun shutdownMidDrainSendsCloseAtOnceAndDestroysAfterBothReplies() = runBlocking {
        val cycle = async(Dispatchers.Default) { engine.runCycle(10_000) { false } }
        await { starter.handles.size == 1 && starter.handles[0].drains.size == 1 }
        val h = starter.handles[0]
        main.onMain { engine.shutdown() }
        assertEquals(listOf("drain", "close"), h.log)
        h.answerDrain(CycleReport(CycleOutcome.OK, drained = 20)) // Dart: the current batch, then stop
        assertEquals(20L, cycle.await().drained)
        assertEquals(0, h.destroyed)
        h.answerClose()
        assertEquals(listOf("drain", "close", "destroy"), h.log)
        assertTrue(engine.isIdle())
        assertEquals(1, gone)
        main.onMain { engine.shutdown() } // idempotent once gone
        assertEquals(1, h.destroyed)
    }

    @Test
    fun aShuttingDownEngineIsNeverReusedTheNextCycleStartsAFreshOne() = runBlocking {
        val first = async(Dispatchers.Default) { engine.runCycle(10_000) { false } }
        await { starter.handles.size == 1 && starter.handles[0].drains.size == 1 }
        starter.handles[0].answerDrain()
        first.await()
        main.onMain { engine.shutdown() }
        val second = async(Dispatchers.Default) { engine.runCycle(10_000) { false } }
        delay(50)
        assertEquals("waits for the old engine to be gone", 1, starter.handles.size)
        starter.handles[0].answerClose()
        await { starter.handles.size == 2 && starter.handles[1].drains.size == 1 }
        starter.handles[1].answerDrain()
        assertEquals(CycleOutcome.OK, second.await().outcome)
        assertEquals(1, starter.handles[0].destroyed)
    }

    @Test
    fun anEngineThatFailsToStartIsATimeoutAndIsDestroyed() = runBlocking {
        starter.readyResult = false
        assertEquals(CycleOutcome.TIMEOUT, engine.runCycle(10_000) { false }.outcome)
        main.flush()
        assertEquals(1, starter.handles[0].destroyed)
        assertTrue(engine.isIdle())
    }

    @Test
    fun aStarterThatThrowsIsATimeout() = runBlocking {
        val throwing = HeadlessEngine({ throw IllegalStateException("no loader") }, main)
        assertEquals(CycleOutcome.TIMEOUT, throwing.runCycle(10_000) { false }.outcome)
        assertTrue(throwing.isIdle())
    }

    @Test
    fun noAnswerInTimeIsATimeoutAndALateReplyIsHarmless() = runBlocking {
        val r = engine.runCycle(200) { false }
        assertEquals(CycleOutcome.TIMEOUT, r.outcome)
        val h = starter.handles[0]
        h.answerDrain()
        main.onMain { engine.shutdown() }
        h.answerClose()
        assertEquals(1, h.destroyed)
    }

    @Test
    fun lingerShutsDownAfterTheDelay() = runBlocking {
        val c = async(Dispatchers.Default) { engine.runCycle(10_000) { false } }
        await { starter.handles.size == 1 && starter.handles[0].drains.size == 1 }
        starter.handles[0].answerDrain()
        c.await()
        main.onMain { engine.scheduleShutdown(HeadlessEngine.LINGER_MS) }
        main.advance(HeadlessEngine.LINGER_MS - 1)
        assertEquals(listOf("drain"), starter.handles[0].log)
        main.advance(1)
        assertEquals(listOf("drain", "close"), starter.handles[0].log)
        assertEquals(10_000L, HeadlessEngine.LINGER_MS)
    }

    @Test
    fun aNewCycleCancelsThePendingLinger() = runBlocking {
        val c = async(Dispatchers.Default) { engine.runCycle(10_000) { false } }
        await { starter.handles.size == 1 && starter.handles[0].drains.size == 1 }
        starter.handles[0].answerDrain()
        c.await()
        main.onMain { engine.scheduleShutdown(HeadlessEngine.LINGER_MS) }
        val again = async(Dispatchers.Default) { engine.runCycle(10_000) { false } }
        await { starter.handles[0].drains.size == 1 }
        main.advance(HeadlessEngine.LINGER_MS)
        assertFalse(starter.handles[0].log.contains("close"))
        starter.handles[0].answerDrain()
        assertEquals(CycleOutcome.OK, again.await().outcome)
    }

    @Test
    fun shuttingDownWhileTheEngineLoadsAnswersTheCycleAndDestroys() = runBlocking {
        starter.readyResult = null // Dart never reports ready
        val c = async(Dispatchers.Default) { engine.runCycle(10_000) { false } }
        await { starter.handles.size == 1 }
        main.onMain { engine.shutdown() }
        starter.handles[0].answerClose()
        assertEquals(CycleOutcome.TIMEOUT, c.await().outcome)
        assertEquals(1, starter.handles[0].destroyed)
    }
}
