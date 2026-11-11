package app.zaghlol.platform.capture

import app.zaghlol.platform.spool.AdmissionClass
import app.zaghlol.platform.spool.CaptureStatusStore
import app.zaghlol.platform.spool.FlakySpoolCipher
import app.zaghlol.platform.spool.RecordingSleep
import app.zaghlol.platform.spool.SoftwareSpoolCipher
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.SpoolLimits
import app.zaghlol.platform.spool.SpoolStore
import app.zaghlol.platform.spool.otherKeyCipher
import app.zaghlol.platform.spool.put
import app.zaghlol.platform.spool.record
import app.zaghlol.platform.spool.statusIn
import app.zaghlol.platform.spool.storeIn
import app.zaghlol.platform.spool.tempDir
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PrintStream

class AndroidCaptureHostTest {
    private val dir = tempDir()
    private val statusDir = tempDir()
    private val status = statusIn(statusDir)
    private val store = storeIn(dir, status = status)
    private val claim = SpoolClaim(clock = { 0 })
    private val sched = FakeScheduler()
    private val device = FakeDevice()

    private fun host(
        engine: Long,
        s: SpoolStore = store,
        st: CaptureStatusStore = status,
        writer: ((ByteArray) -> Unit)? = null,
        guard: (() -> GuardConfigState)? = null,
        scheduler: IngestScheduler? = sched,
        dev: CaptureDevice? = device,
    ) = AndroidCaptureHost(engine, s, claim, st, scheduler, writer, guard, dev)

    private fun expectCode(code: String, block: () -> Unit) {
        try {
            block()
            fail("no error")
        } catch (e: CaptureApiError) {
            assertEquals(code, e.code)
            assertNull(e.message)
            assertNull(e.details)
        }
    }

    @Test
    fun drainReturnsOldestFirstUpToMax() {
        val ids = (1..3).map { store.put("m$it") }
        val got = host(1).drainSpool(2)
        assertEquals(ids.take(2), got.map { it.id })
        assertEquals("m1", got[0].body)
        assertEquals("5550100", got[0].source)
        assertEquals("sms", got[0].channel)
        assertEquals(1L, got[0].simSlot)
        assertEquals(1_700_000_000_000L, got[0].receivedAtMs)
    }

    @Test
    fun maxIsClamped() {
        repeat(3) { store.put("m$it") }
        assertEquals(1, host(1).drainSpool(0).size)
        assertEquals(3, host(1).drainSpool(1_000_000).size)
    }

    // AC3.
    @Test
    fun ackDeletesOnlyListedIdsThisHostDrained() {
        val a = store.put("a")
        val b = store.put("b")
        val ui = host(1)
        assertEquals(listOf(a, b), ui.drainSpool(10).map { it.id })
        val c = store.put("c") // written after the drain: never received by ui
        ui.ackSpool(listOf(a, c, "not-a-ulid", "../../x"))
        assertEquals(listOf(b, c), store.pendingIds())
        ui.ackSpool(listOf(a)) // idempotent
        assertEquals(listOf(b, c), store.pendingIds())
    }

    @Test
    fun anotherEnginesAckCannotDeleteEntriesItNeverReceived() {
        val a = store.put("a")
        val ui = host(1)
        val headless = host(2)
        ui.drainSpool(10)
        headless.ackSpool(listOf(a)) // stray / late ack
        assertEquals(listOf(a), store.pendingIds())
        ui.ackSpool(listOf(a))
        assertEquals(emptyList<String>(), store.pendingIds())
    }

    /** After a claim expiry another engine may ack an entry; the first host forgets it at its next drain. */
    @Test
    fun ackRightsForEntriesThatLeftTheSpoolAreForgotten() {
        var now = 0L
        val expiring = SpoolClaim(clock = { now }, ttlMs = 10)
        val a = store.put("a")
        val ui = AndroidCaptureHost(1, store, expiring, status, sched, null, null, device)
        val headless = AndroidCaptureHost(2, store, expiring, status, sched, null, null, device)
        assertEquals(listOf(a), ui.drainSpool(10).map { it.id })
        now = 11 // the UI engine never acked; its claim expires
        assertEquals(listOf(a), headless.drainSpool(10).map { it.id })
        headless.ackSpool(listOf(a))
        assertEquals(1, ui.ackableCount())
        val b = store.put("b")
        now = 30
        assertEquals(listOf(b), ui.drainSpool(10).map { it.id })
        assertEquals(1, ui.ackableCount()) // b only; a is gone
    }

