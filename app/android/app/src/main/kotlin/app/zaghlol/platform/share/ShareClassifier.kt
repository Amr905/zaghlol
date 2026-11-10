package app.zaghlol.platform.share

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/** Pure MIME and magic-byte checks. No Android classes, so it runs in JVM unit tests. */
object ShareClassifier {
    /** Largest prefix the sniffers need. */
    const val SNIFF_BYTES = 16

    fun normalizeMime(mime: String?): String? {
        if (mime == null) return null
        val base = mime.substringBefore(';').trim().lowercase()
        return base.ifEmpty { null }
    }

    /** Maps a declared MIME to a share kind, or null when it is not one we accept. */
    fun kindForMime(mime: String?): ShareKind? {
        val m = normalizeMime(mime) ?: return null
        return when {
            m == "text/plain" -> ShareKind.TEXT
            m == "text/csv" -> ShareKind.CSV
            m == "application/pdf" -> ShareKind.PDF
            m.startsWith("image/") -> ShareKind.IMAGE
            else -> null
        }
    }

    /** Canonical MIME of a supported image by its first bytes, or null (GIF, SVG, unknown...). */
    fun sniffImage(head: ByteArray): String? {
        if (head.size >= 8 && head.startsWith(PNG)) return "image/png"
        if (head.size >= 3 && head.startsWith(JPEG)) return "image/jpeg"
        if (head.size >= 12 && head.startsWith(RIFF) && head.matchesAt(8, WEBP)) return "image/webp"
        if (head.size >= 12 && head.matchesAt(4, FTYP)) {
            val brand = String(head, 8, 4, Charsets.ISO_8859_1)
            if (brand in HEIF_BRANDS) return "image/heif"
        }
        return null
    }

    fun isPdf(head: ByteArray): Boolean = head.size >= 5 && head.startsWith(PDF)

    /** CSV may be UTF-8 or Windows-1256 (Egyptian bank exports), so only reject binary data. */
    fun looksLikeCsv(bytes: ByteArray, length: Int): Boolean {
        if (length <= 0) return false
        val n = minOf(length, 8192)
        for (i in 0 until n) if (bytes[i] == 0.toByte()) return false
        return true
    }

    /** Strict UTF-8 decode; null when the bytes are not valid UTF-8 or contain NUL. */
    fun decodeUtf8Strict(bytes: ByteArray, length: Int): String? {
        for (i in 0 until length) if (bytes[i] == 0.toByte()) return null
        return try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes, 0, length))
                .toString()
        } catch (_: CharacterCodingException) {
            null
        }
    }

    private val PNG = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    private val JPEG = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte())
    private val RIFF = "RIFF".toByteArray(Charsets.ISO_8859_1)
    private val WEBP = "WEBP".toByteArray(Charsets.ISO_8859_1)
    private val FTYP = "ftyp".toByteArray(Charsets.ISO_8859_1)
    private val PDF = "%PDF-".toByteArray(Charsets.ISO_8859_1)
    private val HEIF_BRANDS = setOf("heic", "heix", "hevc", "heim", "heis", "mif1", "msf1")

    private fun ByteArray.startsWith(prefix: ByteArray): Boolean = matchesAt(0, prefix)

    private fun ByteArray.matchesAt(offset: Int, pattern: ByteArray): Boolean {
        if (size < offset + pattern.size) return false
        for (i in pattern.indices) if (this[offset + i] != pattern[i]) return false
        return true
    }
}
