package app.zaghlol.spike.sms

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

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
        assertEquals(1, awaitFinish(BoundedDispatch(Executors.newSingleThreadExecutor(), timer, 1_000)) { error("boom") })
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
}
