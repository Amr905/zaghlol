package app.zaghlol.platform.spool

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.io.IOException

class SpoolStoreTest {
    private fun written(r: SpoolStore.WriteResult) = (r as SpoolStore.WriteResult.Written).id

    private fun refused(r: SpoolStore.WriteResult) = (r as SpoolStore.WriteResult.Refused).reason

    @Test
    fun roundTripAndOldestFirst() {
        val dir = tempDir()
        val store = storeIn(dir)
        val ids = (1..5).map { store.put("m$it") }
        assertEquals(ids, store.pendingIds())
        assertEquals(ids.sorted(), ids)
        val r = store.read(ids[2]) as SpoolStore.ReadResult.Ok
        assertEquals("m3", r.record.body)
        assertTrue(dir.listFiles()!!.all { SpoolStore.isEntryName(it.name) })
    }

    // AC1 (simulated): a new store over the same directory reads every entry.
    @Test
    fun entriesSurviveANewStoreInstance() {
        val dir = tempDir()
        val gen = UlidGenerator() // one per process in production: same-millisecond ids stay ordered
        val ids = (1..20).map { storeIn(dir, ids = gen).put("m$it") }
        val fresh = storeIn(dir)
        assertEquals(ids, fresh.pendingIds())
        ids.forEachIndexed { i, id -> assertEquals("m${i + 1}", (fresh.read(id) as SpoolStore.ReadResult.Ok).record.body) }
    }

    // AC1: a fault at any write step leaves a complete decryptable entry or none; never a partial .bin.
    @Test
    fun aFaultAtEveryWriteStepLeavesAllOrNothing() {
        for (step in listOf(FileStep.OPEN, FileStep.WRITE, FileStep.PARTIAL_WRITE, FileStep.SYNC, FileStep.MOVE)) {
            val dir = tempDir()
            val good = storeIn(dir).put("before")
            val ops = FaultyFileOps(step)
            try {
                storeIn(dir, files = ops).write(record(body = "faulted"), AdmissionClass.PRIORITY)
                fail("$step: no error")
            } catch (_: IOException) {
            }
            assertTrue("$step reached", step in ops.steps)
            val fresh = storeIn(dir)
            assertEquals("$step", listOf(good), fresh.pendingIds())
            assertTrue("$step", fresh.read(good) is SpoolStore.ReadResult.Ok)
            assertTrue("$step: tmp left", dir.list()!!.none { it.endsWith(".tmp") })
        }
    }

    @Test
    fun aDirectoryFsyncFailureIsIgnoredAndTheEntryKept() {
        val dir = tempDir()
        val id = written(storeIn(dir, files = FaultyFileOps(FileStep.SYNC_DIR)).write(record(), AdmissionClass.PRIORITY))
        assertTrue(storeIn(dir).read(id) is SpoolStore.ReadResult.Ok)
    }

    @Test
    fun anEncryptionFailureWritesNothing() {
        val dir = tempDir()
        try {
            storeIn(dir, cipher = FlakySpoolCipher(0, failEncrypt = true)).write(record(), AdmissionClass.PRIORITY)
            fail("no error")
        } catch (_: IllegalStateException) {
        }
        assertEquals(0, dir.list()!!.size)
    }

    // AC2: the AAD binds the name; a renamed entry is deleted only on proof after the ladder.
    @Test
    fun swappedFileFailsAadAndIsDeletedOnlyAfterTheRetrySchedule() {
        val dir = tempDir()
        val sleep = RecordingSleep()
        val cipher = SoftwareSpoolCipher()
        val store = storeIn(dir, cipher, sleep)
        val a = store.put("a")
        val b = store.put("b")
        File(dir, "$a.bin").copyTo(File(dir, "$b.bin"), overwrite = true)
        assertEquals(SpoolStore.ReadResult.Deleted, store.read(b))
        assertEquals(listOf(100L, 300L, 900L), sleep.calls)
        assertEquals(4, cipher.decrypts)
        assertFalse(File(dir, "$b.bin").exists())
        assertTrue(store.read(a) is SpoolStore.ReadResult.Ok)
    }

