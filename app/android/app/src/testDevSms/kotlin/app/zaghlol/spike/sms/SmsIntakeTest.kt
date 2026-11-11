package app.zaghlol.spike.sms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SmsIntakeTest {
    private val stamp = ReceiveStamp(1_700_000_000_000L, 5_000_000L, 7, 0)

    @Test
    fun multipartIsJoinedInPduOrderPerSender() {
        val out = SmsAssembler.assemble(
            listOf(
                SmsPart("5550100", "part one, ", 10),
                SmsPart("CIB", "other", 11),
                SmsPart("5550100", "part two", 12),
                SmsPart(null, "orphan", 13),
            ),
        )
        assertEquals(2, out.size)
        assertEquals("5550100", out[0].source)
        assertEquals("part one, part two", out[0].body)
        assertEquals(10L, out[0].sentAtMs)
        assertEquals("other", out[1].body)
    }

    @Test
    fun nonAllowlistedAndOtpWriteNothingAndEnqueueNothing() {
        val dir = tempDir()
        val sched = FakeScheduler()
        val intake = SmsIntake(SpikeGuard(), storeIn(dir), sched, null)
        val ids = intake.process(
            listOf(AssembledSms("Mom", "see you at 8", 1), AssembledSms("5550100", "OTP 123456", 2)),
            stamp,
        )
        assertTrue(ids.isEmpty())
        assertEquals(0, sched.enqueued)
        assertEquals(0, dir.list()!!.size)
    }

    @Test
    fun keptMessageIsSpooledThenEnqueuedOnce() {
        val dir = tempDir()
        val sched = FakeScheduler()
        val store = storeIn(dir)
        val intake = SmsIntake(SpikeGuard(), store, sched, null)
        val ids = intake.process(listOf(AssembledSms("5550100", "a", 1), AssembledSms("5550100", "b", 1)), stamp)
        assertEquals(2, ids.size)
        assertEquals(1, sched.enqueued)
        val rec = (store.read(ids[0]) as SpoolStore.ReadResult.Ok).record
        assertEquals(stamp.wallMs, rec.receivedAtMs)
        assertEquals(stamp.elapsedNs, rec.rxElapsedNs)
        assertEquals(7, rec.bootCount)
        assertEquals(0, rec.simSlot)
        assertEquals("spike", rec.guardInst)
    }

    @Test
    fun fullSpoolRefusesAndDoesNotEnqueue() {
        val dir = tempDir()
        val sched = FakeScheduler()
        val intake = SmsIntake(SpikeGuard(), storeIn(dir, maxEntries = 0), sched, null)
        assertTrue(intake.process(listOf(AssembledSms("5550100", "a", 1)), stamp).isEmpty())
        assertEquals(0, sched.enqueued)
    }

    @Test
    fun failedEnqueueKeepsTheEntry() {
        val dir = tempDir()
        val sched = FakeScheduler().apply { fail = true }
        val store = storeIn(dir)
        val ids = SmsIntake(SpikeGuard(), store, sched, null).process(listOf(AssembledSms("5550100", "a", 1)), stamp)
        assertEquals(1, ids.size)
        assertEquals(ids, store.pendingIds())
    }

    @Test
    fun unwritableDirectoryDoesNotThrow() {
        val file = kotlin.io.path.createTempFile().toFile() // a file, not a directory
        val ids = SmsIntake(SpikeGuard(), storeIn(java.io.File(file, "spool")), FakeScheduler(), null)
            .process(listOf(AssembledSms("5550100", "a", 1)), stamp)
        assertTrue(ids.isEmpty())
    }
}
