package app.zaghlol.platform.capture

import app.zaghlol.platform.guard.AndroidGuardChannel
import app.zaghlol.platform.guard.GuardFixtures
import app.zaghlol.platform.guard.GuardRuntime
import app.zaghlol.platform.guard.GuardUserConfigStore
import app.zaghlol.platform.guard.SoftwareGuardUserCipher
import app.zaghlol.platform.spool.CaptureStatusStore
import app.zaghlol.platform.spool.SoftwareSpoolCipher
import app.zaghlol.platform.spool.SpoolLimits
import app.zaghlol.platform.spool.SpoolStore
import app.zaghlol.platform.spool.put
import app.zaghlol.platform.spool.storeIn
import app.zaghlol.platform.spool.tempDir
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** T-043 design note sections 3, 6, 7 and 10: repeats, updates, refusals, rate limit, overflow. */
class NotificationIntakeTest {
    private val root = tempDir()
    private val spoolDir = File(root, "spool")
    private val status = CaptureStatusStore(File(root, "capture/status.bin"), SoftwareSpoolCipher())
    private var mono = 0L
    private val guard = GuardRuntime({ GuardFixtures.t1Base }, GuardUserConfigStore(tempDir(), SoftwareGuardUserCipher()), { mono })
        .also { it.writeUser(GuardFixtures.t1User) }
    private var enqueues = 0

    private fun intake(store: SpoolStore = storeIn(spoolDir, status = status, wall = { 5_000L })) = NotificationIntake(
        admits = guard::admitsNotificationPackage,
        intake = CaptureIntake(AndroidGuardChannel.NOTIFICATION, guard::decide, store, status, { enqueues++ }),
        recent = RecentNotifications({ mono }),
    )

    private fun nbe(text: String) = FakePosted("com.example.nbe", FakeFields(title = "NBE", text = text))

    @Test
    fun writtenIsOneEntryAndOneEnqueue() {
        val store = storeIn(spoolDir, status = status)
        val r = intake(store).process(nbe("Purchase EGP 10.00 card **1234"), 1L, 2L)!!
        assertEquals(r.written, store.pendingIds())
        assertEquals(1, enqueues)
    }

    @Test
    fun aRepeatIsOneEntryAndAnUpdateWithNewTextIsAnother() {
        val store = storeIn(spoolDir, status = status)
        val i = intake(store)
        assertEquals(1, i.process(nbe("Purchase EGP 10.00 card **1234"), 1L, 2L)!!.written.size)
        assertNull("repeat", i.process(nbe("Purchase EGP 10.00 card **1234"), 3L, 4L))
        assertEquals("update (new text)", 1, i.process(nbe("Purchase EGP 11.00 card **1234"), 5L, 6L)!!.written.size)
        assertEquals(2, store.pendingIds().size)
        assertEquals(2, enqueues)
    }

    @Test
    fun aRefusedWriteIsCountedMissedEnqueuedOnceAndNotRemembered() {
        val store = storeIn(spoolDir, status = status, limits = SpoolLimits(maxEntries = 1), wall = { 5_000L })
        store.put("old")
        val i = intake(store)
        val r = i.process(nbe("Purchase EGP 1.00 card **1234"), 1L, 2L)!!
        assertEquals(1, r.refused)
        assertEquals(1, enqueues)
        assertEquals(1L, status.read().missedNotifications)
        // Not remembered: the app's next re-post reaches the store again (and is counted again).
        assertEquals(1, i.process(nbe("Purchase EGP 1.00 card **1234"), 3L, 4L)!!.refused)
        assertEquals(2L, status.read().missedNotifications)
    }

    @Test
    fun theTwentyFirstKeepOfAMinuteIsRateLimitedAndCountedMissed() {
        val i = intake()
        repeat(20) { k -> assertEquals(1, i.process(nbe("Purchase EGP $k.00 card **1234"), 1L, 2L)!!.written.size) }
        val r = i.process(nbe("Purchase EGP 99.00 card **1234"), 1L, 2L)!!
        assertTrue(r.written.isEmpty())
        val s = status.read()
        assertEquals(1L, s.rateLimited)
        assertEquals(1L, s.missedNotifications)
        assertEquals(20, enqueues)
    }

    @Test
    fun aBurstOfSixtyFiveOverflowsTheQueueAndTheIntakeThreadCountsIt() {
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val handled = AtomicInteger()
        val missed = AtomicInteger()
        val counted = CountDownLatch(1)
        val d = NotificationDispatcher<Int>(
            onMissed = { n ->
                status.recordMissed("notification", 1L, n)
                missed.addAndGet(n)
                counted.countDown()
            },
            handler = {
                handled.incrementAndGet()
                started.countDown()
                release.await(10, TimeUnit.SECONDS)
            },
        )
        d.submit(0)
        assertTrue(started.await(10, TimeUnit.SECONDS)) // taken off the queue, blocked in the handler
        for (k in 1..NotificationDispatcher.QUEUE_CAPACITY) d.submit(k) // fills the queue exactly
        d.submit(999) // 65th beyond the one in flight: dropped, counted on the calling thread
        assertEquals("nothing reported from the submitting thread", 0, missed.get())
        release.countDown()
        assertTrue(counted.await(10, TimeUnit.SECONDS))
        assertEquals(1, missed.get())
        assertEquals(1L, status.read().missedNotifications)
    }

    @Test
    fun aThrowingHandlerDoesNotStopTheThread() {
        val done = CountDownLatch(2)
        val d = NotificationDispatcher<Int>(onMissed = {}, handler = { done.countDown(); throw IllegalStateException("x") })
        d.submit(1)
        d.submit(2)
        assertTrue(done.await(10, TimeUnit.SECONDS))
    }
}