    // AC2: another key fails authentication.
    @Test
    fun anotherKeyFailsAuthentication() {
        val dir = tempDir()
        val id = storeIn(dir).put("x")
        val sleep = RecordingSleep()
        assertEquals(SpoolStore.ReadResult.Deleted, storeIn(dir, otherKeyCipher(), sleep).read(id))
        assertEquals(3, sleep.calls.size)
    }

    // AC2: no canary in the entry bytes (UTF-8, UTF-16LE/BE) or names.
    @Test
    fun noPlaintextOnDisk() {
        val dir = tempDir()
        val store = storeIn(dir)
        val canary = "ZG_CANARY_7731"
        store.write(record(body = "$canary EGP 999.99 خصم", source = "5550100"), AdmissionClass.PRIORITY)
        store.write(record(body = canary.repeat(200), source = canary), AdmissionClass.GENERIC)
        for (f in dir.listFiles()!!) {
            val bytes = f.readBytes()
            for (cs in listOf(Charsets.UTF_8, Charsets.UTF_16LE, Charsets.UTF_16BE)) {
                val hay = String(bytes, Charsets.ISO_8859_1)
                val needle = String(canary.toByteArray(cs), Charsets.ISO_8859_1)
                assertFalse("$cs", hay.contains(needle))
                assertFalse(hay.contains(String("5550100".toByteArray(cs), Charsets.ISO_8859_1)))
                assertFalse(hay.contains(String("خصم".toByteArray(cs), Charsets.ISO_8859_1)))
            }
            assertFalse(f.name.contains("CANARY"))
        }
    }

    @Test
    fun truncatedEntryIsDeletedAfterRetries() {
        val dir = tempDir()
        val sleep = RecordingSleep()
        val store = storeIn(dir, sleep = sleep, keyCreatedAtMs = { Long.MAX_VALUE })
        val id = store.put()
        val f = File(dir, "$id.bin")
        f.writeBytes(f.readBytes().copyOf(20))
        assertEquals(SpoolStore.ReadResult.Deleted, store.read(id))
        // Truncation is not lost-key evidence even when the entry predates the key: ladder.
        assertEquals(3, sleep.calls.size)
        assertEquals(emptyList<String>(), store.pendingIds())
    }

    @Test
    fun transientCipherErrorKeepsTheEntry() {
        val dir = tempDir()
        val cipher = FlakySpoolCipher(failures = 100)
        val store = storeIn(dir, cipher)
        val id = store.put()
        assertTrue(store.read(id) is SpoolStore.ReadResult.Unavailable)
        assertTrue(File(dir, "$id.bin").exists())
        cipher.failures = 0
        assertTrue(store.read(id) is SpoolStore.ReadResult.Ok)
    }

    /** FileNotFoundException that is not "absent" (EACCES, EMFILE, EISDIR) proves nothing: kept, not Missing. */
    @Test
    fun anEntryThatCannotBeOpenedIsUnavailableNotMissingOrDeleted() {
        val dir = tempDir()
        val sleep = RecordingSleep()
        val store = storeIn(dir, sleep = sleep)
        val id = UlidGenerator().next()
        val blocker = File(dir, "$id.bin").apply { mkdirs() }
        File(blocker, "keep").writeText("x")
        assertEquals(listOf(id), store.pendingIds())
        assertTrue(store.read(id) is SpoolStore.ReadResult.Unavailable)
        assertEquals(listOf(100L, 300L, 900L), sleep.calls)
        assertTrue(File(blocker, "keep").exists())
        blocker.deleteRecursively()
        assertEquals(SpoolStore.ReadResult.Missing, store.read(id))
    }

    @Test
    fun oneTransientAttemptAmongProofsKeepsTheEntry() {
        val dir = tempDir()
        val cipher = FlakySpoolCipher(failures = 1)
        val store = storeIn(dir, cipher)
        val id = store.put()
        val f = File(dir, "$id.bin")
        f.writeBytes(f.readBytes().copyOf(40)) // bad, but the first attempt is "transient"
        assertTrue(store.read(id) is SpoolStore.ReadResult.Unavailable)
        assertTrue(f.exists())
    }

