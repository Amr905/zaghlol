package app.zaghlol.platform.ocr

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

private class FakeImage(override val width: Int, override val height: Int) : DecodedImage {
    var recycled = false
    override fun recycle() {
        recycled = true
    }
}

private class FakeDecoder(var size: ImageSize? = ImageSize(1000, 2000), var decodes: Boolean = true) : OcrImageDecoder {
    var lastSample = -1
    var image: FakeImage? = null
    override fun bounds(data: ByteArray) = size
    override fun decode(data: ByteArray, sampleSize: Int): DecodedImage? {
        lastSample = sampleSize
        if (!decodes) return null
        return FakeImage(size!!.width / sampleSize, size!!.height / sampleSize).also { image = it }
    }
}

private class FakeEngine(var lines: List<RawLine> = emptyList(), var error: Throwable? = null) : OcrEngine {
    val calls = AtomicInteger()
    var onCall: () -> Unit = {}
    override fun recognize(image: DecodedImage, deadlineAtMs: Long): List<RawLine> {
        calls.incrementAndGet()
        onCall()
        error?.let { throw it }
        return lines
    }
}

private class FakeArabic(var available: Boolean = true, var lines: List<RawLine> = emptyList()) : ArabicOcrEngine {
    val calls = AtomicInteger()
    override fun ensureAvailable() = available
    override fun likelyAvailable() = available
    override fun recognize(image: DecodedImage, deadlineAtMs: Long): List<RawLine> {
        calls.incrementAndGet()
        return lines
    }
}

class OcrHostTest {
    private val sentinelId = "SENTINEL-ID-0123456789ab"
    private val sentinelText = "SENTINEL-TEXT-9f3"
    private val bytes = ByteArray(16) { 7 }
    private var source = OcrImageSource { bytes }
    private val decoder = FakeDecoder()
    private val latin = FakeEngine(listOf(RawLine("EGP 100", 0.8, 100, 200, 300, 260)))
    private val arabic = FakeArabic(lines = listOf(RawLine("مرحبا", 0.7, 0, 0, 500, 100)))
    private val executor = Executors.newSingleThreadExecutor()

    private fun host(clock: () -> Long = { 0L }) =
        OcrHost({ source.read(it) }, decoder, latin, arabic, executor, { it.run() }, clock)

    private fun failureCode(block: () -> Unit): OcrFailure = try {
        block()
        fail("expected OcrFailure")
        throw AssertionError()
    } catch (e: OcrFailure) {
        e
    }

    @Test
    fun mergesBothEnginesAndNormalisesBoxesToTheDecodedImage() {
        val r = host().recognizeBlocking("id", listOf("ar", "en"))
        assertEquals(listOf("مرحبا", "EGP 100"), r.lines.map { it.text })
        assertEquals(listOf(0.1, 0.1, 0.2, 0.03), r.lines[1].box.map { Math.round(it * 1000) / 1000.0 })
        assertEquals(0.7, r.lines[0].confidence, 1e-9)
    }

    @Test
    fun onlyRequestedEnginesRun() {
        host().recognizeBlocking("id", listOf("en"))
        assertEquals(1, latin.calls.get())
        assertEquals(0, arabic.calls.get())
        host().recognizeBlocking("id", listOf("ar", "xx"))
        assertEquals(1, latin.calls.get())
        assertEquals(1, arabic.calls.get())
    }

    @Test
    fun noSupportedLanguageIsOcrFailed() {
        assertEquals("OCR_FAILED", failureCode { host().recognizeBlocking("id", listOf("fr")) }.code)
        assertEquals("OCR_FAILED", failureCode { host().recognizeBlocking("id", emptyList()) }.code)
    }

    @Test
    fun missingArabicModelIsNotAvailableAloneAndDroppedWithEnglish() {
        arabic.available = false
        assertEquals("NOT_AVAILABLE", failureCode { host().recognizeBlocking("id", listOf("ar")) }.code)
        val r = host().recognizeBlocking("id", listOf("ar", "en"))
        assertEquals(listOf("EGP 100"), r.lines.map { it.text })
        assertEquals(listOf("en"), host().supportedLanguages())
    }

    @Test
    fun supportedLanguagesListsArabicWhenModelIsUsable() {
        assertEquals(listOf("ar", "en"), host().supportedLanguages())
    }

    @Test
    fun oversizedImageIsRefusedBeforeDecoding() {
        decoder.size = ImageSize(10_000, 10_000) // 100 MP
        assertEquals("OCR_FAILED", failureCode { host().recognizeBlocking("id", listOf("en")) }.code)
        assertEquals(-1, decoder.lastSample)
    }