    @Test
    fun moreThan100IdsIsIoErrorAndDeletesNothing() {
        val a = store.put("a")
        val h = host(1)
        h.drainSpool(10)
        expectCode("IO_ERROR") { h.ackSpool(List(100) { a } + a) }
        assertEquals(listOf(a), store.pendingIds())
        h.ackSpool(List(100) { a })
        assertEquals(emptyList<String>(), store.pendingIds())
    }

    @Test
    fun twoEnginesNeverGetTheSameEntries() {
        val ids = (1..2).map { store.put("m$it") }
        val ui = host(1)
        val headless = host(2)
        assertEquals(ids, ui.drainSpool(10).map { it.id })
        assertEquals(emptyList<String>(), headless.drainSpool(10))
        ui.ackSpool(ids)
        val third = store.put("m3")
        assertEquals(listOf(third), headless.drainSpool(10).map { it.id })
    }

    @Test
    fun detachReleasesTheClaimWithoutDeletingAndDropsAckRights() {
        val id = store.put("m")
        val ui = host(1)
        ui.drainSpool(10)
        ui.detach()
        ui.ackSpool(listOf(id))
        assertEquals(listOf(id), host(2).drainSpool(10).map { it.id })
    }

    @Test
    fun noAckMeansRedelivery() {
        val id = store.put("m")
        val h = host(1)
        h.drainSpool(10)
        assertEquals(listOf(id), h.drainSpool(10).map { it.id })
    }

    @Test
    fun drainSweepsTmp() {
        val id = store.put("m")
        File(dir, "01ARZ3NDEKTSV4RRFFQ69G5FAV.bin.tmp").writeText("x")
        host(1).drainSpool(10)
        assertEquals(listOf("$id.bin"), dir.list()!!.toList())
    }

    @Test
    fun corruptEntryIsDeletedCountedAndNotReturned() {
        val bad = store.put("bad")
        val good = store.put("good")
        File(dir, "$bad.bin").writeBytes(ByteArray(40))
        val h = host(1)
        assertEquals(listOf(good), h.drainSpool(10).map { it.id })
        assertEquals(listOf(good), store.pendingIds())
        assertEquals(1L, h.getSpoolStatus().decryptDeleted)
    }

    // AC5: lost key → readable entries still drained, old-key entries deleted on tag failure, reported.
    @Test
    fun lostKeyIsReportedNotThrownAndReadableEntriesStillDrain() {
        var wall = 1_700_000_000_000L
        val oldKeyStore = storeIn(dir, otherKeyCipher(), wall = { wall })
        val old = (1..100).map { oldKeyStore.put("old$it") }
        wall += 10_000
        val sleep = RecordingSleep()
        val newKeyStore = storeIn(dir, SoftwareSpoolCipher(), sleep, status = status, keyCreatedAtMs = { wall - 5_000 }, wall = { wall })
        val fresh = newKeyStore.put("new")
        val h = host(1, s = newKeyStore)
        val got = h.drainSpool(10)
        assertEquals(listOf(fresh), got.map { it.id })
        assertEquals(emptyList<Long>(), sleep.calls) // I-3: no ladder for 100 old entries
        assertTrue(old.none { File(dir, "$it.bin").exists() })
        val s = h.getSpoolStatus()
        assertEquals(wall, s.keyInvalidatedAtMs)
        assertEquals(100L, s.decryptDeleted)
        assertEquals(1L, s.pending)
    }

