package app.zaghlol.platform.capture

import app.zaghlol.platform.ingest.CycleOutcome
import app.zaghlol.platform.ingest.FakeMain
import app.zaghlol.platform.ingest.FakeStarter
import app.zaghlol.platform.ingest.IngestTrace
import app.zaghlol.platform.ingest.IngestWorkQueue
import app.zaghlol.platform.spool.SoftwareSpoolCipher
import app.zaghlol.platform.spool.SpoolStore
import app.zaghlol.platform.spool.put
import app.zaghlol.platform.spool.tempDir
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** A messenger that records sends and handlers (JVM). */
internal class RecordingMessenger : BinaryMessenger {
    val sends = ArrayList<Pair<String, List<Any?>>>()
    val handlers = HashMap<String, BinaryMessenger.BinaryMessageHandler?>()

    override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)

    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
        message?.rewind()
        @Suppress("UNCHECKED_CAST")
        val decoded = (message?.let { StandardMessageCodec.INSTANCE.decodeMessage(it) } as? List<Any?>).orEmpty()
        synchronized(sends) { sends += channel to decoded }
    }

    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
        handlers[channel] = handler
    }

    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?, taskQueue: BinaryMessenger.TaskQueue?) {
        handlers[channel] = handler
    }

    override fun makeBackgroundTaskQueue(options: BinaryMessenger.TaskQueueOptions): BinaryMessenger.TaskQueue =
        object : BinaryMessenger.TaskQueue {}

    fun spoolChanged(): List<Long> = synchronized(sends) {
        sends.filter { it.first.endsWith("CaptureEventsApi.onSpoolChanged") }.map { it.second[0] as Long }
    }
}

class CaptureRuntimeTest {
    private val main = FakeMain()
    private val dir = tempDir()

    private class Queue : IngestWorkQueue {
        var live = 0
        var fail = false
        override fun enqueue() {
            if (fail) throw IllegalStateException("wm")
            live++
        }
        override fun enqueueRetry(attempt: Int, fromRetryRun: Boolean) = Unit
        override fun cancelRetry() = Unit
    }

    private val queue = Queue()
    private val starter = FakeStarter(main)

    private fun seams(version: Long = 1, software: Boolean = true) = if (software) {
        CaptureSeams(
            noBackupDir = dir, appVersion = { version }, main = main, queue = queue, device = FakeDevice(),
            guard = { throw IllegalStateException("not in JVM tests") }, headlessStarter = { starter },
            cipher = SoftwareSpoolCipher(),
            keyCreatedAtMs = { null },
            monoClockMs = { System.nanoTime() / 1_000_000 },
        )
    } else {
        // The production defaults for cipher, key date and clocks (FU-104 I-1).
        CaptureSeams(
            noBackupDir = dir, appVersion = { version }, main = main, queue = queue, device = null,
            guard = { throw IllegalStateException("not in JVM tests") }, headlessStarter = { starter },
        )
    }

    @After
    fun stop() = main.shutdown()

    /** FU-104 I-1: the production graph has a status store and the production key date / monotonic clock. */
    @Test
    fun productionGraphWiresTheStatusKeyDateAndMonotonicClock() {
        val rt = CaptureRuntime.create(seams(software = false))
        assertNotNull(rt.store.statusStore)
        assertSame(rt.status, rt.store.statusStore)
        assertSame(ProductionClocks.keyCreatedAtMs, rt.store.keyCreatedAtMsFn)
        assertSame(ProductionClocks.monoClockMs, rt.store.monoClockMsFn)
        assertEquals(File(dir, "spool"), File(dir, "spool").also { rt.store.pendingCount() })
    }

    @Test
    fun heldEntriesAreReleasedAtCreationOnlyAfterAnUpdate() {
        val first = CaptureRuntime.create(seams(version = 5))
        val id = first.store.put("a")
        assertTrue(first.store.hold(id))
        CaptureRuntime.create(seams(version = 5))
        assertEquals(1, first.store.heldCount())
        assertTrue(File(dir, "spool/held/${SpoolStore.HELD_VERSION_FILE}").exists())
        CaptureRuntime.create(seams(version = 6))
        assertEquals(0, first.store.heldCount())
        assertEquals(listOf(id), first.store.pendingIds())
    }

    @Test
    fun notificationsAreCoalescedAndReadTheCountWhenTheyRun() {
        val rt = CaptureRuntime.create(seams())
        val m = RecordingMessenger()
        main.onMain { rt.attachUi(Any(), m) }
        val gate = CountDownLatch(1)
        main.post { gate.await(5, TimeUnit.SECONDS) } // hold the main thread
        repeat(3) { rt.notifyUiIfAttached() }
        rt.store.put("a")
        rt.store.put("b")
        gate.countDown()
        main.flush()
        assertEquals("one post for three calls, count read when it ran", listOf(2L), m.spoolChanged())
        rt.notifyUiIfAttached()
        main.flush()
        assertEquals(listOf(2L, 2L), m.spoolChanged())
    }

