package app.zaghlol.platform.ocr

import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException

/**
 * Pigeon host for `OcrHostApi` (platform-channels.md section 4).
 *
 * The image is read from the share store into memory, decoded with a
 * sample-size cap and recognised; nothing is written to disk and the share is
 * not discarded here (Dart owns that, FU-067). Recognitions run one at a time
 * on [executor]. Nothing here logs; errors carry codes only.
 *
 * [post] delivers the reply on the platform thread. [clock] is monotonic ms.
 */
class OcrHost(
    private val images: OcrImageSource,
    private val decoder: OcrImageDecoder,
    private val latin: OcrEngine,
    private val arabic: ArabicOcrEngine,
    private val executor: ExecutorService,
    private val post: (Runnable) -> Unit,
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
) : OcrHostApi {

    override fun recognize(encryptedImagePath: String, languages: List<String>, callback: (Result<OcrResult>) -> Unit) {
        val task = Runnable {
            val result = try {
                Result.success(recognizeBlocking(encryptedImagePath, languages))
            } catch (e: OcrFailure) {
                Result.failure(OcrApiError(e.code, e.message))
            } catch (_: OutOfMemoryError) {
                Result.failure(OcrApiError(OcrFailure.OCR_FAILED, "recognition failed"))
            } catch (_: Exception) {
                Result.failure(OcrApiError(OcrFailure.OCR_FAILED, "recognition failed"))
            }
            post(Runnable { callback(result) })
        }
        try {
            executor.execute(task)
        } catch (_: RejectedExecutionException) {
            callback(Result.failure(OcrApiError(OcrFailure.OCR_FAILED, "recognition unavailable")))
        }
    }

    override fun supportedLanguages(): List<String> =
        if (arabic.likelyAvailable()) listOf(OcrLimits.LANG_AR, OcrLimits.LANG_EN) else listOf(OcrLimits.LANG_EN)

    /** Visible for tests. */
    fun recognizeBlocking(id: String, languages: List<String>): OcrResult {
        val wanted = languages.filter { it == OcrLimits.LANG_AR || it == OcrLimits.LANG_EN }.toSet()
        if (wanted.isEmpty()) throw OcrFailure(OcrFailure.OCR_FAILED, "no supported language requested")
        val deadline = clock() + OcrLimits.TIMEOUT_MS

        var useArabic = OcrLimits.LANG_AR in wanted
        val useLatin = OcrLimits.LANG_EN in wanted
        if (useArabic && !arabic.ensureAvailable()) {
            if (!useLatin) throw OcrFailure(OcrFailure.NOT_AVAILABLE, "Arabic model unavailable")
            useArabic = false
        }

        val bytes = images.read(id)
        var image: DecodedImage? = null
        try {
            val size = decoder.bounds(bytes) ?: throw OcrFailure(OcrFailure.OCR_FAILED, "not a decodable image")
            if (size.width <= 0 || size.height <= 0 ||
                size.width.toLong() * size.height > OcrLimits.IMAGE_MAX_PIXELS
            ) {
                throw OcrFailure(OcrFailure.OCR_FAILED, "image too large")
            }
            val img = decoder.decode(bytes, OcrLimits.sampleSizeFor(size.width, size.height))
                ?: throw OcrFailure(OcrFailure.OCR_FAILED, "not a decodable image")
            image = img
            bytes.fill(0)

            val latinLines = if (useLatin) guarded(deadline) { latin.recognize(img, deadline) } else null
            val arabicLines = if (useArabic) guarded(deadline) { arabic.recognize(img, deadline) } else null
            val w = img.width.toDouble()
            val h = img.height.toDouble()
            val lines = OcrMerger.merge(latinLines, arabicLines).map { it.toOcrLine(w, h) }
            return OcrResult(lines)
        } finally {
            bytes.fill(0)
            image?.recycle()
        }
    }

    private fun <T> guarded(deadline: Long, block: () -> T): T {
        if (clock() >= deadline) throw OcrFailure(OcrFailure.OCR_FAILED, "recognition timed out")
        return block()
    }

    private fun RawLine.toOcrLine(w: Double, h: Double): OcrLine {
        fun n(v: Double) = if (v.isNaN()) 0.0 else v.coerceIn(0.0, 1.0)
        val x = n(left / w)
        val y = n(top / h)
        return OcrLine(
            text = text,
            confidence = n(confidence),
            box = listOf(x, y, n(right / w) - x, n(bottom / h) - y).map { maxOf(it, 0.0) },
        )
    }
}
