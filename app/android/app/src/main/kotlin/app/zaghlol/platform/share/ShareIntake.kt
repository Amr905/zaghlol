package app.zaghlol.platform.share

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.security.GeneralSecurityException

/**
 * Validates, size-limits and encrypts one share. Pure Kotlin (no Android
 * types), so every rule is unit-tested on the JVM. It never logs and never
 * keeps content after [accept] returns.
 */
class ShareIntake(
    private val store: ShareStore,
    private val ownPackage: String,
) {
    fun accept(source: ShareSource): ShareOutcome {
        return try {
            if (source.streamScheme != null) acceptStream(source) else acceptText(source)
        } catch (_: IOException) {
            ShareOutcome.Rejected(ShareRejectReason.UNREADABLE)
        } catch (_: SecurityException) {
            ShareOutcome.Rejected(ShareRejectReason.UNREADABLE)
        } catch (_: GeneralSecurityException) {
            ShareOutcome.Rejected(ShareRejectReason.UNREADABLE)
        }
    }

    private fun reject(r: ShareRejectReason) = ShareOutcome.Rejected(r)

    private fun acceptText(source: ShareSource): ShareOutcome {
        val text = source.text?.toString() ?: return reject(ShareRejectReason.EMPTY)
        val kind = ShareClassifier.kindForMime(source.intentType)
        if (kind != ShareKind.TEXT) return reject(ShareRejectReason.UNSUPPORTED_TYPE)
        if (text.isBlank()) return reject(ShareRejectReason.EMPTY)
        if (text.length > ShareLimits.TEXT_MAX_CHARS) return reject(ShareRejectReason.TOO_LARGE)
        return store(ShareKind.TEXT, "text/plain", text.toByteArray(Charsets.UTF_8))
    }

    private fun acceptStream(source: ShareSource): ShareOutcome {
        // A file:// URI would make us read our own private files for another app.
        if (source.streamScheme != "content") return reject(ShareRejectReason.UNSUPPORTED_TYPE)
        val authority = source.streamAuthority.orEmpty()
        if (authority == ownPackage || authority.startsWith("$ownPackage.")) {
            return reject(ShareRejectReason.UNSUPPORTED_TYPE)
        }
        val kind = ShareClassifier.kindForMime(source.resolverType())
            ?: ShareClassifier.kindForMime(source.intentType)
            ?: return reject(ShareRejectReason.UNSUPPORTED_TYPE)
        val input = source.open() ?: return reject(ShareRejectReason.UNREADABLE)
        return input.use {
            when (kind) {
                ShareKind.IMAGE, ShareKind.PDF -> acceptBinary(kind, it)
                ShareKind.TEXT, ShareKind.CSV -> acceptTextFile(kind, it)
            }
        }
    }

    /** Images and PDFs are streamed straight into the encrypted file; only a 16-byte head is inspected. */
    private fun acceptBinary(kind: ShareKind, input: InputStream): ShareOutcome {
        val max = ShareLimits.maxBytes(kind)
        val head = ByteArray(ShareClassifier.SNIFF_BYTES)
        val headLen = readUpTo(input, head)
        if (headLen == 0) return reject(ShareRejectReason.EMPTY)
        val headBytes = head.copyOf(headLen)
        val sniffed: String? = if (kind == ShareKind.PDF) {
            if (ShareClassifier.isPdf(headBytes)) "application/pdf" else null
        } else {
            ShareClassifier.sniffImage(headBytes)
        }
        val mime = sniffed ?: return reject(ShareRejectReason.UNSUPPORTED_TYPE)

        val writer = store.newWriter()
        try {
            var total = headLen.toLong()
            writer.write(headBytes, 0, headLen)
            val buf = ByteArray(COPY_BUFFER)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                total += n
                if (total > max) {
                    writer.abort()
                    return reject(ShareRejectReason.TOO_LARGE)
                }
                writer.write(buf, 0, n)
            }
            return ShareOutcome.Accepted(writer.commit(kind, mime))
        } catch (e: Throwable) {
            writer.abort()
            throw e
        }
    }

    /** Text and CSV files are small enough to hold in memory for full validation. */
    private fun acceptTextFile(kind: ShareKind, input: InputStream): ShareOutcome {
        val max = ShareLimits.maxBytes(kind)
        val out = ByteArrayOutputStream()
        val buf = ByteArray(COPY_BUFFER)
        var total = 0L
        while (true) {
            val n = input.read(buf)
            if (n < 0) break
            total += n
            if (total > max) return reject(ShareRejectReason.TOO_LARGE)
            out.write(buf, 0, n)
        }
        val bytes = out.toByteArray()
        if (bytes.isEmpty()) return reject(ShareRejectReason.EMPTY)
        return if (kind == ShareKind.CSV) {
            if (!ShareClassifier.looksLikeCsv(bytes, bytes.size)) return reject(ShareRejectReason.UNSUPPORTED_TYPE)
            store(ShareKind.CSV, "text/csv", bytes)
        } else {
            val text = ShareClassifier.decodeUtf8Strict(bytes, bytes.size)
                ?: return reject(ShareRejectReason.UNSUPPORTED_TYPE)
            if (text.isBlank()) return reject(ShareRejectReason.EMPTY)
            if (text.length > ShareLimits.TEXT_MAX_CHARS) return reject(ShareRejectReason.TOO_LARGE)
            store(ShareKind.TEXT, "text/plain", bytes)
        }
    }

    private fun store(kind: ShareKind, mime: String, bytes: ByteArray): ShareOutcome {
        val writer = store.newWriter()
        try {
            writer.write(bytes, 0, bytes.size)
            return ShareOutcome.Accepted(writer.commit(kind, mime))
        } catch (e: Throwable) {
            writer.abort()
            throw e
        }
    }

    private fun readUpTo(input: InputStream, buf: ByteArray): Int {
        var read = 0
        while (read < buf.size) {
            val n = input.read(buf, read, buf.size - read)
            if (n < 0) break
            read += n
        }
        return read
    }

    private companion object {
        const val COPY_BUFFER = 16 * 1024
    }
}
