package app.zaghlol.platform.spool

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GetOrCreateTest {
    @Test
    fun concurrentFirstCallersCreateExactlyOnceAndShareTheResult() {
        var stored: Any? = null
        val creations = AtomicInteger()
        val holder = GetOrCreate(
            load = { stored },
            create = {
                creations.incrementAndGet()
                Thread.sleep(20) // widen the check-then-create window
                Any().also { stored = it }
            },
        )
        val threads = 16
        val start = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(threads)
        val results = (1..threads).map { pool.submit<Any> { start.await(); holder.get() } }
        start.countDown()
        val keys = results.map { it.get(5, TimeUnit.SECONDS) }
        pool.shutdown()

        assertEquals(1, creations.get())
        assertTrue(keys.all { it === keys[0] })
    }

    @Test
    fun anExistingValueIsNeverRecreated() {
        val existing = Any()
        val holder = GetOrCreate(load = { existing }, create = { throw AssertionError("must not create") })
        assertTrue(holder.get() === existing)
    }
}
