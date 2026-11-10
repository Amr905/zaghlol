package app.zaghlol.platform.ocr

/** A line as an engine reports it: pixel box of the decoded image, confidence 0..1. Contains recognised text, so never log it. */
data class RawLine(
    val text: String,
    val confidence: Double,
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top
}

/** An image decoded for recognition. Owned by the caller, which must call [recycle] (in a `finally`). */
interface DecodedImage {
    val width: Int
    val height: Int
    fun recycle()
}

data class ImageSize(val width: Int, val height: Int)

/** Production: BitmapFactory. Fakes in JVM tests. */
interface OcrImageDecoder {
    /** Header-only bounds; null when the bytes are not a decodable image. */
    fun bounds(data: ByteArray): ImageSize?

    /** Decodes with [sampleSize] (a power of two); null when the bytes cannot be decoded. */
    fun decode(data: ByteArray, sampleSize: Int): DecodedImage?
}

/** One recognition engine. Throws [OcrFailure] on any problem; must stop work by [deadlineAtMs] (on [OcrLimits] clock). */
interface OcrEngine {
    fun recognize(image: DecodedImage, deadlineAtMs: Long): List<RawLine>
}

/** The Arabic engine also reports whether its model is usable. */
interface ArabicOcrEngine : OcrEngine {
    /** Installs and verifies the model if needed. False when it cannot be made usable. */
    fun ensureAvailable(): Boolean

    /** Cheap check that never touches the disk beyond a cached answer; true when [ensureAvailable] has succeeded or the model asset exists. */
    fun likelyAvailable(): Boolean
}

/** Reads the plaintext of a pending share in memory. Throws [OcrFailure] with the contract's error code. */
fun interface OcrImageSource {
    fun read(id: String): ByteArray
}

/** Error with a platform-channels.md error code. Never carries recognised text, ids or sizes. */
class OcrFailure(val code: String, message: String) : Exception(message) {
    companion object {
        const val OCR_FAILED = "OCR_FAILED"
        const val NOT_AVAILABLE = "NOT_AVAILABLE"
        const val IO_ERROR = "IO_ERROR"
        const val SPOOL_DECRYPT_FAILED = "SPOOL_DECRYPT_FAILED"
    }
}

object OcrLimits {
    /** Same cap as T-060 intake (ShareLimits.IMAGE_MAX_PIXELS), re-checked here because the bytes are untrusted. */
    const val IMAGE_MAX_PIXELS = 64_000_000L

    /** Decoded bitmap cap (ARGB_8888 = 4 bytes/pixel, so 32 MB). Larger images are decoded with a sample size. */
    const val DECODE_MAX_PIXELS = 8_000_000L

    /** Whole recognition deadline, all engines together. */
    const val TIMEOUT_MS = 40_000L

    const val LANG_AR = "ar"
    const val LANG_EN = "en"

    /** Power-of-two sample size so that the decoded size is at most [DECODE_MAX_PIXELS]. Never below 1. */
    fun sampleSizeFor(width: Int, height: Int): Int {
        var sample = 1
        while (true) {
            val w = (width.toLong() + sample - 1) / sample
            val h = (height.toLong() + sample - 1) / sample
            if (w * h <= DECODE_MAX_PIXELS || sample >= 1 shl 16) return sample
            sample = sample shl 1
        }
    }
}