    @Test
    fun largeButAllowedImageIsDecodedWithASampleSize() {
        decoder.size = ImageSize(8000, 8000)
        host().recognizeBlocking("id", listOf("en"))
        assertEquals(4, decoder.lastSample)
    }

    @Test
    fun undecodableBytesAreOcrFailed() {
        decoder.size = null
        assertEquals("OCR_FAILED", failureCode { host().recognizeBlocking("id", listOf("en")) }.code)
        decoder.size = ImageSize(10, 10)
        decoder.decodes = false
        assertEquals("OCR_FAILED", failureCode { host().recognizeBlocking("id", listOf("en")) }.code)
    }

    @Test
    fun bitmapIsRecycledAndPlaintextZeroedOnSuccessAndOnEngineFailure() {
        host().recognizeBlocking("id", listOf("en"))
        assertTrue(decoder.image!!.recycled)
        assertArrayEquals(ByteArray(16), bytes)

        val again = ByteArray(16) { 9 }
        source = OcrImageSource { again }
        latin.error = OcrFailure("OCR_FAILED", "boom")
        failureCode { host().recognizeBlocking("id", listOf("en")) }
        assertTrue(decoder.image!!.recycled)
        assertArrayEquals(ByteArray(16), again)
    }

    @Test
    fun plaintextIsZeroedWhenBoundsFail() {
        val b = ByteArray(8) { 5 }
        source = OcrImageSource { b }
        decoder.size = null
        failureCode { host().recognizeBlocking("id", listOf("en")) }
        assertArrayEquals(ByteArray(8), b)
    }

    @Test
    fun sourceErrorCodesPassThrough() {
        for (code in listOf("IO_ERROR", "SPOOL_DECRYPT_FAILED")) {
            source = OcrImageSource { throw OcrFailure(code, "x") }
            assertEquals(code, failureCode { host().recognizeBlocking("id", listOf("en")) }.code)
        }
    }

    @Test
    fun expiredDeadlineStopsBeforeTheNextEngine() {
        var now = 0L
        latin.onCall = { now += OcrLimits.TIMEOUT_MS + 1 }
        val e = failureCode { host { now }.recognizeBlocking("id", listOf("en", "ar")) }
        assertEquals("OCR_FAILED", e.code)
        assertEquals(0, arabic.calls.get())
    }

    @Test
    fun errorsNeverEchoTheIdOrRecognisedText() {
        latin.lines = listOf(RawLine(sentinelText, 1.0, 0, 0, 10, 10))
        source = OcrImageSource { throw OcrFailure("IO_ERROR", "unknown image") }
        val e = failureCode { host().recognizeBlocking(sentinelId, listOf("en")) }
        assertFalse(e.message!!.contains(sentinelId))
        decoder.size = null
        source = OcrImageSource { bytes }
        val e2 = failureCode { host().recognizeBlocking(sentinelId, listOf("en")) }
        assertFalse(e2.message!!.contains(sentinelId))
    }

    @Test
    fun unexpectedEngineExceptionBecomesOcrFailedThroughTheCallback() {
        latin.error = IllegalStateException(sentinelText)
        var got: Result<OcrResult>? = null
        val done = CountDownLatch(1)
        host().recognize(sentinelId, listOf("en")) {
            got = it
            done.countDown()
        }
        assertTrue(done.await(5, TimeUnit.SECONDS))
        val err = got!!.exceptionOrNull() as OcrApiError
        assertEquals("OCR_FAILED", err.code)
        assertFalse(err.message!!.contains(sentinelText))
        assertNotNull(err)
    }

    @Test
    fun callsAreSerialised() {
        val running = AtomicInteger()
        val maxRunning = AtomicInteger()
        latin.onCall = {
            maxRunning.accumulateAndGet(running.incrementAndGet()) { a, b -> maxOf(a, b) }
            Thread.sleep(30)
            running.decrementAndGet()
        }
        val done = CountDownLatch(4)
        val h = host()
        repeat(4) { h.recognize("id", listOf("en")) { done.countDown() } }
        assertTrue(done.await(10, TimeUnit.SECONDS))
        assertEquals(1, maxRunning.get())
        assertEquals(4, latin.calls.get())
    }

    @Test
    fun shutDownExecutorReportsOcrFailedInsteadOfHanging() {
        executor.shutdown()
        var got: Result<OcrResult>? = null
        host().recognize("id", listOf("en")) { got = it }
        assertEquals("OCR_FAILED", (got!!.exceptionOrNull() as OcrApiError).code)
    }
}
