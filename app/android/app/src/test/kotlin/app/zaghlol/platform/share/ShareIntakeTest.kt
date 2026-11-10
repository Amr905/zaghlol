package app.zaghlol.platform.share

import java.io.File
import java.io.IOException
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class ShareIntakeTest {
    private lateinit var dir: File
    private lateinit var store: ShareStore
    private lateinit var intake: ShareIntake

    @Before
    fun setUp() {
        dir = Files.createTempDirectory("share-test").toFile()
        store = ShareStore(dir, SoftwareShareCipher())
        intake = ShareIntake(store, "app.zaghlol")
    }

    @After
    fun tearDown() {
        dir.deleteRecursively()
    }

    private fun rejected(outcome: ShareOutcome): ShareRejectReason =
        (outcome as ShareOutcome.Rejected).reason

    private fun accepted(outcome: ShareOutcome): ShareDescriptor =
        (outcome as ShareOutcome.Accepted).descriptor

    // ---- text ----

    @Test
    fun sharedTextIsStoredEncryptedAndReadBack() {
        val body = "SYNTHETIC-BANK-SMS you paid EGP 125.50 at TEST MERCHANT"
        val d = accepted(intake.accept(FakeShareSource(intentType = "text/plain", text = body)))
        assertEquals(ShareKind.TEXT, d.kind)
        assertEquals("text/plain", d.mimeType)
        assertEquals(body.toByteArray().size.toLong(), d.sizeBytes)

        val content = store.read(d.id)
        assertEquals(body, content.text)
        assertEquals(null, content.bytes)
        for (bytes in dir.allBytes()) {
            assertFalse("plaintext must not be on disk", bytes.contains("TEST MERCHANT".toByteArray()))
        }
    }

    @Test
    fun blankOrMissingTextIsEmpty() {
        assertEquals(ShareRejectReason.EMPTY, rejected(intake.accept(FakeShareSource(intentType = "text/plain", text = "  \n"))))
        assertEquals(ShareRejectReason.EMPTY, rejected(intake.accept(FakeShareSource(intentType = "text/plain"))))
        assertNoLeftovers(dir)
    }

    @Test
    fun textOverTheCharLimitIsTooLarge() {
        val text = "a".repeat(ShareLimits.TEXT_MAX_CHARS + 1)
        assertEquals(ShareRejectReason.TOO_LARGE, rejected(intake.accept(FakeShareSource(intentType = "text/plain", text = text))))
        val atLimit = "a".repeat(ShareLimits.TEXT_MAX_CHARS)
        accepted(intake.accept(FakeShareSource(intentType = "text/plain", text = atLimit)))
    }

    @Test
    fun extraTextWithANonTextTypeIsUnsupported() {
        assertEquals(
            ShareRejectReason.UNSUPPORTED_TYPE,
            rejected(intake.accept(FakeShareSource(intentType = "application/zip", text = "x"))),
        )
    }

    @Test
    fun textFileMustBeValidUtf8() {
        val good = "synthetic line".toByteArray()
        assertEquals(ShareKind.TEXT, accepted(intake.accept(FakeShareSource.stream("text/plain", good))).kind)
        val bad = byteArrayOf(0x41, 0xC7.toByte(), 0xE1.toByte())
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(FakeShareSource.stream("text/plain", bad))))
    }

    // ---- images and PDFs ----

    @Test
    fun sharedImageIsStoredEncryptedForTheOcrFlow() {
        val image = PNG_HEAD + "SYNTHETIC-PIXELS".toByteArray() + ByteArray(1000) { 7 }
        val d = accepted(intake.accept(FakeShareSource.stream("image/*", image)))
        assertEquals(ShareKind.IMAGE, d.kind)
        assertEquals("image/png", d.mimeType)
        assertEquals(image.size.toLong(), d.sizeBytes)
        assertArrayEquals(image, store.read(d.id).bytes)
        for (bytes in dir.allBytes()) {
            assertFalse(bytes.contains("SYNTHETIC-PIXELS".toByteArray()))
        }
    }

    @Test
    fun imageTypeComesFromTheBytesNotTheDeclaration() {
        val d = accepted(intake.accept(FakeShareSource.stream("image/png", JPEG_HEAD + ByteArray(50))))
        assertEquals("image/jpeg", d.mimeType)
    }

    @Test
    fun gifsAndMislabelledFilesAreRefused() {
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(FakeShareSource.stream("image/gif", GIF_HEAD))))
        assertEquals(
            ShareRejectReason.UNSUPPORTED_TYPE,
            rejected(intake.accept(FakeShareSource.stream("image/png", "MZ-not-an-image-at-all".toByteArray()))),
        )
        assertNoLeftovers(dir)
    }

    @Test
    fun imageOverTheLimitIsTooLargeAndLeavesNothingBehind() {
        val outcome = intake.accept(FakeShareSource.bigStream("image/png", PNG_HEAD, ShareLimits.IMAGE_MAX_BYTES + 1))
        assertEquals(ShareRejectReason.TOO_LARGE, rejected(outcome))
        assertNoLeftovers(dir)
    }

    @Test
    fun imageExactlyAtTheLimitIsAccepted() {
        val d = accepted(intake.accept(FakeShareSource.bigStream("image/png", PNG_HEAD, ShareLimits.IMAGE_MAX_BYTES)))
        assertEquals(ShareLimits.IMAGE_MAX_BYTES, d.sizeBytes)
    }

    @Test
    fun pdfIsAcceptedByMagicAndRefusedOtherwise() {
        val pdf = PDF_HEAD + "synthetic statement".toByteArray()
        val d = accepted(intake.accept(FakeShareSource.stream("application/pdf", pdf)))
        assertEquals(ShareKind.PDF, d.kind)
        assertArrayEquals(pdf, store.read(d.id).bytes)
        assertEquals(
            ShareRejectReason.UNSUPPORTED_TYPE,
            rejected(intake.accept(FakeShareSource.stream("application/pdf", "PK-zip".toByteArray()))),
        )
    }

    @Test
    fun pdfOverTheLimitIsTooLarge() {
        val outcome = intake.accept(FakeShareSource.bigStream("application/pdf", PDF_HEAD, ShareLimits.PDF_MAX_BYTES + 1))
        assertEquals(ShareRejectReason.TOO_LARGE, rejected(outcome))
        assertNoLeftovers(dir)
    }

    @Test
    fun emptyStreamsAreEmpty() {
        assertEquals(ShareRejectReason.EMPTY, rejected(intake.accept(FakeShareSource.stream("image/png", ByteArray(0)))))
        assertEquals(ShareRejectReason.EMPTY, rejected(intake.accept(FakeShareSource.stream("text/csv", ByteArray(0)))))
    }

    // ---- CSV ----

    @Test
    fun csvIsAcceptedAsBytesIncludingLegacyEncodings() {
        val csv = byteArrayOf(0xC7.toByte(), 0xE1.toByte(), 0x2C) + "100.50\n".toByteArray()
        val d = accepted(intake.accept(FakeShareSource.stream("text/csv", csv)))
        assertEquals(ShareKind.CSV, d.kind)
        assertArrayEquals(csv, store.read(d.id).bytes)
    }

    @Test
    fun binaryCsvAndOversizeCsvAreRefused() {
        assertEquals(
            ShareRejectReason.UNSUPPORTED_TYPE,
            rejected(intake.accept(FakeShareSource.stream("text/csv", byteArrayOf(0x41, 0, 0x42)))),
        )
        val outcome = intake.accept(FakeShareSource.bigStream("text/csv", "a,b\n".toByteArray(), ShareLimits.CSV_MAX_BYTES + 1))
        assertEquals(ShareRejectReason.TOO_LARGE, rejected(outcome))
        assertNoLeftovers(dir)
    }

    @Test
    fun providerTypeWinsOverTheIntentType() {
        val source = FakeShareSource(
            intentType = "text/plain",
            streamScheme = "content",
            streamAuthority = "com.example.provider",
            resolverMime = "text/csv",
            opener = { "a,b\n1,2\n".byteInputStream() },
        )
        assertEquals(ShareKind.CSV, accepted(intake.accept(source)).kind)
    }

    // ---- URI and provider safety ----

    @Test
    fun fileUrisAreRefusedSoWeNeverReadOurOwnPrivateFiles() {
        val source = FakeShareSource.stream("image/png", PNG_HEAD + ByteArray(20), scheme = "file", authority = "")
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(source)))
        assertNoLeftovers(dir)
    }

    @Test
    fun ourOwnProvidersAreRefused() {
        for (authority in listOf("app.zaghlol", "app.zaghlol.dev.fileprovider")) {
            val source = FakeShareSource.stream("image/png", PNG_HEAD + ByteArray(20), authority = authority)
            assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(source)))
        }
        // A look-alike authority from another app is fine.
        accepted(intake.accept(FakeShareSource.stream("image/png", PNG_HEAD + ByteArray(20), authority = "app.zaghlolfake.provider")))
    }

    @Test
    fun unsupportedMimeTypesAreRefused() {
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(FakeShareSource.stream("application/zip", ByteArray(20)))))
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(FakeShareSource.stream("application/octet-stream", ByteArray(20)))))
    }

    @Test
    fun unreadableStreamsAreReportedNotThrown() {
        val refused = FakeShareSource(intentType = "image/png", streamScheme = "content", streamAuthority = "x.y", opener = { null })
        assertEquals(ShareRejectReason.UNREADABLE, rejected(intake.accept(refused)))
        val io = FakeShareSource(intentType = "image/png", streamScheme = "content", streamAuthority = "x.y", opener = { throw IOException("boom") })
        assertEquals(ShareRejectReason.UNREADABLE, rejected(intake.accept(io)))
        val sec = FakeShareSource(intentType = "image/png", streamScheme = "content", streamAuthority = "x.y", opener = { throw SecurityException("no grant") })
        assertEquals(ShareRejectReason.UNREADABLE, rejected(intake.accept(sec)))
    }

    @Test
    fun aStreamThatFailsMidCopyLeavesNothingBehind() {
        val source = FakeShareSource(
            intentType = "image/png",
            streamScheme = "content",
            streamAuthority = "x.y",
            opener = {
                object : java.io.InputStream() {
                    var n = 0
                    override fun read(): Int = throw ThrowingStreamException()
                    override fun read(b: ByteArray, off: Int, len: Int): Int {
                        if (n == 0) {
                            n++
                            PNG_HEAD.copyInto(b, off)
                            return PNG_HEAD.size
                        }
                        throw ThrowingStreamException()
                    }
                }
            },
        )
        assertEquals(ShareRejectReason.UNREADABLE, rejected(intake.accept(source)))
        assertNoLeftovers(dir)
    }

    @Test
    fun committedSharesAreListedAndDiscardable() {
        val a = accepted(intake.accept(FakeShareSource(intentType = "text/plain", text = "one")))
        assertTrue(store.list().any { it.id == a.id })
        store.discard(a.id)
        assertTrue(store.list().isEmpty())
        assertNoLeftovers(dir)
    }
}
