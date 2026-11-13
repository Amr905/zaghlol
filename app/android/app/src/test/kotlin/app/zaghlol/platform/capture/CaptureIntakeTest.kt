package app.zaghlol.platform.capture

import app.zaghlol.platform.guard.AndroidGuardChannel
import app.zaghlol.platform.guard.GuardDecision
import app.zaghlol.platform.guard.GuardDropReason
import app.zaghlol.platform.guard.GuardFixtures
import app.zaghlol.platform.guard.GuardKeepKind
import app.zaghlol.platform.guard.GuardRuntime
import app.zaghlol.platform.guard.GuardUserConfigStore
import app.zaghlol.platform.guard.SoftwareGuardUserCipher
import app.zaghlol.platform.ingest.IngestTrace
import app.zaghlol.platform.spool.AdmissionClass
import app.zaghlol.platform.spool.CaptureStatusStore
import app.zaghlol.platform.spool.FaultyFileOps
import app.zaghlol.platform.spool.FileStep
import app.zaghlol.platform.spool.FlakySpoolCipher
import app.zaghlol.platform.spool.SoftwareSpoolCipher
import app.zaghlol.platform.spool.SpoolLimits
import app.zaghlol.platform.spool.SpoolStore
import app.zaghlol.platform.spool.put
import app.zaghlol.platform.spool.storeIn
import app.zaghlol.platform.spool.tempDir
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Guard → spool → status → enqueue (T-040 design note sections 4 and 11),
 * with the real `GuardRuntime` (t1 golden config), a real `SpoolStore` and
 * `CaptureStatusStore` under one temp root.
 */
class CaptureIntakeTest {
    private val root = tempDir()
    private val spoolDir = File(root, "spool")
    private val status = CaptureStatusStore(File(root, "capture/status.bin"), SoftwareSpoolCipher())
    private var now = 0L
    private val guard = GuardRuntime({ GuardFixtures.t1Base }, GuardUserConfigStore(tempDir(), SoftwareGuardUserCipher()), { now })
        .also { it.writeUser(GuardFixtures.t1User) }
    private var afterWrites = 0
    private var failAfterWrite = false
    private val spooled = ArrayList<String>()
    private val enqueuedTrace = ArrayList<List<String>>()
    private val trace = object : IngestTrace {
        override fun spooled(id: String, rxElapsedNs: Long, rxWallMs: Long) {
            spooled += id
        }

        override fun enqueued(ids: List<String>) {
            enqueuedTrace += ids
        }
    }

    private fun intake(
        store: SpoolStore = storeIn(spoolDir, status = status),
        decide: (AndroidGuardChannel, String, String) -> GuardDecision = guard::decide,
    ) = CaptureIntake(
        channel = AndroidGuardChannel.SMS,
        decide = decide,
        store = store,
        status = status,
        afterWrite = {
            afterWrites++
            if (failAfterWrite) throw IllegalStateException("wm down")
        },
        trace = { trace },
    )

    private val stamp = ReceiveStamp(wallMs = 1_700_000_000_123L, elapsedNs = 987_654_321L, bootCount = 7, simSlot = 1)

    private fun msg(source: String, body: String) = CapturedMessage(source, body)

    /** Every file under [dir] with its bytes (the whole tree, byte for byte). */
    private fun tree(dir: File): Map<String, List<Byte>> =
        dir.walkTopDown().associate { f -> f.relativeTo(dir).path to (if (f.isFile) f.readBytes().toList() else emptyList()) }

    @Test
    fun personalSmsLeavesTheWholeRootByteIdentical() {
        val before = tree(root)
        val r = intake().process(listOf(msg("Mom", "see you at 7, bring the cake")), stamp)
        assertEquals(1, r.dropped)
        assertEquals(before, tree(root))
        assertFalse(spoolDir.exists())
        assertFalse(File(root, "capture").exists())
        assertEquals(0, afterWrites)
        assertTrue(spooled.isEmpty())
    }

    /** FU-121 negative proof 1: a personal message from a user-added sender leaves nothing behind. */
    @Test
    fun personalSmsFromAUserAddedSenderLeavesTheWholeRootByteIdentical() {
        val before = tree(root)
        val r = intake().process(
            listOf(msg("MyCoop", "see you at 7, bring the cake"), msg("club-7", "Paid 10.00 for lunch, thanks")),
            stamp,
        )
        assertEquals(2, r.dropped)
        assertEquals(0, r.written.size)
        assertEquals(before, tree(root))
        assertFalse(spoolDir.exists())
        assertFalse(File(root, "capture").exists())
        assertEquals(0, afterWrites)
        assertTrue(spooled.isEmpty())
        assertTrue(enqueuedTrace.isEmpty())
    }