    @Test
    fun noUiEngineNoNotification() {
        val rt = CaptureRuntime.create(seams())
        rt.notifyUiIfAttached()
        main.flush()
        assertTrue(!rt.uiAttached())
    }

    @Test
    fun afterSpoolWriteEnqueuesAndNotifiesAlsoWhenTheEnqueueFails() {
        val rt = CaptureRuntime.create(seams())
        val m = RecordingMessenger()
        main.onMain { rt.attachUi(Any(), m) }
        rt.afterSpoolWrite()
        assertEquals(1, queue.live)
        queue.fail = true
        try {
            rt.afterSpoolWrite()
            fail("enqueue failure is rethrown")
        } catch (_: IllegalStateException) {
        }
        main.flush()
        assertTrue(m.spoolChanged().isNotEmpty())
    }

    @Test
    fun attachRegistersTheHostAndStopsHeadlessStartsDetachOnlyForTheAttachedEngine() = runBlocking {
        val rt = CaptureRuntime.create(seams())
        val m = RecordingMessenger()
        val key = Any()
        main.onMain { rt.attachUi(key, m) }
        assertNotNull(m.handlers["dev.flutter.pigeon.zaghlol.AndroidCaptureHostApi.drainSpool"])
        assertNotNull(m.handlers["dev.flutter.pigeon.zaghlol.AndroidCaptureHostApi.holdSpool"])
        assertTrue(rt.uiAttached())
        assertEquals(CycleOutcome.UI_TOOK_OVER, rt.headless.runCycle(1_000, rt::uiAttached).outcome)
        assertEquals(0, starter.handles.size)
        main.onMain { rt.detachUi(Any(), m) } // another engine: ignored
        assertTrue(rt.uiAttached())
        main.onMain { rt.detachUi(key, m) }
        assertTrue(!rt.uiAttached())
        assertNull(m.handlers["dev.flutter.pigeon.zaghlol.AndroidCaptureHostApi.drainSpool"])
    }

    /** UI attach while a headless engine lingers: it is shut down (close first), never destroyed directly. */
    @Test
    fun attachingTheUiShutsALiveHeadlessEngineDown() = runBlocking {
        val rt = CaptureRuntime.create(seams())
        rt.store.put("a")
        val cycle = async(Dispatchers.Default) { rt.headless.runCycle(10_000) { false } }
        repeat(200) { if (main.onMain { starter.handles.size == 1 && starter.handles[0].drains.size == 1 }) return@repeat; Thread.sleep(5) }
        val h = starter.handles[0]
        main.onMain { rt.attachUi(Any(), RecordingMessenger()) }
        assertEquals(listOf("drain", "close"), h.log)
        h.answerDrain()
        cycle.await()
        h.answerClose()
        assertEquals(listOf("drain", "close", "destroy"), h.log)
    }

    /**
     * Design note section 3 (time limits): a worker run stopped by WorkManager
     * (quota, 10 min, cancel) shuts the headless engine down at once (close
     * first) and never destroys it before the drain and close replies; a run
     * that ends normally lets it linger.
     */
    @Test
    fun aStoppedWorkerRunShutsTheEngineDownAtOnceAndNeverDestroysIt() = runBlocking {
        val rt = CaptureRuntime.create(seams())
        rt.store.put("a")
        val run = launch(Dispatchers.Default) { rt.ingest.run(0) }
        repeat(400) { if (main.onMain { starter.handles.size == 1 && starter.handles[0].drains.size == 1 }) return@repeat; Thread.sleep(5) }
        val h = starter.handles[0]
        run.cancelAndJoin()
        main.flush()
        assertEquals("close at once, no destroy yet", listOf("drain", "close"), h.log)
        h.answerDrain()
        h.answerClose()
        main.flush()
        assertEquals(listOf("drain", "close", "destroy"), h.log)
    }

    @Test
    fun aNormalRunLetsTheEngineLinger() = runBlocking {
        val rt = CaptureRuntime.create(seams())
        rt.store.put("a")
        val run = async(Dispatchers.Default) { rt.ingest.run(0) }
        repeat(400) { if (main.onMain { starter.handles.size == 1 && starter.handles[0].drains.size == 1 }) return@repeat; Thread.sleep(5) }
        val h = starter.handles[0]
        rt.store.ack(rt.store.pendingIds().toSet())
        h.answerDrain()
        run.await()
        main.flush()
        assertEquals("lingering: no close before the linger ends", listOf("drain"), h.log)
    }

    @Test
    fun theTraceSeesEnginesAttachAndDetach() {
        val rt = CaptureRuntime.create(seams())
        val seen = ArrayList<String>()
        rt.trace = object : IngestTrace {
            override fun engineAttached(messenger: BinaryMessenger) { seen += "attach" }
            override fun engineDetached(messenger: BinaryMessenger) { seen += "detach" }
        }
        val key = Any()
        val m = RecordingMessenger()
        main.onMain { rt.attachUi(key, m) }
        main.onMain { rt.detachUi(key, m) }
        assertEquals(listOf("attach", "detach"), seen)
    }
}
