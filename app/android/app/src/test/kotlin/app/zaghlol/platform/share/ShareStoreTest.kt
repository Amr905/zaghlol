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

    private fun newStore(
        cipher: ShareCipher = SoftwareShareCipher(),
        maxPending: Int = ShareLimits.MAX_PENDING_SHARES,
        maxBytes: Long = ShareLimits.MAX_PENDING_BYTES,
    ) = ShareStore(
        dir,
        cipher,
        clock = { now },
        newId = { "%012x".format(now) + "%016x".format(++counter) },
        maxPending = maxPending,
        maxBytes = maxBytes,
    )

    private fun put(store: ShareStore, text: String, kind: ShareKind = ShareKind.TEXT): ShareDescriptor {
        val w = store.newWriter(kind, if (kind == ShareKind.TEXT) "text/plain" else "text/csv")
        val bytes = text.toByteArray()
        w.write(bytes, 0, bytes.size)
        return w.commit()
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
        val w = store.newWriter(ShareKind.IMAGE, "image/png")
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

    // ---- F6: delete only on proof ----

    @Test
    fun aTransientDecryptFailureKeepsTheShare() {
        val flaky = FlakyShareCipher(failures = 0) { java.security.ProviderException("keystore busy") }
        val store = newStore(flaky)
        val a = put(store, "payload")
        flaky.failures = 1
        assertThrows(ShareStore.Transient::class.java) { store.read(a.id) }
        assertTrue(File(dir, "${a.id}.bin").exists())
        assertTrue(File(dir, "${a.id}.meta").exists())
        assertEquals("payload", store.read(a.id).text)
    }

    @Test
    fun aKeystoreGeneralSecurityExceptionIsTransientToo() {
        val flaky = FlakyShareCipher(failures = 0) { java.security.InvalidKeyException("not now") }
        val store = newStore(flaky)
        val a = put(store, "payload")
        flaky.failures = 2 // meta and body attempts in two reads
        assertThrows(ShareStore.Transient::class.java) { store.read(a.id) }
        assertThrows(ShareStore.Transient::class.java) { store.read(a.id) }
        assertEquals("payload", store.read(a.id).text)
    }

    @Test
    fun hostMapsATransientFailureToIoErrorAndKeepsTheShare() {
        val flaky = FlakyShareCipher(failures = 0) { java.security.ProviderException("keystore busy") }
        val store = newStore(flaky)
        val host = ShareIntakeHost(store)
        val a = put(store, "payload")
        flaky.failures = 1
        assertEquals("IO_ERROR", assertThrows(ShareIntakeApiError::class.java) { host.readShare(a.id) }.code)
        assertEquals(listOf(a.id), host.listPendingShares().map { it.id })
    }

    @Test
    fun aTruncatedFileIsProvenBadAndDeleted() {
        val store = newStore()
        val a = put(store, "payload")
        File(dir, "${a.id}.bin").writeBytes(ByteArray(5))
        assertThrows(ShareStore.DecryptFailed::class.java) { store.read(a.id) }
        assertNoLeftovers(dir)
    }

    // ---- F11: AAD binds files to id and kind ----

    @Test
    fun aBodyMovedToAnotherShareFailsAuthentication() {
        val store = newStore()
        val a = put(store, "first")
        now += 1
        val b = put(store, "second")
        File(dir, "${a.id}.bin").copyTo(File(dir, "${b.id}.bin"), overwrite = true)
        assertThrows(ShareStore.DecryptFailed::class.java) { store.read(b.id) }
        assertEquals("first", store.read(a.id).text)
    }

    @Test
    fun aMetaMovedToAnotherShareFailsAuthentication() {
        val store = newStore()
        val a = put(store, "first")
        now += 1
        val b = put(store, "second", kind = ShareKind.CSV)
        File(dir, "${a.id}.meta").copyTo(File(dir, "${b.id}.meta"), overwrite = true)
        assertThrows(ShareStore.DecryptFailed::class.java) { store.read(b.id) }
    }

    @Test
    fun aadDiffersByRoleIdAndKind() {
        val id = "0".repeat(28)
        val other = "1".repeat(28)
        val all = listOf(
            ShareStore.metaAad(id),
            ShareStore.metaAad(other),
            ShareStore.bodyAad(id, ShareKind.TEXT),
            ShareStore.bodyAad(id, ShareKind.IMAGE),
            ShareStore.bodyAad(other, ShareKind.TEXT),
        ).map { String(it) }
        assertEquals(all.size, all.toSet().size)
    }

    // ---- F2: caps ----

    @Test
    fun theCountCapIncludesWritesInProgress() {
        val store = newStore(maxPending = 2)
        put(store, "a")
        val inProgress = store.newWriter(ShareKind.TEXT, "text/plain")
        assertThrows(ShareStore.Full::class.java) { store.newWriter(ShareKind.TEXT, "text/plain") }
        inProgress.abort()
        put(store, "b")
        assertThrows(ShareStore.Full::class.java) { store.ensureCapacity() }
    }

    @Test
    fun theByteCapStopsAWriteMidwayAndAbortCleansUp() {
        val store = newStore(maxBytes = 1_000)
        val w = store.newWriter(ShareKind.PDF, "application/pdf")
        w.write(ByteArray(900), 0, 900)
        assertThrows(ShareStore.Full::class.java) { w.write(ByteArray(200), 0, 200) }
        w.abort()
        assertNoLeftovers(dir)
    }

    @Test
    fun staleSharesDoNotCountAgainstTheCaps() {
        val store = newStore(maxPending = 1)
        put(store, "old")
        dir.listFiles()!!.forEach { it.setLastModified(now - ShareLimits.STALE_AFTER_MS - 1000) }
        store.ensureCapacity()
    }
}