    // Key (section 2): an entry older than the current key that fails the tag is deleted at once.
    @Test
    fun staleKeyEntryIsDeletedWithoutTheLadderAndReported() {
        val dir = tempDir()
        var wall = 1_700_000_000_000L
        val writer = storeIn(dir, wall = { wall })
        val old = writer.put("old")
        wall += 5_000
        val sleep = RecordingSleep()
        val status = statusIn(tempDir(), wall = { 42L })
        val reader = storeIn(dir, otherKeyCipher(), sleep, status = status, keyCreatedAtMs = { wall - 1_000 }, wall = { wall })
        assertEquals(SpoolStore.ReadResult.Deleted, reader.read(old))
        assertEquals(emptyList<Long>(), sleep.calls)
        assertEquals(wall, status.read().keyInvalidatedAtMs)
        assertFalse(File(dir, "$old.bin").exists())
    }

    @Test
    fun entryNewerThanTheKeyOrUnknownCreationTakesTheLadder() {
        for (created in listOf<Long?>(null, 0L)) {
            val dir = tempDir()
            val id = storeIn(dir).put("x")
            val sleep = RecordingSleep()
            val status = statusIn(tempDir())
            val r = storeIn(dir, otherKeyCipher(), sleep, status = status, keyCreatedAtMs = { created }).read(id)
            assertEquals(SpoolStore.ReadResult.Deleted, r)
            assertEquals("$created", 3, sleep.calls.size)
            assertEquals(-1L, status.read().keyInvalidatedAtMs)
        }
    }

    @Test
    fun aKeyCreationDateErrorTakesTheLadder() {
        val dir = tempDir()
        val id = storeIn(dir).put("x")
        val sleep = RecordingSleep()
        storeIn(dir, otherKeyCipher(), sleep, keyCreatedAtMs = { throw IllegalStateException("ks") }).read(id)
        assertEquals(3, sleep.calls.size)
    }

    @Test
    fun aTransientErrorOnAStaleEntryDeletesNothing() {
        val dir = tempDir()
        val id = storeIn(dir).put("x")
        val r = storeIn(dir, FlakySpoolCipher(100), keyCreatedAtMs = { Long.MAX_VALUE }).read(id)
        assertTrue(r is SpoolStore.ReadResult.Unavailable)
        assertTrue(File(dir, "$id.bin").exists())
    }

    // Admission (section 4, L-3).
    @Test
    fun the500thIsWrittenAndThe501stRefusedFullNeverEvicting() {
        val dir = tempDir()
        val status = statusIn(tempDir())
        val store = storeIn(dir, status = status)
        val ids = (1..500).map { store.put("m$it") }
        assertEquals(RefusalReason.FULL, refused(store.write(record(body = "new"), AdmissionClass.PRIORITY)))
        assertEquals(ids, store.pendingIds())
        assertEquals(1L, status.read().refusedFull)
        assertTrue(status.read().firstMissedSmsAtMs > 0)
    }

    @Test
    fun byteCapRefusesNew() {
        val dir = tempDir()
        val store = storeIn(dir, limits = SpoolLimits(maxBytes = 200))
        store.put("x".repeat(50))
        assertEquals(RefusalReason.FULL, refused(store.write(record(body = "y".repeat(100)), AdmissionClass.PRIORITY)))
        assertEquals(1, store.pendingCount())
    }

    @Test
    fun tmpFilesCountTowardsTheCaps() {
        val dir = tempDir()
        val store = storeIn(dir, limits = SpoolLimits(maxEntries = 2))
        store.put()
        File(dir, "01ARZ3NDEKTSV4RRFFQ69G5FAV.bin.tmp").writeText("x")
        assertEquals(RefusalReason.FULL, refused(store.write(record(), AdmissionClass.PRIORITY)))
    }

    @Test
    fun genericIsRefusedAtHalfTheEntriesWhilePriorityIsStillWritten() {
        val dir = tempDir()
        val status = statusIn(tempDir())
        val clock = FakeClock()
        val store = storeIn(dir, status = status, mono = clock.fn)
        repeat(250) {
            store.put("p$it")
        }
        assertEquals(RefusalReason.GENERIC_BUDGET, refused(store.write(record(), AdmissionClass.GENERIC)))
        store.put("priority still fits")
        assertEquals(251, store.pendingCount())
        assertEquals(1L, status.read().refusedGeneric)
    }

