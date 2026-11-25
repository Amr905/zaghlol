package app.zaghlol.platform.share

import java.io.InputStream
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** FU-070 S1: a provider that never returns can't block later shares. */
class ShareWorkersTest {
    private val hang = CountDownLatch(1)
    private val workers = ShareWorkers(threads = 2, queue = 1, name = "share-test")
    private val dir = Files.createTempDirectory("share-workers").toFile()

    @After
    fun tearDown() {
        hang.countDown()
        workers.shutdownNow()
        dir.deleteRecursively()
    }

    private fun intake() = ShareIntake(ShareStore(dir, SoftwareShareCipher()), "app.zaghlol", FakeBoundsProbe())

    /** An opener that never returns (ignores cancellation), like a stuck provider. */
    private fun stuckSource() = FakeShareSource(
        intentType = "text/plain",
        streamScheme = "content",
        streamHost = "com.example.stuck",
        opener = {
            try {
                hang.await()
            } catch (_: InterruptedException) {
                // shutdownNow at the end of the test
            }
            null as InputStream?
        },
    )

    @Test
    fun aShareAfterAStuckProviderStillCompletes() {
        val results = LinkedBlockingQueue<ShareOutcome>()
        workers.submit(task = { results.add(intake().accept(stuckSource())) }, onRejected = { error("not rejected") })
        workers.submit(
            task = { results.add(intake().accept(FakeShareSource(intentType = "text/plain", text = "SYNTHETIC"))) },
            onRejected = { error("not rejected") },
        )
        val next = results.poll(5, TimeUnit.SECONDS)
        assertTrue("the second share completed while the first is stuck: $next", next is ShareOutcome.Accepted)
    }

    @Test
    fun whenEveryWorkerAndQueueSlotIsHeldANewShareIsRefusedAtOnce() {
        val started = CountDownLatch(2)
        repeat(2) {
            workers.submit(task = { started.countDown(); intake().accept(stuckSource()) }, onRejected = { error("not rejected") })
        }
        assertTrue(started.await(5, TimeUnit.SECONDS))
        workers.submit(task = { intake().accept(stuckSource()) }, onRejected = { error("queued, not rejected") }) // fills the queue
        var rejected = 0
        workers.submit(task = { error("must not run") }, onRejected = { rejected++ })
        assertEquals(1, rejected)
    }
}
