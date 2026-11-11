package app.zaghlol.platform.capture

import app.zaghlol.platform.ingest.IngestTrace
import app.zaghlol.platform.spool.DefaultSpoolFileOps
import app.zaghlol.platform.spool.FlakySpoolCipher
import app.zaghlol.platform.spool.SoftwareSpoolCipher
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.SpoolFileOps
import app.zaghlol.platform.spool.SpoolStore
import app.zaghlol.platform.spool.otherKeyCipher
import app.zaghlol.platform.spool.put
import app.zaghlol.platform.spool.statusIn
import app.zaghlol.platform.spool.storeIn
import app.zaghlol.platform.spool.tempDir
import io.flutter.plugin.common.BinaryMessenger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/** T-041: holdSpool (FU-105), the drain scan budget (FU-104 #2) and one status write per drain (FU-104 #8). */
class CaptureHostHoldAndBudgetTest {
    private val dir = tempDir()
    private val statusDir = tempDir()
    private val status = statusIn(statusDir)
    private val store = storeIn(dir, status = status)
    private val claim = SpoolClaim(clock = { 0 })

    private fun host(
        engine: Long,
        s: SpoolStore = store,
        mono: () -> Long = { 0L },
        trace: IngestTrace = IngestTrace.NONE,
    ) = AndroidCaptureHost(engine, s, claim, status, null, null, null, null, { trace }, mono)

    @Test
    fun holdMovesOnlyEntriesThisHostDrainedAndReleasesTheirClaim() {
        val a = store.put("a")
        val ui = host(1)
        assertEquals(listOf(a), ui.drainSpool(10).map { it.id })
        val b = store.put("b") // never drained by ui
        ui.holdSpool(listOf(a, b, "not-a-ulid", "../x"))
        assertEquals(listOf(b), store.pendingIds())
        assertEquals(1, store.heldCount())
        assertEquals(0, ui.ackableCount())
        // The claim is free again: another engine drains b at once.
        assertEquals(listOf(b), host(2).drainSpool(10).map { it.id })
        assertEquals(1L, ui.getSpoolStatus().held)
        assertEquals(1L, ui.getSpoolStatus().pending)
    }

    @Test
    fun anotherEnginesHoldCannotMoveEntriesItNeverReceived() {
        val a = store.put("a")
        host(1).drainSpool(10)
        host(2).holdSpool(listOf(a))
        assertEquals(listOf(a), store.pendingIds())
        assertEquals(0, store.heldCount())
    }

    @Test
    fun holdOfMoreThan100IdsIsIoErrorAndMovesNothing() {
        val a = store.put("a")
        val h = host(1)
        h.drainSpool(10)
        try {
            h.holdSpool(List(101) { a })
            fail("no error")
        } catch (e: CaptureApiError) {
            assertEquals("IO_ERROR", e.code)
        }
        assertEquals(listOf(a), store.pendingIds())
    }

    @Test
    fun aHeldEntryIsNotDrainedAgain() {
        val a = store.put("a")
        val h = host(1)
        h.drainSpool(10)
        h.holdSpool(listOf(a))
        assertEquals(emptyList<SpoolEntry>(), h.drainSpool(10))
    }

    /** FU-104 #2: one Keystore failure stops the scan (no 1.3 s ladder per remaining entry). */
    @Test
    fun theScanStopsAtTheFirstKeyRelatedFailure() {
        val ids = (1..3).map { store.put("m$it") }
        val flaky = FlakySpoolCipher(failures = 4) // the four attempts of the first entry
        val h = host(1, s = storeIn(dir, flaky, status = status))
        assertEquals(emptyList<SpoolEntry>(), h.drainSpool(10))
        assertEquals("only the first entry was tried", 4, flaky.decrypts)
        assertEquals(ids, store.pendingIds())
        assertEquals(ids, h.drainSpool(10).map { it.id })
    }

    @Test
    fun aFileProblemDoesNotStopTheScan() {
        val blocked = app.zaghlol.platform.spool.UlidGenerator(clock = { 1L }).next()
        File(dir, "$blocked.bin").mkdirs() // oldest; can't be opened
        val a = store.put("a")
        assertEquals(listOf(a), host(1).drainSpool(10).map { it.id })
    }

    /** FU-104 #2: the scan returns what it has after 5 s. */
    @Test
    fun theScanStopsAfterItsTimeBudget() {
        val ids = (1..3).map { store.put("m$it") }
        var now = 0L
        val h = host(1, mono = { now.also { now += 2_600 } })
        assertEquals(ids.take(1), h.drainSpool(10).map { it.id })
        assertEquals(5_000L, AndroidCaptureHost.DRAIN_SCAN_BUDGET_MS)
    }

    /** FU-104 #8: three lost-key entries and one corrupt entry → one status write. */
    @Test
    fun alertsAreWrittenOncePerDrain() {
        var wall = 1_700_000_000_000L
        val old = storeIn(dir, otherKeyCipher(), wall = { wall })
        repeat(3) { old.put("old$it") }
        wall += 10_000
        val countingOps = CountingOps()
        val countedStatus = app.zaghlol.platform.spool.statusIn(statusDir, files = countingOps)
        val s = storeIn(dir, SoftwareSpoolCipher(), status = countedStatus, keyCreatedAtMs = { wall - 1 }, wall = { wall })
        val bad = s.put("bad")
        File(dir, "$bad.bin").writeBytes(ByteArray(40))
        val h = AndroidCaptureHost(1, s, claim, countedStatus, null, null, null, null)
        assertEquals(emptyList<SpoolEntry>(), h.drainSpool(10))
        assertEquals("one status write for the whole drain", 1, countingOps.moves)
        val st = h.getSpoolStatus()
        assertEquals(4L, st.decryptDeleted)
        assertEquals(wall, st.keyInvalidatedAtMs)
    }

    @Test
    fun aDrainWithoutAlertsWritesNoStatus() {
        store.put("a")
        val countingOps = CountingOps()
        val countedStatus = app.zaghlol.platform.spool.statusIn(statusDir, files = countingOps)
        AndroidCaptureHost(1, store, claim, countedStatus, null, null, null, null).drainSpool(10)
        assertEquals(0, countingOps.moves)
    }

    @Test
    fun traceGetsIdsAndNumbersOnly() {
        val a = store.put("ZG_CANARY_7731")
        val seen = ArrayList<String>()
        val trace = object : IngestTrace {
            override fun drained(id: String, rxElapsedNs: Long, bootCount: Int) {
                seen += "d:$id:$rxElapsedNs:$bootCount"
            }

            override fun acked(ids: List<String>) {
                seen += "a:$ids"
            }

            override fun engineAttached(messenger: BinaryMessenger) = Unit
        }
        val h = host(1, trace = trace)
        h.drainSpool(10)
        h.ackSpool(listOf(a))
        assertEquals(listOf("d:$a:1000000:7", "a:[$a]"), seen)
        val throwing = object : IngestTrace {
            override fun drained(id: String, rxElapsedNs: Long, bootCount: Int) = throw IllegalStateException("x")
        }
        val b = store.put("b")
        assertEquals("a throwing trace never breaks the drain", listOf(b), host(3, trace = throwing).drainSpool(10).map { it.id })
        assertTrue(seen.none { it.contains("ZG_CANARY") })
    }

    private class CountingOps : SpoolFileOps by DefaultSpoolFileOps {
        var moves = 0

        override fun move(from: File, to: File) {
            moves++
            DefaultSpoolFileOps.move(from, to)
        }
    }
}