    @Test
    fun genericIsRefusedAtHalfTheBytes() {
        val dir = tempDir()
        val store = storeIn(dir, limits = SpoolLimits(maxBytes = 2_000, genericMaxBytes = 1_000))
        store.put("x".repeat(900))
        assertEquals(RefusalReason.GENERIC_BUDGET, refused(store.write(record(body = "y".repeat(200)), AdmissionClass.GENERIC)))
        assertTrue(store.write(record(body = "y".repeat(200)), AdmissionClass.PRIORITY) is SpoolStore.WriteResult.Written)
    }

    @Test
    fun the11thGenericInAMinuteIsRefusedAndTheWindowSlides() {
        val dir = tempDir()
        val clock = FakeClock()
        val status = statusIn(tempDir())
        val store = storeIn(dir, status = status, mono = clock.fn)
        repeat(10) {
            store.put("g$it", AdmissionClass.GENERIC)
            clock.now += 1_000
        }
        assertEquals(RefusalReason.GENERIC_RATE, refused(store.write(record(), AdmissionClass.GENERIC)))
        store.put("priority is not rate limited")
        clock.now += 50_000 // the first generic write is now 60 s old
        assertTrue(store.write(record(), AdmissionClass.GENERIC) is SpoolStore.WriteResult.Written)
        assertEquals(1L, status.read().refusedGeneric)
        assertEquals(12, store.pendingCount())
    }

    @Test
    fun aRefusedNotificationIsCountedAsMissed() {
        val dir = tempDir()
        val status = statusIn(tempDir())
        val store = storeIn(dir, status = status, limits = SpoolLimits(maxEntries = 0))
        store.write(record(channel = "notification"), AdmissionClass.PRIORITY)
        val s = status.read()
        assertEquals(1L, s.missedNotifications)
        assertEquals(-1L, s.firstMissedSmsAtMs)
    }

    @Test
    fun ackIsIdempotentAndIgnoresForeignIds() {
        val dir = tempDir()
        val store = storeIn(dir)
        val id = store.put()
        assertEquals(1, store.ack(listOf(id, "../../etc/passwd", "nope")))
        assertEquals(0, store.ack(listOf(id)))
        assertEquals(SpoolStore.ReadResult.Missing, store.read(id))
    }

    @Test
    fun foreignFilesAreIgnored() {
        val dir = tempDir()
        val store = storeIn(dir)
        File(dir, "notes.txt").writeText("x")
        File(dir, "01ARZ3NDEKTSV4RRFFQ69G5FAV.bin.bak").writeText("x")
        File(dir, "zzzzzzzzzzzzzzzzzzzzzzzzzz.bin").writeText("x")
        val id = store.put()
        assertEquals(listOf(id), store.pendingIds())
    }

    // Section 7: every spool .tmp is swept regardless of age; entries and foreign files stay.
    @Test
    fun sweepRemovesEveryTmpButNotEntriesOrForeignFiles() {
        val dir = tempDir()
        val store = storeIn(dir)
        val id = store.put()
        val future = File(dir, "01ARZ3NDEKTSV4RRFFQ69G5FAV.bin.tmp").apply { writeText("x"); setLastModified(System.currentTimeMillis() + 86_400_000) }
        val fresh = File(dir, "01ARZ3NDEKTSV4RRFFQ69G5FAW.bin.tmp").apply { writeText("x") }
        val foreign = File(dir, "other.tmp").apply { writeText("x") }
        assertEquals(2, store.sweepTmp())
        assertFalse(future.exists())
        assertFalse(fresh.exists())
        assertTrue(foreign.exists())
        assertEquals(listOf(id), store.pendingIds())
    }

    @Test
    fun ulidTimeRoundTrips() {
        val id = UlidGenerator(clock = { 1_731_300_000_123L }).next()
        assertEquals(1_731_300_000_123L, UlidGenerator.timeMs(id))
    }
}
