package app.zaghlol.platform.share

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.security.GeneralSecurityException

/** Decoded image dimensions, read without decoding pixels. */
data class ImageBounds(val width: Int, val height: Int)

/** Reads image bounds from leading bytes (production: BitmapFactory with `inJustDecodeBounds`). Null when unknown. */
fun interface ImageBoundsProbe {
    fun bounds(data: ByteArray, length: Int): ImageBounds?
}

/**
 * Validates, size-limits and encrypts one share. Pure Kotlin (no Android
 * types), so every rule is unit-tested on the JVM. It never logs and never
 * keeps content after [accept] returns.
 *
 * [clock] is monotonic milliseconds and is only compared with the deadline
 * given to [accept].
 */
class ShareIntake(
    private val store: ShareStore,
    private val ownPackage: String,
    private val imageProbe: ImageBoundsProbe,
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
) {
    /** Thrown internally when the deadline passes; maps to `unreadable`. */
    private class TimedOut : IOException("share intake timed out")

    /**
     * [deadlineAtMs] is on [clock]'s time base (F3). Past it, the read is
     * aborted, nothing is committed and the share is refused as `unreadable`.
     */
    fun accept(source: ShareSource, deadlineAtMs: Long = Long.MAX_VALUE): ShareOutcome {
        return try {
            checkDeadline(deadlineAtMs)
            if (source.streamScheme != null) acceptStream(source, deadlineAtMs) else acceptText(source, deadlineAtMs)
        } catch (_: ShareStore.Full) {
            reject(ShareRejectReason.TOO_LARGE)
        } catch (_: IOException) {
            reject(ShareRejectReason.UNREADABLE)
        } catch (_: SecurityException) {
            reject(ShareRejectReason.UNREADABLE)
        } catch (_: GeneralSecurityException) {
            reject(ShareRejectReason.UNREADABLE)
        }
    }

    private fun reject(r: ShareRejectReason) = ShareOutcome.Rejected(r)

    private fun checkDeadline(deadlineAtMs: Long) {
        if (clock() > deadlineAtMs) throw TimedOut()
    }

    private fun acceptText(source: ShareSource, deadlineAtMs: Long): ShareOutcome {
        val text = source.text?.toString() ?: return reject(ShareRejectReason.EMPTY)
        val kind = ShareClassifier.kindForMime(source.intentType)
        if (kind != ShareKind.TEXT) return reject(ShareRejectReason.UNSUPPORTED_TYPE)
        if (text.isBlank()) return reject(ShareRejectReason.EMPTY)
        if (text.length > ShareLimits.TEXT_MAX_CHARS) return reject(ShareRejectReason.TOO_LARGE)
        return store(ShareKind.TEXT, "text/plain", text.toByteArray(Charsets.UTF_8), deadlineAtMs)
    }

    private fun acceptStream(source: ShareSource, deadlineAtMs: Long): ShareOutcome {
        if (!ShareUriPolicy.isAllowed(source, ownPackage)) return reject(ShareRejectReason.UNSUPPORTED_TYPE)
        val kind = ShareClassifier.kindForMime(source.resolverType())
            ?: ShareClassifier.kindForMime(source.intentType)
            ?: return reject(ShareRejectReason.UNSUPPORTED_TYPE)
        // Fail fast when the caps are reached, before reading anything from the sender.
        store.ensureCapacity()
        val input = source.open() ?: return reject(ShareRejectReason.UNREADABLE)
        return input.use {
            when (kind) {
                ShareKind.IMAGE, ShareKind.PDF -> acceptBinary(kind, it, deadlineAtMs)
                ShareKind.TEXT, ShareKind.CSV -> acceptTextFile(kind, it, deadlineAtMs)
            }
        }
    }

    /**
     * Images and PDFs are streamed into the encrypted file. Only a prefix is
     * held in memory: 16 bytes for a PDF, up to [ShareLimits.IMAGE_PROBE_BYTES]
     * for an image so its bounds can be checked (F9) before anything is stored.
     */
    private fun acceptBinary(kind: ShareKind, input: InputStream, deadlineAtMs: Long): ShareOutcome {
        val max = ShareLimits.maxBytes(kind)
        val prefix = ByteArray(if (kind == ShareKind.IMAGE) ShareLimits.IMAGE_PROBE_BYTES else ShareClassifier.SNIFF_BYTES)
        val prefixLen = readUpTo(input, prefix, deadlineAtMs)
        if (prefixLen == 0) return reject(ShareRejectReason.EMPTY)
        val head = prefix.copyOf(minOf(prefixLen, ShareClassifier.SNIFF_BYTES))
        val sniffed: String? = if (kind == ShareKind.PDF) {
            if (ShareClassifier.isPdf(head)) "application/pdf" else null
        } else {
            ShareClassifier.sniffImage(head)
        }
        val mime = sniffed ?: return reject(ShareRejectReason.UNSUPPORTED_TYPE)

        if (kind == ShareKind.IMAGE) {
            val bounds = imageProbe.bounds(prefix, prefixLen)
            if (bounds == null || bounds.width <= 0 || bounds.height <= 0) {
                return reject(ShareRejectReason.UNSUPPORTED_TYPE)
            }
            if (bounds.width.toLong() * bounds.height.toLong() > ShareLimits.IMAGE_MAX_PIXELS) {
                return reject(ShareRejectReason.TOO_LARGE)
            }
        }

        val writer = store.newWriter(kind, mime)
        try {
            var total = prefixLen.toLong()
            writer.write(prefix, 0, prefixLen)
            val buf = ByteArray(COPY_BUFFER)
            while (true) {
                val n = input.read(buf)
                checkDeadline(deadlineAtMs)
                if (n < 0) break
                total += n
                if (total > max) {
                    writer.abort()
                    return reject(ShareRejectReason.TOO_LARGE)
                }
                writer.write(buf, 0, n)
            }
            checkDeadline(deadlineAtMs)
            return ShareOutcome.Accepted(writer.commit())
        } catch (e: Throwable) {
            writer.abort()
            throw e
        }
    }

    /** Text and CSV files are small enough to hold in memory for full validation. */
    private fun acceptTextFile(kind: ShareKind, input: InputStream, deadlineAtMs: Long): ShareOutcome {
        val max = ShareLimits.maxBytes(kind)
        val out = ByteArrayOutputStream()
        val buf = ByteArray(COPY_BUFFER)
        var total = 0L
        while (true) {
            val n = input.read(buf)
            checkDeadline(deadlineAtMs)
            if (n < 0) break
            total += n
            if (total > max) return reject(ShareRejectReason.TOO_LARGE)
            out.write(buf, 0, n)
        }
        val bytes = out.toByteArray()
        if (bytes.isEmpty()) return reject(ShareRejectReason.EMPTY)
        return if (kind == ShareKind.CSV) {
            if (!ShareClassifier.looksLikeCsv(bytes, bytes.size)) return reject(ShareRejectReason.UNSUPPORTED_TYPE)
            store(ShareKind.CSV, "text/csv", bytes, deadlineAtMs)
        } else {
            val text = ShareClassifier.decodeUtf8Strict(bytes, bytes.size)
                ?: return reject(ShareRejectReason.UNSUPPORTED_TYPE)
            if (text.isBlank()) return reject(ShareRejectReason.EMPTY)
            if (text.length > ShareLimits.TEXT_MAX_CHARS) return reject(ShareRejectReason.TOO_LARGE)
            store(ShareKind.TEXT, "text/plain", bytes, deadlineAtMs)
        }
    }

    private fun store(kind: ShareKind, mime: String, bytes: ByteArray, deadlineAtMs: Long): ShareOutcome {
        val writer = store.newWriter(kind, mime)
        try {
            writer.write(bytes, 0, bytes.size)
            checkDeadline(deadlineAtMs)
            return ShareOutcome.Accepted(writer.commit())
        } catch (e: Throwable) {
            writer.abort()
            throw e
        }
    }

    private fun readUpTo(input: InputStream, buf: ByteArray, deadlineAtMs: Long): Int {
        var read = 0
        while (read < buf.size) {
            val n = input.read(buf, read, buf.size - read)
            checkDeadline(deadlineAtMs)
            if (n < 0) break
            read += n
        }
        return read
    }

    private companion object {
        const val COPY_BUFFER = 16 * 1024
    }
}
