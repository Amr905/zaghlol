package app.zaghlol.platform.guard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class SenderRateLimiterTest {
    private val keep = GuardDecision.Keep(GuardKeepKind.REGISTRY, "nbe")

    private fun SenderRateLimiter.kept(source: String, t: Long, ch: String = "sms") = apply(keep, ch, source, t) is GuardDecision.Keep

    @Test
    fun windowBoundaryIsExactlyDarts() {
        val l = SenderRateLimiter(2)
        assertTrue(l.kept("NBE", 0) && l.kept("NBE", 1))
        assertEquals(false, l.kept("NBE", 59_999))
        // At exactly 60,000 ms the first entry has left the window (`>=`).
        assertTrue(l.kept("NBE", 60_000))
    }

    @Test
    fun keyIsTheFoldedSourceAndChannel() {
        val l = SenderRateLimiter(1)
        assertTrue(l.kept("NBE", 0))
        assertEquals(false, l.kept(" nbe\u200F", 0))
        assertTrue(l.kept("NBE", 0, ch = "shortcut_message"))
        // Unknown channel: Dart-trimmed source.
        assertTrue(l.kept("\uFEFFX", 0, ch = "mms"))
        assertEquals(false, l.kept("X", 0, ch = "mms"))
    }

    @Test
    fun dropsPassThroughUncounted() {
        val l = SenderRateLimiter(1)
        val drop = GuardDecision.Drop(GuardDropReason.NOT_FINANCIAL)
        repeat(5) { assertTrue(l.apply(drop, "sms", "NBE", 0) === drop) }
        assertTrue(l.kept("NBE", 0))
        assertEquals(0 + 1, l.trackedKeys)
    }

    @Test
    fun lruForgetsTheLeastRecentKey() {
        val l = SenderRateLimiter(1, maxKeys = 3)
        assertTrue(l.kept("A", 0) && l.kept("B", 0) && l.kept("C", 0))
        assertEquals(false, l.kept("A", 0)) // touch A: B is now the oldest
        assertTrue(l.kept("D", 0)) // evicts B
        assertEquals(3, l.trackedKeys)
        assertTrue(l.kept("B", 0)) // B forgotten -> fresh window; evicts C
        assertEquals(false, l.kept("A", 0))
    }

    @Test
    fun clockGoingBackwardsRestartsTheWindow() {
        val l = SenderRateLimiter(1)
        assertTrue(l.kept("NBE", 10_000))
        assertTrue(l.kept("NBE", 5_000))
    }

    /** Two actors (receiver and listener threads) never exceed the limit together. */
    @Test
    fun concurrentCallersShareOneBudget() {
        val l = SenderRateLimiter(20)
        val pool = Executors.newFixedThreadPool(8)
        val start = CountDownLatch(1)
        val kept = AtomicInteger()
        repeat(400) {
            pool.execute {
                start.await()
                if (l.kept("NBE", 1_000)) kept.incrementAndGet()
            }
        }
        start.countDown()
        pool.shutdown()
        assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS))
        assertEquals(20, kept.get())
    }
}