    @Test
    fun aTransientKeystoreErrorDeletesNothing() {
        val ids = (1..3).map { store.put("m$it") }
        val flaky = storeIn(dir, FlakySpoolCipher(1_000), status = status, keyCreatedAtMs = { Long.MAX_VALUE })
        assertEquals(emptyList<SpoolEntry>(), host(1, s = flaky).drainSpool(10))
        assertEquals(ids, store.pendingIds())
        val s = host(1).getSpoolStatus()
        assertEquals(0L, s.decryptDeleted)
        assertNull(s.keyInvalidatedAtMs)
    }

    // AC4: a full spool refuses, records, never evicts; the drain still works.
    @Test
    fun fullSpoolIsReportedThroughStatus() {
        val small = storeIn(dir, status = status, limits = SpoolLimits(maxEntries = 2))
        val ids = listOf(small.put("a"), small.put("b"))
        val r = small.write(record(body = "c"), AdmissionClass.PRIORITY)
        assertTrue(r is SpoolStore.WriteResult.Refused)
        val h = host(1, s = small)
        val s = h.getSpoolStatus()
        assertEquals(1L, s.refusedFull)
        assertEquals(2L, s.pending)
        assertTrue(s.firstMissedSmsAtMs!! > 0)
        assertEquals(ids, h.drainSpool(10).map { it.id })
    }

    @Test
    fun statusDefaultsAndClear() {
        val h = host(1)
        val empty = h.getSpoolStatus()
        assertEquals(SpoolStatus(0, 0, 0, 0, 0, 0, null, 0, null, GuardConfigState.UNKNOWN), empty)
        status.recordRateLimited("notification", 5)
        val s = h.getSpoolStatus()
        assertEquals(1L, s.rateLimited)
        assertEquals(1L, s.missedNotifications)
        h.clearSpoolAlerts(s.seq - 1) // stale
        assertEquals(1L, h.getSpoolStatus().rateLimited)
        h.clearSpoolAlerts(s.seq)
        assertEquals(0L, h.getSpoolStatus().rateLimited)
    }

    @Test
    fun guardStateIsPassedThroughAndUnknownOnError() {
        assertEquals(GuardConfigState.BASE_ONLY, host(1, guard = { GuardConfigState.BASE_ONLY }).getSpoolStatus().guardState)
        assertEquals(GuardConfigState.UNKNOWN, host(1, guard = { throw IllegalStateException("x") }).getSpoolStatus().guardState)
    }

    @Test
    fun unreadableStatusIsIoError() {
        status.recordRefused(app.zaghlol.platform.spool.RefusalReason.FULL, "sms", 1)
        val h = host(1, st = statusIn(statusDir, FlakySpoolCipher(100)))
        expectCode("IO_ERROR") { h.getSpoolStatus() }
        expectCode("IO_ERROR") { h.clearSpoolAlerts(1) }
    }

    @Test
    fun writeGuardConfigPassesTheBytesAndZeroesThem() {
        var seen: ByteArray? = null
        val json = "{\"v\":1}".toByteArray()
        host(1, writer = { seen = it.copyOf() }).writeGuardConfig(json)
        assertArrayEquals("{\"v\":1}".toByteArray(), seen)
        assertTrue(json.all { it == 0.toByte() })
    }

    @Test
    fun writeGuardConfigErrorsAreCodeOnly() {
        expectCode("NOT_AVAILABLE") { host(1).writeGuardConfig(ByteArray(1)) }
        expectCode("CONFIG_INVALID") {
            host(1, writer = { throw CaptureApiError("CONFIG_INVALID", "ZG_CANARY_7731", "x") }).writeGuardConfig(ByteArray(1))
        }
        expectCode("IO_ERROR") {
            host(1, writer = { throw CaptureApiError("SOMETHING_ELSE", null, null) }).writeGuardConfig(ByteArray(1))
        }
        expectCode("IO_ERROR") { host(1, writer = { throw IllegalStateException("ZG_CANARY_7731") }).writeGuardConfig(ByteArray(1)) }
    }

