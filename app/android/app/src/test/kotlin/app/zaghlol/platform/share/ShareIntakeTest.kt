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
    private val probe = FakeBoundsProbe()
    private var now = 0L

    @Before
    fun setUp() {
        dir = Files.createTempDirectory("share-test").toFile()
        store = ShareStore(dir, SoftwareShareCipher())
        intake = ShareIntake(store, "app.zaghlol", probe, clock = { now })
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
            streamHost = "com.example.provider",
            resolverMime = "text/csv",
            opener = { "a,b\n1,2\n".byteInputStream() },
        )
        assertEquals(ShareKind.CSV, accepted(intake.accept(source)).kind)
    }

    // ---- URI and provider safety ----

    @Test
    fun fileUrisAreRefusedSoWeNeverReadOurOwnPrivateFiles() {
        val source = FakeShareSource.stream("image/png", PNG_HEAD + ByteArray(20), scheme = "file", host = "")
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(source)))
        assertNoLeftovers(dir)
    }

    @Test
    fun ourOwnProvidersAreRefused() {
        for (host in listOf("app.zaghlol", "app.zaghlol.dev.fileprovider")) {
            val source = FakeShareSource.stream("image/png", PNG_HEAD + ByteArray(20), host = host)
            assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(source)))
        }
        // A look-alike authority from another app is fine.
        accepted(intake.accept(FakeShareSource.stream("image/png", PNG_HEAD + ByteArray(20), host = "app.zaghlolfake.provider")))
    }

    @Test
    fun unsupportedMimeTypesAreRefused() {
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(FakeShareSource.stream("application/zip", ByteArray(20)))))
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(FakeShareSource.stream("application/octet-stream", ByteArray(20)))))
    }

    @Test
    fun unreadableStreamsAreReportedNotThrown() {
        val refused = FakeShareSource(intentType = "image/png", streamScheme = "content", streamHost = "x.y", opener = { null })
        assertEquals(ShareRejectReason.UNREADABLE, rejected(intake.accept(refused)))
        val io = FakeShareSource(intentType = "image/png", streamScheme = "content", streamHost = "x.y", opener = { throw IOException("boom") })
        assertEquals(ShareRejectReason.UNREADABLE, rejected(intake.accept(io)))
        val sec = FakeShareSource(intentType = "image/png", streamScheme = "content", streamHost = "x.y", opener = { throw SecurityException("no grant") })
        assertEquals(ShareRejectReason.UNREADABLE, rejected(intake.accept(sec)))
    }

    @Test
    fun aStreamThatFailsMidCopyLeavesNothingBehind() {
        val source = FakeShareSource(
            intentType = "image/png",
            streamScheme = "content",
            streamHost = "x.y",
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

    // ---- F4: authority / user info bypass ----

    @Test
    fun userInfoCannotSmuggleOurOwnProviderPastTheCheck() {
        val png = PNG_HEAD + ByteArray(20)
        // The old authority comparison saw "x@app.zaghlol.provider" and let it through; the resolver
        // strips "x@" and would open our own provider.
        val bypass = FakeShareSource.fromUri("content://x@app.zaghlol.provider/files/secret.png", "image/png", png)
        assertEquals("app.zaghlol.provider", bypass.streamHost)
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(bypass)))
        assertEquals(0, bypass.opened)

        // Any user info is refused, even in front of a foreign provider.
        val foreign = FakeShareSource.fromUri("content://0@com.example.provider/a.png", "image/png", png)
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(foreign)))
        assertNoLeftovers(dir)
    }

    @Test
    fun hostCaseAndPortDoNotHideOurOwnProvider() {
        val png = PNG_HEAD + ByteArray(20)
        for (uri in listOf("content://APP.Zaghlol.Provider/a.png", "content://app.zaghlol.provider:7/a.png", "content://app.zaghlol/a.png")) {
            assertEquals(uri, ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(FakeShareSource.fromUri(uri, "image/png", png))))
        }
        accepted(intake.accept(FakeShareSource.fromUri("content://com.example.provider/a.png", "image/png", png)))
    }

    @Test
    fun aProviderThatResolvesToUsIsRefusedWhateverItsName() {
        val source = FakeShareSource.fromUri(
            "content://innocent.looking/a.png",
            "image/png",
            PNG_HEAD + ByteArray(20),
            providerPackage = "app.zaghlol",
        )
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(source)))
    }

    @Test
    fun aContentUriWithoutAHostIsRefused() {
        val source = FakeShareSource(intentType = "image/png", streamScheme = "content", streamHost = null, opener = { (PNG_HEAD + ByteArray(20)).inputStream() })
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(source)))
    }

    // ---- F2: pending caps ----

    @Test
    fun tooManyPendingSharesAreRefusedWithoutReadingTheSender() {
        val capped = ShareIntake(ShareStore(dir, SoftwareShareCipher(), maxPending = 3), "app.zaghlol", probe)
        repeat(3) { accepted(capped.accept(FakeShareSource(intentType = "text/plain", text = "synthetic $it"))) }
        assertEquals(ShareRejectReason.TOO_LARGE, rejected(capped.accept(FakeShareSource(intentType = "text/plain", text = "one more"))))
        val stream = FakeShareSource.stream("image/png", PNG_HEAD + ByteArray(20))
        assertEquals(ShareRejectReason.TOO_LARGE, rejected(capped.accept(stream)))
        assertEquals("the sender's stream is not opened when the store is full", 0, stream.opened)
        assertEquals(3, store.list().size)
    }

    @Test
    fun totalBytesOverTheCapAreRefusedAndThePartialFileIsDeleted() {
        val capped = ShareIntake(ShareStore(dir, SoftwareShareCipher(), maxBytes = 64 * 1024), "app.zaghlol", probe)
        accepted(capped.accept(FakeShareSource.bigStream("application/pdf", PDF_HEAD, 40L * 1024)))
        val before = dir.listFiles()!!.map { it.name }.toSet()
        val outcome = capped.accept(FakeShareSource.bigStream("application/pdf", PDF_HEAD, 40L * 1024))
        assertEquals(ShareRejectReason.TOO_LARGE, rejected(outcome))
        assertEquals(before, dir.listFiles()!!.map { it.name }.toSet())
    }

    @Test
    fun defaultCapsMatchTheDocumentedLimits() {
        assertEquals(10, ShareLimits.MAX_PENDING_SHARES)
        assertEquals(100L * 1024 * 1024, ShareLimits.MAX_PENDING_BYTES)
    }

    // ---- F3: time bound ----

    @Test
    fun aDripFeedingProviderIsAbortedAtTheDeadlineAndLeavesNothing() {
        val source = FakeShareSource.dripStream("image/png", PNG_HEAD) { now += 10 }
        val outcome = intake.accept(source, deadlineAtMs = 5_000)
        assertEquals(ShareRejectReason.UNREADABLE, rejected(outcome))
        assertNoLeftovers(dir)
    }

    @Test
    fun aDripFeedingTextFileIsAbortedToo() {
        val source = FakeShareSource.dripStream("text/csv", "a,b\n".toByteArray()) { now += 10 }
        assertEquals(ShareRejectReason.UNREADABLE, rejected(intake.accept(source, deadlineAtMs = 5_000)))
        assertNoLeftovers(dir)
    }

    @Test
    fun aShareWhoseDeadlinePassedWhileQueuedIsNotRead() {
        now = 10_000
        val stream = FakeShareSource.stream("image/png", PNG_HEAD + ByteArray(20))
        assertEquals(ShareRejectReason.UNREADABLE, rejected(intake.accept(stream, deadlineAtMs = 9_999)))
        assertEquals(0, stream.opened)
        val text = FakeShareSource(intentType = "text/plain", text = "synthetic")
        assertEquals(ShareRejectReason.UNREADABLE, rejected(intake.accept(text, deadlineAtMs = 9_999)))
        assertNoLeftovers(dir)
    }

    @Test
    fun aCancelledReadIsUnreadableAndLeavesNothing() {
        // What the watchdog does on a device: close the stream under a blocked read.
        val source = FakeShareSource(
            intentType = "application/pdf",
            streamScheme = "content",
            streamHost = "com.example.provider",
            opener = {
                object : java.io.InputStream() {
                    var first = true
                    override fun read(): Int = throw UnsupportedOperationException()
                    override fun read(b: ByteArray, off: Int, len: Int): Int {
                        if (first) {
                            first = false
                            PDF_HEAD.copyInto(b, off)
                            return PDF_HEAD.size
                        }
                        throw IOException("stream closed")
                    }
                }
            },
        )
        assertEquals(ShareRejectReason.UNREADABLE, rejected(intake.accept(source, deadlineAtMs = 5_000)))
        assertNoLeftovers(dir)
    }

    // ---- F9: decoded image size ----

    @Test
    fun imagesOverThePixelCapAreRefusedBeforeAnythingIsStored() {
        probe.bounds = ImageBounds(8_001, 8_000) // 64,008,000 px
        assertEquals(ShareRejectReason.TOO_LARGE, rejected(intake.accept(FakeShareSource.stream("image/png", PNG_HEAD + ByteArray(20)))))
        probe.bounds = ImageBounds(1, Int.MAX_VALUE) // no Int overflow in width * height
        assertEquals(ShareRejectReason.TOO_LARGE, rejected(intake.accept(FakeShareSource.stream("image/png", PNG_HEAD + ByteArray(20)))))
        assertNoLeftovers(dir)
    }

    @Test
    fun imagesAtThePixelCapAreAccepted() {
        probe.bounds = ImageBounds(8_000, 8_000) // exactly 64,000,000 px
        accepted(intake.accept(FakeShareSource.stream("image/png", PNG_HEAD + ByteArray(20))))
    }

    @Test
    fun imagesWithoutReadableBoundsAreRefused() {
        probe.bounds = null
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(FakeShareSource.stream("image/jpeg", JPEG_HEAD + ByteArray(20)))))
        probe.bounds = ImageBounds(0, 100)
        assertEquals(ShareRejectReason.UNSUPPORTED_TYPE, rejected(intake.accept(FakeShareSource.stream("image/jpeg", JPEG_HEAD + ByteArray(20)))))
        assertNoLeftovers(dir)
    }

    @Test
    fun theProbeSeesTheWholeSmallImageAndTheStoredBytesAreComplete() {
        val image = PNG_HEAD + ByteArray(5_000) { it.toByte() }
        val d = accepted(intake.accept(FakeShareSource.stream("image/png", image)))
        assertEquals(image.size, probe.lastLength)
        assertArrayEquals(image, store.read(d.id).bytes)
    }

    @Test
    fun aLargeImageIsProbedOnItsPrefixAndStoredInFull() {
        val length = ShareLimits.IMAGE_PROBE_BYTES + 100_000L
        val d = accepted(intake.accept(FakeShareSource.bigStream("image/png", PNG_HEAD, length)))
        assertEquals(ShareLimits.IMAGE_PROBE_BYTES, probe.lastLength)
        assertEquals(length, d.sizeBytes)
        assertEquals(length, store.read(d.id).bytes!!.size.toLong())
    }
}
