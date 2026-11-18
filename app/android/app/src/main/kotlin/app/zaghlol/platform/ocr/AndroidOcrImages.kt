package app.zaghlol.platform.ocr

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import app.zaghlol.platform.share.ShareKind
import app.zaghlol.platform.share.ShareStore
import java.io.File
import java.io.IOException

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

    override fun discard(id: String) {
        try {
            store.discard(id)
        } catch (_: Exception) {
            // Nothing more to do: the store purges stale shares after 24 hours.
        }
    }
}

/**
 * `sealImage`: copies a plain image from the app's cache directory into the
 * encrypted share store (spool key, AES-GCM) and deletes the plain file in a
 * `finally`. A path outside [allowedRoots] (after symlink resolution) is
 * refused and left alone: only files the app itself put in its cache are ours
 * to delete. Nothing here logs or puts a path into an error.
 */
class ShareStoreImageSealer(
    private val store: ShareStore,
    private val allowedRoots: List<File>,
    private val decoder: OcrImageDecoder = BitmapOcrDecoder,
) : OcrImageSealer {
    override fun seal(plainImagePath: String): String {
        val file = try {
            File(plainImagePath).canonicalFile
        } catch (_: IOException) {
            throw OcrFailure(OcrFailure.IO_ERROR, "image not readable")
        }
        val roots = allowedRoots.mapNotNull { runCatching { it.canonicalFile }.getOrNull() }
        if (roots.none { file.path.startsWith(it.path + File.separator) }) {
            throw OcrFailure(OcrFailure.IO_ERROR, "image not readable")
        }
        var bytes: ByteArray? = null
        try {
            if (!file.isFile) throw OcrFailure(OcrFailure.IO_ERROR, "image not readable")
            val len = file.length()
            if (len <= 0 || len > OcrLimits.SEAL_MAX_BYTES) throw OcrFailure(OcrFailure.IO_ERROR, "image not readable")
            val data = try {
                file.inputStream().use { readExactly(it, len.toInt()) }
            } catch (_: IOException) {
                throw OcrFailure(OcrFailure.IO_ERROR, "image not readable")
            }
            bytes = data
            val size = decoder.bounds(data) ?: throw OcrFailure(OcrFailure.IO_ERROR, "not an image")
            if (size.width.toLong() * size.height > OcrLimits.IMAGE_MAX_PIXELS) {
                throw OcrFailure(OcrFailure.IO_ERROR, "image too large")
            }
            val writer = try {
                store.newWriter(ShareKind.IMAGE, mimeOf(data))
            } catch (_: ShareStore.Full) {
                throw OcrFailure(OcrFailure.IO_ERROR, "image store full")
            } catch (_: Exception) {
                throw OcrFailure(OcrFailure.IO_ERROR, "image could not be stored")
            }
            try {
                writer.write(data, 0, data.size)
                return writer.commit().id
            } catch (e: OcrFailure) {
                writer.abort()
                throw e
            } catch (_: ShareStore.Full) {
                writer.abort()
                throw OcrFailure(OcrFailure.IO_ERROR, "image store full")
            } catch (_: Exception) {
                writer.abort()
                throw OcrFailure(OcrFailure.IO_ERROR, "image could not be stored")
            }
        } finally {
            bytes?.fill(0)
            file.delete()
        }
    }

    /** Reads exactly [len] bytes (the length probed before) and fails if the file grew or shrank. */
    private fun readExactly(input: java.io.InputStream, len: Int): ByteArray {
        val buf = ByteArray(len)
        var off = 0
        while (off < len) {
            val n = input.read(buf, off, len - off)
            if (n < 0) {
                buf.fill(0)
                throw IOException("short read")
            }
            off += n
        }
        if (input.read() >= 0) {
            buf.fill(0)
            throw IOException("file changed")
        }
        return buf
    }

    private fun mimeOf(d: ByteArray): String = when {
        d.size > 3 && d[0] == 0xFF.toByte() && d[1] == 0xD8.toByte() -> "image/jpeg"
        d.size > 7 && d[0] == 0x89.toByte() && d[1] == 'P'.code.toByte() -> "image/png"
        d.size > 11 && d[0] == 'R'.code.toByte() && d[8] == 'W'.code.toByte() -> "image/webp"
        else -> "image/*"
    }
}
