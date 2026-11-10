package app.zaghlol.platform.ocr

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import app.zaghlol.platform.share.ShareKind
import app.zaghlol.platform.share.ShareStore

/** [DecodedImage] backed by an ARGB_8888 bitmap. */
class BitmapImage(val bitmap: Bitmap) : DecodedImage {
    override val width: Int get() = bitmap.width
    override val height: Int get() = bitmap.height
    override fun recycle() = bitmap.recycle()
}

/** BitmapFactory decoder: bounds without pixels, then a sampled decode. */
object BitmapOcrDecoder : OcrImageDecoder {
    override fun bounds(data: ByteArray): ImageSize? {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        try {
            BitmapFactory.decodeByteArray(data, 0, data.size, opts)
        } catch (_: RuntimeException) {
            return null
        }
        if (opts.outWidth <= 0 || opts.outHeight <= 0) return null
        return ImageSize(opts.outWidth, opts.outHeight)
    }

    override fun decode(data: ByteArray, sampleSize: Int): DecodedImage? {
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return try {
            BitmapFactory.decodeByteArray(data, 0, data.size, opts)?.let { BitmapImage(it) }
        } catch (_: RuntimeException) {
            null
        } catch (_: OutOfMemoryError) {
            null
        }
    }
}

/**
 * Resolves the contract's `encryptedImagePath` to a pending share in the T-060
 * store and reads it into memory. Same failure semantics as `ShareIntakeHost`.
 */
class ShareStoreImageSource(private val store: ShareStore) : OcrImageSource {
    override fun read(id: String): ByteArray {
        val content = try {
            store.read(id)
        } catch (_: ShareStore.NotFound) {
            throw OcrFailure(OcrFailure.IO_ERROR, "unknown image")
        } catch (_: ShareStore.Transient) {
            throw OcrFailure(OcrFailure.IO_ERROR, "image could not be read now")
        } catch (_: OutOfMemoryError) {
            throw OcrFailure(OcrFailure.IO_ERROR, "image could not be read now")
        } catch (_: ShareStore.DecryptFailed) {
            throw OcrFailure(OcrFailure.SPOOL_DECRYPT_FAILED, "image could not be decrypted")
        }
        if (content.descriptor.kind != ShareKind.IMAGE) throw OcrFailure(OcrFailure.OCR_FAILED, "not an image")
        return content.bytes ?: throw OcrFailure(OcrFailure.OCR_FAILED, "not an image")
    }
}
