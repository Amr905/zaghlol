package app.zaghlol.platform.share

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class ShareStoreTest {
    private lateinit var dir: File
    private var now = 1_700_000_000_000L
    private var counter = 0

    @Before
    fun setUp() {
        dir = Files.createTempDirectory("share-store").toFile()
    }

    @After
    fun tearDown() {
        dir.deleteRecursively()
    }

    private fun newStore(cipher: ShareCipher = SoftwareShareCipher()) = ShareStore(
        dir,
        cipher,
        clock = { now },
        newId = { "%012x".format(now) + "%016x".format(++counter) },
    )

    private fun put(store: ShareStore, text: String): ShareDescriptor {
        val w = store.newWriter()
        val bytes = text.toByteArray()
        w.write(bytes, 0, bytes.size)
        return w.commit(ShareKind.TEXT, "text/plain")
    }

    @Test
    fun listsOldestFirst() {
        val store = newStore()
        val a = put(store, "a")
        now += 1000
        val b = put(store, "b")
        assertEquals(listOf(a.id, b.id), store.list().map { it.id })
    }

    @Test
    fun discardIsIdempotentAndRemovesBothFiles() {
        val store = newStore()
        val a = put(store, "a")
        store.discard(a.id)
        store.discard(a.id)
        assertNoLeftovers(dir)
    }

    @Test
    fun idsThatCouldEscapeTheDirectoryAreRefused() {
        val store = newStore()
        assertThrows(ShareStore.NotFound::class.java) { store.read("../../etc/passwd") }
        assertThrows(ShareStore.NotFound::class.java) { store.discard("..") }
        assertThrows(ShareStore.NotFound::class.java) { store.read("0".repeat(28)) }
    }

    @Test
    fun purgesStaleSharesOrphansAndTempFiles() {
        val store = newStore()
        val old = put(store, "old")
        File(dir, "orphan.bin").writeText("x")
        File(dir, "leftover.bin.tmp").writeText("x")
        val past = now - ShareLimits.STALE_AFTER_MS - 1000
        dir.listFiles()!!.forEach { it.setLastModified(past) }
        now += 10
        val fresh = put(store, "fresh")
        val ids = store.list().map { it.id }
        assertEquals(listOf(fresh.id), ids)
        assertFalse(File(dir, "${old.id}.bin").exists())
        assertFalse(File(dir, "orphan.bin").exists())
        assertFalse(File(dir, "leftover.bin.tmp").exists())
    }

    @Test
    fun filesOnDiskHoldNoPlaintext() {
        val store = newStore()
        put(store, "SYNTHETIC-SECRET-TEXT")
        for (bytes in dir.allBytes()) {
            assertFalse(bytes.contains("SYNTHETIC-SECRET-TEXT".toByteArray()))
            assertFalse(bytes.contains("text/plain".toByteArray()))
        }
    }

    @Test
    fun tamperedFilesFailToDecryptAndAreDeleted() {
        val store = newStore()
        val a = put(store, "payload")
        val body = File(dir, "${a.id}.bin")
        val bytes = body.readBytes()
        bytes[bytes.size - 1] = (bytes[bytes.size - 1].toInt() xor 0x01).toByte()
        body.writeBytes(bytes)
        assertThrows(ShareStore.DecryptFailed::class.java) { store.read(a.id) }
        assertNoLeftovers(dir)
    }

    @Test
    fun aDifferentKeyCannotReadTheStore() {
        val a = put(newStore(), "payload")
        val other = newStore(SoftwareShareCipher(ByteArray(32) { 99 }))
        assertTrue(other.list().isEmpty())
        assertThrows(ShareStore.DecryptFailed::class.java) { other.read(a.id) }
    }

    @Test
    fun abortedWritesLeaveNothing() {
        val store = newStore()
        val w = store.newWriter()
        w.write(ByteArray(10), 0, 10)
        w.abort()
        assertNoLeftovers(dir)
    }

    @Test
    fun hostMapsErrorsToContractCodesAndTakesRejectionOnce() {
        val store = newStore()
        val host = ShareIntakeHost(store)
        val missing = assertThrows(ShareIntakeApiError::class.java) { host.readShare("0".repeat(28)) }
        assertEquals("IO_ERROR", missing.code)

        val a = put(store, "payload")
        File(dir, "${a.id}.bin").writeBytes(ByteArray(64))
        val broken = assertThrows(ShareIntakeApiError::class.java) { host.readShare(a.id) }
        assertEquals("SPOOL_DECRYPT_FAILED", broken.code)

        host.discardShare("not-an-id")
        ShareIntakeState.setRejected(ShareRejectReason.TOO_LARGE)
        assertEquals(ShareRejectReason.TOO_LARGE, host.takePendingRejection())
        assertEquals(null, host.takePendingRejection())
    }
}
