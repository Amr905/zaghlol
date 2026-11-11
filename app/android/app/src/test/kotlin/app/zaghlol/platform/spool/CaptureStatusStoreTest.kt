package app.zaghlol.platform.spool

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.io.IOException

class CaptureStatusStoreTest {
    private fun file(dir: File) = File(dir, "capture/status.bin")

    @Test
    fun absentFileReadsAsZeroAndWritesNothing() {
        val dir = tempDir()
        assertEquals(CaptureStatus(), statusIn(dir).read())
        assertFalse(File(dir, "capture").exists())
    }

    @Test
    fun alertsPersistAcrossInstances() {
        val dir = tempDir()
        val a = statusIn(dir)
        a.recordRefused(RefusalReason.FULL, "sms", 500)
        a.recordRefused(RefusalReason.GENERIC_RATE, "notification", 400)
        a.recordRateLimited("sms", 300)
        a.recordDecryptDeleted(2)
        a.recordKeyInvalidated(900)
        a.recordKeyInvalidated(800)
        val s = statusIn(dir).read()
        assertEquals(1L, s.refusedFull)
        assertEquals(1L, s.refusedGeneric)
        assertEquals(1L, s.rateLimited)
        assertEquals(1L, s.missedNotifications)
        assertEquals(300L, s.firstMissedSmsAtMs)
        assertEquals(500L, s.lastRefusedAtMs)
        assertEquals(2L, s.decryptDeleted)
        assertEquals(800L, s.keyInvalidatedAtMs)
        assertEquals(6L, s.seq)
    }

    @Test
    fun noWriteWithoutAnAlert() {
        val dir = tempDir()
        val s = statusIn(dir)
        s.recordDecryptDeleted(0)
        s.read()
        assertFalse(File(dir, "capture").exists())
        // A normal spool keep writes the entry only.
        val spool = File(dir, "spool")
        storeIn(spool, status = s).put()
        assertFalse(File(dir, "capture").exists())
        assertEquals(1, spool.list()!!.size)
    }

    @Test
    fun clearWithTheCurrentSeqZeroesAndAdvances() {
        val s = statusIn(tempDir())
        s.recordRefused(RefusalReason.FULL, "sms", 1)
        val seen = s.read()
        assertTrue(s.clear(seen.seq))
        assertEquals(CaptureStatus(seq = seen.seq + 1), s.read())
    }

    @Test
    fun clearWithAStaleSeqIsANoOp() {
        val s = statusIn(tempDir())
        s.recordRefused(RefusalReason.FULL, "sms", 1)
        val seen = s.read()
        s.recordRateLimited("notification", 2) // arrived after Dart read
        assertFalse(s.clear(seen.seq))
        val after = s.read()
        assertEquals(1L, after.refusedFull)
        assertEquals(1L, after.rateLimited)
    }

    @Test
    fun countersSaturateAtU32() {
        val dir = tempDir()
        val cipher = SoftwareSpoolCipher()
        val f = file(dir).apply { parentFile.mkdirs() }
        val max = CaptureStatusStore.U32_MAX
        f.writeBytes(cipher.encrypt(CaptureStatusStore.encode(CaptureStatus(seq = max, decryptDeleted = max)), CaptureStatusStore.AAD))
        val s = statusIn(dir, cipher)
        s.recordDecryptDeleted(5)
        val r = s.read()
        assertEquals(max, r.decryptDeleted)
        assertEquals(0L, r.seq) // seq wraps
    }

    @Test
    fun codecRoundTripsAndIsStrict() {
        val v = CaptureStatus(1, 2, 3, 4, 5, 6, 7, 8, 9)
        val b = CaptureStatusStore.encode(v)
        assertEquals(CaptureStatusStore.RECORD_BYTES, b.size)
        assertEquals(v, CaptureStatusStore.decode(b))
        assertArrayEquals(b, CaptureStatusStore.encode(CaptureStatusStore.decode(b)))
        for (bad in listOf(b.copyOf(b.size - 1), b + 0, b.copyOf().also { it[0] = 2 })) {
            try {
                CaptureStatusStore.decode(bad)
                fail("decoded")
            } catch (_: Exception) {
            }
        }
    }

    // Tag-failed status (lost key) → reset with keyInvalidatedAtMs, after the ladder.
    @Test
    fun aTagFailedStatusIsResetWithKeyInvalidated() {
        val dir = tempDir()
        statusIn(dir, otherKeyCipher()).recordRefused(RefusalReason.FULL, "sms", 1)
        val sleep = RecordingSleep()
        val s = statusIn(dir, SoftwareSpoolCipher(), sleep, wall = { 4242L }, seq = { 99L })
        val r = s.read()
        assertEquals(listOf(100L, 300L, 900L), sleep.calls)
        assertEquals(4242L, r.keyInvalidatedAtMs)
        assertEquals(0L, r.refusedFull)
        assertEquals(99L, r.seq)
        // Persisted: a second read is clean.
        assertEquals(r, statusIn(dir).read())
    }