    @Test
    fun unwiredDependenciesAreNotAvailable() {
        val h = host(1, scheduler = null, dev = null)
        expectCode("NOT_AVAILABLE") { h.scheduleIngestionNow() }
        expectCode("NOT_AVAILABLE") { h.getCapabilities() }
        expectCode("NOT_AVAILABLE") { h.isIgnoringBatteryOptimizations() }
        expectCode("NOT_AVAILABLE") { h.requestIgnoreBatteryOptimizations() }
        expectCode("NOT_AVAILABLE") { h.openNotificationAccessSettings() }
        expectCode("NOT_AVAILABLE") { h.queryInbox(InboxQuery(0, listOf("x"), null, 10)) }
        var result: Result<Boolean>? = null
        h.requestSmsPermission { result = it }
        assertEquals("NOT_AVAILABLE", (result!!.exceptionOrNull() as CaptureApiError).code)
    }

    @Test
    fun schedulingBatteryAndCapabilities() {
        val h = host(1)
        h.scheduleIngestionNow()
        assertEquals(1, sched.enqueued)
        h.requestIgnoreBatteryOptimizations()
        assertEquals(1, device.settingsOpened)
        assertFalse(h.isIgnoringBatteryOptimizations())
        assertTrue(h.getCapabilities().smsFlavor)
        sched.fail = true
        expectCode("IO_ERROR") { h.scheduleIngestionNow() }
    }

    // Section 11: canary through write/read/drain/ack/status with failing parts.
    @Test
    fun canaryNeverLeaks() {
        val canary = "ZG_CANARY_7731"
        val out = ByteArrayOutputStream()
        val err = ByteArrayOutputStream()
        val oldOut = System.out
        val oldErr = System.err
        System.setOut(PrintStream(out, true))
        System.setErr(PrintStream(err, true))
        val texts = ArrayList<String>()
        try {
            val id = store.write(record(body = "$canary paid EGP 1.00", source = canary), AdmissionClass.PRIORITY)
            texts += id.toString()
            val h = host(1)
            val entries = h.drainSpool(10)
            h.ackSpool(entries.map { it.id })
            texts += store.read(entries[0].id).toString()
            store.put(canary)
            texts += (store.read(store.pendingIds()[0]) as SpoolStore.ReadResult.Ok).toString()
            texts += (store.read(store.pendingIds()[0]) as SpoolStore.ReadResult.Ok).record.toString()

            val hostileStatus = statusIn(statusDir, FlakySpoolCipher(100, canary, failEncrypt = true))
            val hostileStore = storeIn(dir, FlakySpoolCipher(100, canary, failEncrypt = true), status = hostileStatus)
            val hostile = host(
                2,
                s = hostileStore,
                st = hostileStatus,
                writer = { throw IllegalStateException(canary) },
                guard = { throw IllegalStateException(canary) },
                scheduler = { throw IllegalStateException(canary) },
            )
            val errors = ArrayList<Throwable>()
            for (call in listOf<() -> Unit>(
                { hostile.drainSpool(10) },
                { hostile.getSpoolStatus() },
                { hostile.clearSpoolAlerts(0) },
                { hostile.writeGuardConfig(canary.toByteArray()) },
                { hostile.scheduleIngestionNow() },
                { hostileStore.write(record(body = canary), AdmissionClass.PRIORITY) },
            )) {
                try {
                    call()
                } catch (t: Throwable) {
                    errors += t
                }
            }
            assertTrue(errors.size >= 4)
            for (t in errors) {
                if (t is IllegalStateException) continue // the fake cipher's own exception (store.write's contract: thrown to the caller)
                texts += t.toString()
                texts += t.message.orEmpty()
                texts += t.stackTraceToString()
            }
            texts += hostileStatus.toString() + status.read().toString()
        } finally {
            System.setOut(oldOut)
            System.setErr(oldErr)
        }
        texts += out.toString()
        texts += err.toString()
        for (t in texts) assertFalse(t, t.contains(canary))
        for (f in dir.listFiles()!! + File(statusDir, "capture").listFiles().orEmpty()) {
            assertFalse(String(f.readBytes(), Charsets.ISO_8859_1).contains(canary))
        }
    }
}
