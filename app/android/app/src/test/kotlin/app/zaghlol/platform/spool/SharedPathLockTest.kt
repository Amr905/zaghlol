package app.zaghlol.platform.spool

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * T-039 review #1: two instances over one path share one lock (and one
 * generic window / pending delta). Each instance-A file op parks at [at] until
 * the other instance has finished, or [PARK_MS] passed. With per-instance
 * locks the other instance finishes inside the park and the tests fail; with
 * the shared lock it waits for A, the park times out and A completes first.
 */
class SharedPathLockTest {
    private class ParkingFileOps(private val at: FileStep, private val otherDone: CountDownLatch) : SpoolFileOps {
        @Volatile var parked = CountDownLatch(1)

        private fun park(step: FileStep) {
            if (step != at) return
            parked.countDown()
            otherDone.await(PARK_MS, TimeUnit.MILLISECONDS)
        }

        override fun open(file: File): FileOutputStream {
            val out = DefaultSpoolFileOps.open(file)
            park(FileStep.OPEN)
            return out
        }

        override fun write(out: FileOutputStream, bytes: ByteArray) = out.write(bytes)

        override fun sync(out: FileOutputStream) = out.fd.sync()

        override fun move(from: File, to: File) {
            park(FileStep.MOVE)
            DefaultSpoolFileOps.move(from, to)
        }

        override fun syncDir(dir: File) {}
    }

    /** Runs [a] on a thread; once it parks, runs [b] on another; returns A's error. */
    private fun race(ops: ParkingFileOps, otherDone: CountDownLatch, a: () -> Unit, b: () -> Unit): Throwable? {
        var error: Throwable? = null
        val ta = thread {
            try {
                a()
            } catch (t: Throwable) {
                error = t
            }
        }
        assertTrue("A reached the parked step", ops.parked.await(5, TimeUnit.SECONDS))
        val tb = thread {
            try {
                b()
            } finally {
                otherDone.countDown()
            }
        }
        ta.join(10_000)
        tb.join(10_000)
        return error
    }

    @Test
    fun aSweepOnAnotherInstanceNeverDeletesAnInFlightTmp() {
        val dir = tempDir()
        val sweepDone = CountDownLatch(1)
        val ops = ParkingFileOps(FileStep.MOVE, sweepDone) // A parks after fsync, before rename
        val a = storeIn(dir, files = ops)
        val b = storeIn(File(dir.path + "/./")) // same directory, different spelling
        var id: String? = null
        var swept = -1
        val error = race(ops, sweepDone, a = { id = a.put("in flight") }, b = { swept = b.sweepTmp() })
        assertNull("A's write failed: the sweep deleted its .tmp", error)
        assertEquals("the sweep saw no .tmp", 0, swept)
        assertEquals(listOf(id), b.pendingIds())
        assertEquals("in flight", (b.read(id!!) as SpoolStore.ReadResult.Ok).record.body)
    }

    @Test
    fun theGenericRateWindowIsSharedByInstancesOverOneDirectory() {
        val dir = tempDir()
        val clock = FakeClock()
        val limits = SpoolLimits(genericPerWindow = 2)
        val a = storeIn(dir, limits = limits, mono = clock.fn)
        val b = storeIn(dir, limits = limits, mono = clock.fn)
        a.put("g1", AdmissionClass.GENERIC)
        b.put("g2", AdmissionClass.GENERIC)
        val third = b.write(record(body = "g3"), AdmissionClass.GENERIC)
        assertEquals(RefusalReason.GENERIC_RATE, (third as SpoolStore.WriteResult.Refused).reason)
    }

    @Test
    fun statusWritesOnTwoInstancesNeverInterleave() {
        val dir = tempDir()
        val bDone = CountDownLatch(1)
        val ops = ParkingFileOps(FileStep.OPEN, bDone) // A parks with status.bin.tmp open, before writing
        val a = statusIn(dir, files = ops)
        val b = statusIn(dir)
        val error = race(
            ops,
            bDone,
            a = { a.recordRefused(RefusalReason.FULL, "sms", 100) },
            b = { b.recordRefused(RefusalReason.FULL, "notification", 200) },
        )
        assertNull(error)
        for (s in listOf(statusIn(dir).read(), a.read(), b.read())) {
            assertEquals("both refusals counted once", 2L, s.refusedFull)
            assertEquals(1L, s.missedNotifications)
            assertEquals(100L, s.firstMissedSmsAtMs)
            assertEquals("never mistaken for a lost key", -1L, s.keyInvalidatedAtMs)
            assertEquals(2L, s.seq)
        }
    }

    private companion object {
        const val PARK_MS = 500L
    }
}