    @Test
    fun anAlertOnAnUnreadableFileIsKeptAfterTheReset() {
        val dir = tempDir()
        file(dir).apply { parentFile.mkdirs(); writeBytes(ByteArray(5)) }
        val s = statusIn(dir)
        s.recordRateLimited("sms", 10)
        val r = statusIn(dir).read()
        assertEquals(1L, r.rateLimited)
        assertTrue(r.keyInvalidatedAtMs >= 0)
    }

    // Transient read error: never overwrite the unread file; merge later.
    @Test
    fun aTransientReadErrorKeepsTheDeltaInMemoryAndNeverOverwrites() {
        val dir = tempDir()
        statusIn(dir).recordRefused(RefusalReason.FULL, "sms", 1)
        val before = file(dir).readBytes()
        val flaky = FlakySpoolCipher(failures = 1)
        val s = statusIn(dir, flaky)
        s.recordRateLimited("notification", 2) // read fails transiently → kept in memory
        assertArrayEquals(before, file(dir).readBytes())
        val r = s.read() // next successful read merges
        assertEquals(1L, r.refusedFull)
        assertEquals(1L, r.rateLimited)
        assertEquals(1L, r.missedNotifications)
        assertEquals(r, statusIn(dir).read())
    }

    @Test
    fun aTransientReadErrorFailsReadAndClear() {
        val dir = tempDir()
        statusIn(dir).recordRefused(RefusalReason.FULL, "sms", 1)
        val s = statusIn(dir, FlakySpoolCipher(failures = 2))
        try {
            s.read()
            fail("read")
        } catch (_: CaptureStatusUnavailableException) {
        }
        try {
            s.clear(1)
            fail("clear")
        } catch (_: CaptureStatusUnavailableException) {
        }
        assertEquals(1L, statusIn(dir).read().refusedFull)
    }

    @Test
    fun aWriteFailureKeepsTheDeltaWithoutDoubleCounting() {
        val dir = tempDir()
        val ops = FaultyFileOps(FileStep.MOVE)
        val s = statusIn(dir, files = ops)
        s.recordRefused(RefusalReason.FULL, "sms", 1) // write fails at rename
        assertFalse(file(dir).exists())
        assertTrue(File(dir, "capture").list()!!.none { it.endsWith(".tmp") })
        assertEquals(1L, s.read().refusedFull) // persisted now
        assertEquals(1L, statusIn(dir).read().refusedFull)
    }

    /**
     * FileNotFoundException is also EACCES / EMFILE / EISDIR: not proof of
     * absence, so the status is unavailable and nothing is overwritten
     * (a directory in place of the file stands in for "exists, can't open",
     * which works even when the tests run as root).
     */
    @Test
    fun anUnopenableStatusFileIsUnavailableNotAbsent() {
        val dir = tempDir()
        val blocker = file(dir).apply { mkdirs() }
        File(blocker, "keep").writeText("x")
        val s = statusIn(dir)
        s.recordRefused(RefusalReason.FULL, "sms", 1) // kept in memory, nothing written
        try {
            s.read()
            fail("read")
        } catch (_: CaptureStatusUnavailableException) {
        }
        try {
            s.clear(0)
            fail("clear")
        } catch (_: CaptureStatusUnavailableException) {
        }
        assertTrue(blocker.isDirectory)
        assertEquals(listOf("keep"), blocker.list()!!.toList())
        // Once the file can be opened (here: absent), the in-memory alert is merged.
        blocker.deleteRecursively()
        assertEquals(1L, s.read().refusedFull)
    }

    /** A delta whose write failed is part of what the caller cleared; it is not re-added later. */
    @Test
    fun clearDropsAPendingDeltaTheCallerAlreadySaw() {
        val dir = tempDir()
        var failingMoves = 3
        val ops = object : SpoolFileOps by DefaultSpoolFileOps {
            override fun move(from: File, to: File) {
                if (failingMoves-- > 0) throw IOException("rename")
                DefaultSpoolFileOps.move(from, to)
            }
        }
        val s = statusIn(dir, files = ops)
        s.recordRefused(RefusalReason.FULL, "sms", 1) // move 1 fails: delta pending
        val seen = s.read() // move 2 fails: the caller sees the delta under this seq
        assertEquals(1L, seen.refusedFull)
        assertTrue(s.clear(seen.seq)) // move 3 (merge) fails, the clear write succeeds
        assertEquals(0L, s.read().refusedFull)
        assertEquals(0L, statusIn(dir).read().refusedFull)
    }

    @Test
    fun aClearWriteFailureThrows() {
        val dir = tempDir()
        val ops = FaultyFileOps(null)
        val s = statusIn(dir, files = ops)
        s.recordRefused(RefusalReason.FULL, "sms", 1)
        ops.failAt = FileStep.SYNC
        try {
            s.clear(s.read().seq)
            fail("no error")
        } catch (_: IOException) {
        }
        assertEquals(1L, statusIn(dir).read().refusedFull)
    }

    @Test
    fun theFileHoldsNoPlaintext() {
        val dir = tempDir()
        statusIn(dir).recordRefused(RefusalReason.FULL, "sms", 0x0102030405L)
        val bytes = file(dir).readBytes()
        assertEquals(12 + CaptureStatusStore.RECORD_BYTES + 16, bytes.size)
        assertFalse(String(bytes, Charsets.ISO_8859_1).contains("\u0001\u0002\u0003\u0004\u0005"))
    }
}
