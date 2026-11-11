package app.zaghlol.platform.spool

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** T-041 (FU-105): held entries, and the drain-side store changes of FU-104 #2/#8. */
class SpoolHeldTest {
    private val dir = tempDir()
    private val store = storeIn(dir)
    private val heldDir = File(dir, SpoolStore.HELD_DIR)

    @Test
    fun holdRenamesTheSameBytesAndTheEntryIsNoLongerPending() {
        val a = store.put("a")
        val b = store.put("b")
        val bytes = File(dir, "$a.bin").readBytes()
        assertTrue(store.hold(a))
        assertEquals(listOf(b), store.pendingIds())
        assertEquals(1, store.pendingCountOrNull())
        assertEquals(1, store.heldCount())
        assertFalse(File(dir, "$a.bin").exists())
        assertArrayEquals(bytes, File(heldDir, "$a.bin").readBytes())
    }

    @Test
    fun heldEntriesCountTowardsTheCaps() {
        val small = storeIn(dir, limits = SpoolLimits(maxEntries = 2))
        val a = small.put("a")
        assertTrue(small.hold(a))
        small.put("b")
        val r = small.write(record(body = "c"), AdmissionClass.PRIORITY)
        assertTrue("held + pending = 2 = cap", r is SpoolStore.WriteResult.Refused)
    }

    @Test
    fun heldBytesCountTowardsTheByteCap() {
        val one = File(dir, "${store.put("a")}.bin").length()
        val small = storeIn(dir, limits = SpoolLimits(maxBytes = one * 2 - 1))
        assertTrue(small.hold(small.pendingIds()[0]))
        assertTrue(small.write(record(body = "a"), AdmissionClass.PRIORITY) is SpoolStore.WriteResult.Refused)
    }

    @Test
    fun overTheHeldCapTheEntryStaysPending() {
        val capped = storeIn(dir, limits = SpoolLimits(maxHeld = 1))
        val a = capped.put("a")
        val b = capped.put("b")
        assertTrue(capped.hold(a))
        assertFalse(capped.hold(b))
        assertEquals(listOf(b), capped.pendingIds())
        assertEquals(1, capped.heldCount())
        assertEquals(50, SpoolPolicy.MAX_HELD)
    }

    @Test
    fun invalidOrMissingIdsAreNotHeld() {
        assertFalse(store.hold("../x"))
        assertFalse(store.hold(UlidGenerator().next()))
        assertEquals(0, store.heldCount())
    }

    @Test
    fun releaseOnlyWhenTheAppVersionChanged() {
        val a = store.put("a")
        assertTrue(store.hold(a))
        // First start with held entries and no version file: released (non-destructive).
        assertEquals(1, store.releaseHeldIfVersionChanged(7))
        assertEquals(listOf(a), store.pendingIds())
        assertEquals("7", File(heldDir, SpoolStore.HELD_VERSION_FILE).readText())
        assertTrue(store.hold(a))
        assertEquals("same version: stays held", 0, store.releaseHeldIfVersionChanged(7))
        assertEquals(emptyList<String>(), store.pendingIds())
        assertEquals(1, store.releaseHeldIfVersionChanged(8))
        assertEquals(listOf(a), store.pendingIds())
        // Same bytes and AAD: still readable after the round trip.
        assertEquals("a", (store.read(a) as SpoolStore.ReadResult.Ok).record.body)
        assertEquals("8", File(heldDir, SpoolStore.HELD_VERSION_FILE).readText())
    }

    @Test
    fun releaseWithoutHeldDirectoryDoesNothing() {
        assertEquals(0, store.releaseHeldIfVersionChanged(3))
        assertFalse(heldDir.exists())
    }

    @Test
    fun heldEntriesAreNeverDrainedOrSweptAndTmpCleanupLeavesThem() {
        val a = store.put("a")
        assertTrue(store.hold(a))
        store.sweepTmp()
        assertTrue(File(heldDir, "$a.bin").exists())
        assertEquals(emptyList<String>(), store.pendingIds())
    }

    @Test
    fun pendingCountOrNullTellsAbsentFromUnknown() {
        assertEquals(0, storeIn(File(dir, "never-created")).pendingCountOrNull())
        val notADir = File(dir, "file").apply { writeText("x") }
        assertNull("listing a non-directory proves nothing", storeIn(notADir).pendingCountOrNull())
    }

    @Test
    fun unavailableTellsKeyFailuresFromFileFailures() {
        val flaky = FlakySpoolCipher(failures = 100)
        val keyStore = storeIn(dir, flaky)
        val id = keyStore.put()
        assertTrue((keyStore.read(id) as SpoolStore.ReadResult.Unavailable).keyRelated)
        val other = UlidGenerator().next()
        File(dir, "$other.bin").mkdirs() // can't be opened: a file problem
        assertFalse((storeIn(dir).read(other) as SpoolStore.ReadResult.Unavailable).keyRelated)
    }

    @Test
    fun drainScopeCollectsInsteadOfWritingTheStatus() {
        val statusDir = tempDir()
        val status = statusIn(statusDir)
        var wall = 1_700_000_000_000L
        val old = storeIn(dir, otherKeyCipher(), wall = { wall }).put("old")
        wall += 10_000
        val s = storeIn(dir, status = status, keyCreatedAtMs = { wall - 1 }, wall = { wall })
        val scope = SpoolStore.DrainScope()
        assertEquals(SpoolStore.ReadResult.Deleted, s.read(old, scope))
        assertEquals(1, scope.decryptDeleted)
        assertEquals(wall, scope.keyInvalidatedAtMs)
        assertFalse("nothing written yet", File(statusDir, "capture/status.bin").exists())
        status.recordDrain(scope)
        val st = status.read()
        assertEquals(1L, st.decryptDeleted)
        assertEquals(wall, st.keyInvalidatedAtMs)
    }
}
