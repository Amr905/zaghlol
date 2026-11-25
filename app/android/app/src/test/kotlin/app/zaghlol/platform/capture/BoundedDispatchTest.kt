package app.zaghlol.platform.capture

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Ported from the T-008 spike (T-040 design note section 11): finish() exactly once. */
class BoundedDispatchTest {
    private val timer = Executors.newSingleThreadScheduledExecutor()

    private fun awaitFinish(d: BoundedDispatch, work: () -> Unit): Int = start(d, work = work).get()

    private fun start(d: BoundedDispatch, waitMs: Long = 5_000, work: () -> Unit): AtomicInteger {
        val finished = AtomicInteger()
        val latch = CountDownLatch(1)
        d.run(work) {
            finished.incrementAndGet()
            latch.countDown()
        }
        latch.await(waitMs, TimeUnit.MILLISECONDS)
        Thread.sleep(150)
        return finished
    }

    @Test
    fun finishesOnceOnSuccess() {
        assertEquals(1, awaitFinish(BoundedDispatch(Executors.newSingleThreadExecutor(), timer, 1_000)) { })
    }

    @Test
    fun finishesOnceWhenWorkThrows() {
        // A 60 s budget: within the 2 s wait only the work path can finish.
        assertEquals(1, start(BoundedDispatch(Executors.newSingleThreadExecutor(), timer, 60_000), waitMs = 2_000) { error("boom") }.get())
    }

    @Test
    fun finishesOnSuccessWithoutWaitingForTheBudget() {
        assertEquals(1, start(BoundedDispatch(Executors.newSingleThreadExecutor(), timer, 60_000), waitMs = 2_000) { }.get())
    }

    @Test
    fun finishesOnceAtTheBudgetWhenWorkHangs() {
        val release = CountDownLatch(1)
        val d = BoundedDispatch(Executors.newSingleThreadExecutor(), timer, 50)
        val workDone = CountDownLatch(1)
        // The work hangs far longer than we wait; only the 50 ms budget can finish.
        val finished = start(d, waitMs = 1_000) {
            release.await(30, TimeUnit.SECONDS)
            workDone.countDown()
        }
        assertEquals(1, finished.get()) // finished by the timer while the work still hangs
        release.countDown()
        workDone.await(2, TimeUnit.SECONDS)
        Thread.sleep(100)
        assertEquals(1, finished.get()) // the late completion does not finish again
    }

    @Test
    fun finishesWhenTheExecutorRejects() {
        val ex = Executors.newSingleThreadExecutor().apply { shutdown() }
        assertEquals(1, awaitFinish(BoundedDispatch(ex, timer, 1_000)) { })
        try {
            ex.execute { }
        } catch (_: RejectedExecutionException) {
        }
    }

    @Test
    fun finishesOnceWhenTheTimerRejects() {
        val deadTimer = Executors.newSingleThreadScheduledExecutor().apply { shutdown() }
        assertEquals(1, awaitFinish(BoundedDispatch(Executors.newSingleThreadExecutor(), deadTimer, 1_000)) { })
    }

    @Test
    fun aThrowingFinishIsSwallowedAndNotRepeated() {
        val calls = AtomicInteger()
        val done = CountDownLatch(1)
        BoundedDispatch(Executors.newSingleThreadExecutor(), timer, 50).run({ Thread.sleep(200); done.countDown() }) {
            calls.incrementAndGet()
            error("already finished")
        }
        done.await(2, TimeUnit.SECONDS)
        Thread.sleep(100)
        assertEquals(1, calls.get())
    }

    @Test
    fun theDaemonDispatchUsesNamedDaemonThreads() {
        val name = java.util.concurrent.atomic.AtomicReference<String>()
        val daemon = java.util.concurrent.atomic.AtomicBoolean()
        assertEquals(1, awaitFinish(BoundedDispatch.daemon("sms")) { name.set(Thread.currentThread().name); daemon.set(Thread.currentThread().isDaemon) })
        assertEquals("zaghlol-sms-intake", name.get())
        assertEquals(true, daemon.get())
        assertEquals(5_000L, BoundedDispatch.BUDGET_MS)
    }

    /** FU-086 I-5: the budget ended the broadcast before the work: the miss is reported once, after finish. */
    @Test
    fun anAbandonedWorkIsReportedOnceAfterFinish() {
        val order = java.util.Collections.synchronizedList(mutableListOf<String>())
        val release = CountDownLatch(1)
        val reported = CountDownLatch(1)
        BoundedDispatch(Executors.newSingleThreadExecutor(), timer, 50).run(
            work = { release.await(30, TimeUnit.SECONDS) },
            onAbandoned = { order.add("abandoned"); reported.countDown() },
            finish = { order.add("finish") },
        )
        assertEquals(true, reported.await(2, TimeUnit.SECONDS))
        release.countDown()
        Thread.sleep(150)
        assertEquals(listOf("finish", "abandoned"), order.toList())
    }

    /** FU-086 I-5: a work that finished within the budget is never reported as missed. */
    @Test
    fun aWorkThatFinishesInTimeIsNotReported() {
        val abandoned = AtomicInteger()
        val finished = CountDownLatch(1)
        BoundedDispatch(Executors.newSingleThreadExecutor(), timer, 200).run(
            work = { },
            onAbandoned = { abandoned.incrementAndGet() },
            finish = { finished.countDown() },
        )
        finished.await(2, TimeUnit.SECONDS)
        Thread.sleep(400) // past the budget
        assertEquals(0, abandoned.get())
    }

    @Test
    fun aRejectedWorkIsReported() {
        val ex = Executors.newSingleThreadExecutor().apply { shutdown() }
        val abandoned = AtomicInteger()
        val finished = AtomicInteger()
        BoundedDispatch(ex, timer, 1_000).run(work = { }, onAbandoned = { abandoned.incrementAndGet() }, finish = { finished.incrementAndGet() })
        assertEquals(1, finished.get())
        assertEquals(1, abandoned.get())
    }

    @Test
    fun theMissedRecorderRecordsTheReceiveTimeOnItsOwnThreadAndSwallowsFailures() {
        val thread = Executors.newSingleThreadExecutor { r -> Thread(r, "missed-test") }
        val seen = java.util.concurrent.LinkedBlockingQueue<Pair<Long, String>>()
        val record = SmsCapture.missedRecorder(thread, 1_234L) { at -> seen.add(at to Thread.currentThread().name) }
        record()
        assertEquals(1_234L to "missed-test", seen.poll(2, TimeUnit.SECONDS))
        // A throwing store and a dead executor are both swallowed.
        val throwing = SmsCapture.missedRecorder(thread, 1L) { error("keystore busy") }
        throwing()
        thread.shutdown()
        val dead = SmsCapture.missedRecorder(thread, 1L) { }
        dead()
    }
}