    /** FU-121 negative proof 2: a registry bank sender is unaffected (kept without currency text). */
    @Test
    fun aRegistrySenderIsStillKeptWithoutCurrencyText() {
        val r = intake().process(listOf(msg("NBE", "Paid 10.00")), stamp)
        assertEquals(1, r.written.size)
        assertEquals(0, r.dropped)
    }

    @Test
    fun anOtpFromAKeptSenderLeavesNoTraceEither() {
        val before = tree(root)
        val r = intake().process(listOf(msg("NBE", "Your OTP is 123456")), stamp)
        assertEquals(1, r.dropped)
        assertEquals(before, tree(root))
        assertEquals(0, afterWrites)
    }

    @Test
    fun aBankSmsIsOnePriorityEntryWithEveryRecordField() {
        // Generic budget 0: a priority write still succeeds, so the class must be PRIORITY.
        val store = storeIn(spoolDir, status = status, limits = SpoolLimits(genericMaxEntries = 0))
        val r = intake(store).process(listOf(msg("NBE", "Purchase EGP 10.00 card **1234")), stamp)
        assertEquals(1, r.written.size)
        // AC2 on disk, not only the returned ids: exactly one entry file, the one reported.
        assertEquals(r.written, store.pendingIds())
        assertEquals(listOf("${r.written[0]}.bin"), spoolDir.list().orEmpty().filter { it.endsWith(".bin") })
        assertEquals(1, afterWrites)
        val rec = (store.read(r.written[0]) as SpoolStore.ReadResult.Ok).record
        assertEquals("sms", rec.channel)
        assertEquals("NBE", rec.source)
        assertEquals("Purchase EGP 10.00 card **1234", rec.body)
        assertEquals(stamp.wallMs, rec.receivedAtMs)
        assertEquals(1, rec.simSlot)
        assertEquals("nbe", rec.guardInst)
        assertEquals("1234", rec.guardLast4)
        assertEquals(stamp.elapsedNs, rec.rxElapsedNs)
        assertEquals(7, rec.bootCount)
        assertEquals(r.written, spooled)
        assertEquals(listOf(r.written), enqueuedTrace)
        assertFalse("a normal keep writes no status", File(root, "capture").exists())
    }

    @Test
    fun aUserSenderIsPriorityAndAGenericKeepIsGeneric() {
        val store = storeIn(spoolDir, status = status, limits = SpoolLimits(genericMaxEntries = 0))
        val r = intake(store).process(
            listOf(msg("club-7", "Points used: EGP 5.00"), msg("MyBank", "Debit EGP 250.00 at SHOP E")),
            stamp,
        )
        assertEquals("user sender written (priority)", 1, r.written.size)
        assertEquals("generic refused by the generic budget", 1, r.refused)
        assertEquals(1L, status.read().refusedGeneric)
        assertEquals(1, afterWrites)
    }

    @Test
    fun admissionClassTable() {
        assertEquals(AdmissionClass.PRIORITY, CaptureIntake.admissionOf(GuardKeepKind.REGISTRY))
        assertEquals(AdmissionClass.PRIORITY, CaptureIntake.admissionOf(GuardKeepKind.USER))
        assertEquals(AdmissionClass.GENERIC, CaptureIntake.admissionOf(GuardKeepKind.GENERIC))
    }

    @Test
    fun rateLimitedIsRecordedWithoutAnEntryOrAnEnqueue() {
        val r = intake(decide = { _, _, _ -> GuardDecision.Drop(GuardDropReason.RATE_LIMITED) })
            .process(listOf(msg("NBE", "Purchase EGP 10.00")), stamp)
        assertEquals(1, r.dropped)
        assertFalse(spoolDir.exists())
        val s = status.read()
        assertEquals(1L, s.rateLimited)
        assertEquals(stamp.wallMs, s.firstMissedSmsAtMs)
        assertEquals(0, afterWrites)
    }

