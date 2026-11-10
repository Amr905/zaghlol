package app.zaghlol.platform.ocr

import app.zaghlol.platform.share.ShareKind
import app.zaghlol.platform.share.ShareStore
import app.zaghlol.platform.share.SoftwareShareCipher
import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class ImageSealerTest {
    private lateinit var root: File
    private lateinit var cache: File
    private lateinit var storeDir: File
    private lateinit var store: ShareStore
    private var size: ImageSize? = ImageSize(100, 100)
    private val decoder = object : OcrImageDecoder {
        override fun bounds(data: ByteArray) = size
        override fun decode(data: ByteArray, sampleSize: Int): DecodedImage? = null
    }

    @Before
    fun setUp() {
        root = Files.createTempDirectory("ocr-seal").toFile()
        cache = File(root, "cache").apply { mkdirs() }
        storeDir = File(root, "share")
        store = ShareStore(storeDir, SoftwareShareCipher())
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
    }

    private fun sealer() = ShareStoreImageSealer(store, listOf(cache), decoder)

    private fun plain(name: String = "p.jpg", bytes: ByteArray = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 1, 2, 3, 4)): File =
        File(cache, name).also { it.writeBytes(bytes) }

    private fun code(block: () -> Unit): String = try {
        block()
        fail("expected OcrFailure")
        ""
    } catch (e: OcrFailure) {
        e.code
    }

    @Test
    fun sealsIntoTheEncryptedStoreAndDeletesThePlainFile() {
        val bytes = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 9, 8, 7, 6)
        val f = plain(bytes = bytes)
        val id = sealer().seal(f.path)
        assertFalse(f.exists())
        val content = store.read(id)
        assertEquals(ShareKind.IMAGE, content.descriptor.kind)
        assertEquals("image/jpeg", content.descriptor.mimeType)
        assertArrayEquals(bytes, content.bytes)
        // The bytes on disk are ciphertext only.
        val onDisk = storeDir.listFiles()!!.filter { it.name.endsWith(".bin") }.single().readBytes()
        assertFalse(onDisk.toList().windowed(bytes.size).any { it == bytes.toList() })
    }

    @Test
    fun aPathOutsideTheCacheIsRefusedAndNotDeleted() {
        val outside = File(root, "outside.jpg").apply { writeBytes(ByteArray(10) { 1 }) }
        assertEquals("IO_ERROR", code { sealer().seal(outside.path) })
        assertTrue(outside.exists())
        // ".." tricks resolve before the check.
        val tricky = File(cache, "../outside.jpg")
        assertEquals("IO_ERROR", code { sealer().seal(tricky.path) })
        assertTrue(outside.exists())
    }

    @Test
    fun aSymlinkOutOfTheCacheIsRefusedAndTheTargetKept() {
        val target = File(root, "target.jpg").apply { writeBytes(ByteArray(10) { 1 }) }
        val link = File(cache, "link.jpg")
        try {
            Files.createSymbolicLink(link.toPath(), target.toPath())
        } catch (_: UnsupportedOperationException) {
            return
        }
        assertEquals("IO_ERROR", code { sealer().seal(link.path) })
        assertTrue(target.exists())
    }

    @Test
    fun emptyOversizedAndNonImageFilesAreRefusedAndDeleted() {
        val empty = plain("e.jpg", ByteArray(0))
        assertEquals("IO_ERROR", code { sealer().seal(empty.path) })
        assertFalse(empty.exists())

        size = null
        val notImage = plain("n.jpg")
        assertEquals("IO_ERROR", code { sealer().seal(notImage.path) })
        assertFalse(notImage.exists())

        size = ImageSize(10_000, 10_000)
        val huge = plain("h.jpg")
        assertEquals("IO_ERROR", code { sealer().seal(huge.path) })
        assertFalse(huge.exists())
        assertTrue(storeDir.listFiles().orEmpty().isEmpty())
    }

    @Test
    fun aMissingFileIsIoError() {
        assertEquals("IO_ERROR", code { sealer().seal(File(cache, "none.jpg").path) })
    }

    @Test
    fun aFullStoreIsIoErrorAndTheStoreKeepsNothing() {
        val full = ShareStore(storeDir, SoftwareShareCipher(), maxPending = 0)
        val f = plain()
        assertEquals("IO_ERROR", code { ShareStoreImageSealer(full, listOf(cache), decoder).seal(f.path) })
        assertFalse(f.exists())
        assertTrue(storeDir.listFiles().orEmpty().isEmpty())
    }

    @Test
    fun theStoreSourceDiscardsAnImageAndNeverThrowsForAnUnknownOne() {
        val id = sealer().seal(plain().path)
        val source = ShareStoreImageSource(store)
        source.discard(id)
        assertEquals("IO_ERROR", code { source.read(id) })
        source.discard(id)
        source.discard("not-an-id")
    }
}
