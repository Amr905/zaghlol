package app.zaghlol.spike.sms

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class SpoolStoreTest {
    private fun written(r: SpoolStore.WriteResult) = (r as SpoolStore.WriteResult.Written).id

    @Test
    fun roundTripAndOldestFirst() {
        val dir = tempDir()
        val store = storeIn(dir)
        val ids = (1..5).map { written(store.write(record(body = "m$it"))) }
        assertEquals(ids, store.pendingIds())
        assertEquals(ids.sorted(), ids)
        val r = store.read(ids[2]) as SpoolStore.ReadResult.Ok
        assertEquals("m3", r.record.body)
        assertTrue(dir.listFiles()!!.all { SpoolStore.isEntryName(it.name) })
    }

    @Test
    fun swappedFileFailsAadAndIsDeletedOnlyAfterTheRetrySchedule() {
        val dir = tempDir()
        val sleep = RecordingSleep()
        val cipher = SoftwareSpoolCipher()
        val store = storeIn(dir, cipher, sleep)
        val a = written(store.write(record(body = "a")))
        val b = written(store.write(record(body = "b")))
        // Put a's ciphertext under b's name: the AAD binds the id, so it must not decrypt.
        File(dir, "$a.bin").copyTo(File(dir, "$b.bin"), overwrite = true)
        assertEquals(SpoolStore.ReadResult.Deleted, store.read(b))
        assertEquals(listOf(100L, 300L, 900L), sleep.calls)
        assertEquals(4, cipher.decrypts)
        assertFalse(File(dir, "$b.bin").exists())
        assertTrue(store.read(a) is SpoolStore.ReadResult.Ok)
    }

    @Test
    fun truncatedEntryIsDeletedAfterRetries() {
        val dir = tempDir()
        val store = storeIn(dir)
        val id = written(store.write(record()))
        val f = File(dir, "$id.bin")
        f.writeBytes(f.readBytes().copyOf(20))
        assertEquals(SpoolStore.ReadResult.Deleted, store.read(id))
        assertEquals(emptyList<String>(), store.pendingIds())
    }

    @Test
    fun transientCipherErrorKeepsTheEntry() {
        val dir = tempDir()
        val cipher = FlakySpoolCipher(failures = 100)
        val store = storeIn(dir, cipher)
        val id = written(store.write(record()))
        assertEquals(SpoolStore.ReadResult.Unavailable, store.read(id))
        assertTrue(File(dir, "$id.bin").exists())
        cipher.failures = 0
        assertTrue(store.read(id) is SpoolStore.ReadResult.Ok)
    }

    @Test
    fun oneTransientAttemptAmongProofsKeepsTheEntry() {
        val dir = tempDir()
        val cipher = FlakySpoolCipher(failures = 1)
        val store = storeIn(dir, cipher)
        val id = written(store.write(record()))
        val f = File(dir, "$id.bin")
        f.writeBytes(f.readBytes().copyOf(20)) // bad, but the first attempt is "transient"
        assertEquals(SpoolStore.ReadResult.Unavailable, store.read(id))
        assertTrue(f.exists())
    }

    @Test
    fun countCapRefusesNewAndNeverEvicts() {
        val dir = tempDir()
        val store = storeIn(dir, maxEntries = 3)
        val ids = (1..3).map { written(store.write(record(body = "m$it"))) }
        assertEquals(SpoolStore.WriteResult.Full, store.write(record(body = "new")))
        assertEquals(ids, store.pendingIds())
    }

    @Test
    fun byteCapRefusesNew() {
        val dir = tempDir()
        val store = storeIn(dir, maxBytes = 200)
        written(store.write(record(body = "x".repeat(50))))
        assertEquals(SpoolStore.WriteResult.Full, store.write(record(body = "y".repeat(100))))
        assertEquals(1, store.pendingCount())
    }

    @Test
    fun ackIsIdempotentAndIgnoresForeignIds() {
        val dir = tempDir()
        val store = storeIn(dir)
        val id = written(store.write(record()))
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
        val id = written(store.write(record()))
        assertEquals(listOf(id), store.pendingIds())
    }

    @Test
    fun staleTmpIsSweptFreshTmpKept() {
        val dir = tempDir()
        var now = 1_000_000_000L
        val store = storeIn(dir, clock = { now })
        val old = File(dir, "01ARZ3NDEKTSV4RRFFQ69G5FAV.bin.tmp").apply { writeText("x"); setLastModified(now - 61_000) }
        val fresh = File(dir, "01ARZ3NDEKTSV4RRFFQ69G5FAW.bin.tmp").apply { writeText("x"); setLastModified(now - 1_000) }
        store.sweepTmp()
        assertFalse(old.exists())
        assertTrue(fresh.exists())
    }

    @Test
    fun noPlaintextOnDisk() {
        val dir = tempDir()
        val store = storeIn(dir)
        val id = written(store.write(record(body = "ZG_CANARY_7731 EGP 999.99", source = "5550100")))
        val bytes = File(dir, "$id.bin").readBytes()
        val latin = String(bytes, Charsets.ISO_8859_1)
        assertFalse(latin.contains("ZG_CANARY"))
        assertFalse(latin.contains("5550100"))
        assertFalse(dir.list()!!.any { it.contains("CANARY") })
    }
}