    @Test
    fun theRealRateLimiterDropsTheTwentyFirstKeepOfAMinute() {
        val i = intake()
        repeat(20) { k -> assertEquals(1, i.process(listOf(msg("NBE", "Purchase EGP $k.00")), stamp).written.size) }
        val r = i.process(listOf(msg("NBE", "Purchase EGP 99.00")), stamp)
        assertTrue(r.written.isEmpty())
        assertEquals(1L, status.read().rateLimited)
        assertEquals(20, afterWrites)
    }

    @Test
    fun aRefusalIsCountedAndStillEnqueuesOnce() {
        val store = storeIn(spoolDir, status = status, limits = SpoolLimits(maxEntries = 1), wall = { stamp.wallMs })
        store.put("old")
        val r = intake(store).process(listOf(msg("NBE", "Purchase EGP 1.00"), msg("CIB", "Purchase EGP 2.00")), stamp)
        assertEquals(2, r.refused)
        assertTrue(r.written.isEmpty())
        assertEquals("one enqueue + notify for the batch", 1, afterWrites)
        assertTrue(r.enqueued)
        val s = status.read()
        assertEquals(2L, s.refusedFull)
        assertEquals(stamp.wallMs, s.firstMissedSmsAtMs)
        assertTrue("nothing traced as enqueued for refusals", enqueuedTrace.isEmpty())
    }

    @Test
    fun twoMessagesInOneBroadcastAreOneEnqueue() {
        val r = intake().process(listOf(msg("NBE", "Purchase EGP 1.00"), msg("CIB", "Purchase EGP 2.00")), stamp)
        assertEquals(2, r.written.size)
        assertEquals(1, afterWrites)
        assertEquals(listOf(r.written), enqueuedTrace)
    }

    @Test
    fun aWriteThatThrowsEnqueuesNothingAndLeavesNoFile() {
        for (store in listOf(
            storeIn(spoolDir, status = status, files = FaultyFileOps(FileStep.SYNC)),
            storeIn(spoolDir, cipher = FlakySpoolCipher(0, "ZG_CANARY_7731", failEncrypt = true), status = status),
        )) {
            val r = intake(store).process(listOf(msg("NBE", "ZG_CANARY_7731 Purchase EGP 1.00")), stamp)
            assertEquals(1, r.failed)
            assertFalse(r.enqueued)
            assertFalse(r.toString().contains("ZG_CANARY"))
        }
        assertEquals(0, afterWrites)
        assertTrue(spoolDir.list().orEmpty().isEmpty())
        assertFalse(File(root, "capture").exists())
    }

    @Test
    fun anEnqueueThatThrowsKeepsTheEntry() {
        failAfterWrite = true
        val store = storeIn(spoolDir, status = status)
        val r = intake(store).process(listOf(msg("NBE", "Purchase EGP 1.00")), stamp)
        assertFalse(r.enqueued)
        assertEquals(1, afterWrites)
        assertEquals(r.written, store.pendingIds())
        assertTrue(enqueuedTrace.isEmpty())
    }

    @Test
    fun aThrowingGuardIsADrop() {
        val r = intake(decide = { _, _, _ -> throw IllegalStateException("ZG_CANARY_7731") })
            .process(listOf(msg("NBE", "Purchase EGP 1.00")), stamp)
        assertEquals(1, r.dropped)
        assertFalse(spoolDir.exists())
        assertEquals(0, afterWrites)
    }

    @Test
    fun theIntakeDecidesOnItsOwnChannelOnly() {
        val seen = ArrayList<AndroidGuardChannel>()
        intake(decide = { c, _, _ -> seen += c; GuardDecision.Drop(GuardDropReason.NOT_FINANCIAL) })
            .process(listOf(msg("a", "b"), msg("c", "d")), stamp)
        assertEquals(listOf(AndroidGuardChannel.SMS, AndroidGuardChannel.SMS), seen)
    }

    @Test
    fun theEntryBytesNeverCarryTheBody() {
        val store = storeIn(spoolDir, status = status)
        val r = intake(store).process(listOf(msg("NBE", "ZG_CANARY_7731 Purchase EGP 1.00")), stamp)
        val raw = File(spoolDir, "${r.written[0]}.bin").readBytes()
        assertFalse(String(raw, Charsets.ISO_8859_1).contains("ZG_CANARY"))
        assertArrayEquals(raw, File(spoolDir, "${r.written[0]}.bin").readBytes())
    }
}
