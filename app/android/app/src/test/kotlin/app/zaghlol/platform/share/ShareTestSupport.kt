package app.zaghlol.platform.share

import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.URI
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.CipherOutputStream
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Software AES-256-GCM with the same file format and AAD use as [KeystoreShareCipher]. Test key only. */
open class SoftwareShareCipher(keyBytes: ByteArray = ByteArray(32) { it.toByte() }) : ShareCipher {
    private val key = SecretKeySpec(keyBytes, "AES")
    private val random = java.security.SecureRandom()

    override fun wrapEncrypt(out: OutputStream, aad: ByteArray): OutputStream {
        val iv = ByteArray(ShareCipher.NONCE_BYTES).also { random.nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
        cipher.updateAAD(aad)
        out.write(iv)
        return CipherOutputStream(out, cipher)
    }

    override fun decrypt(data: ByteArray, aad: ByteArray): ByteArray {
        if (data.size < ShareCipher.NONCE_BYTES + ShareCipher.TAG_BYTES) throw AEADBadTagException("truncated")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, data, 0, ShareCipher.NONCE_BYTES))
        cipher.updateAAD(aad)
        return cipher.doFinal(data, ShareCipher.NONCE_BYTES, data.size - ShareCipher.NONCE_BYTES)
    }
}

/** Fails the next [failures] decrypts with [error] (a Keystore-style transient failure), then works. */
class FlakyShareCipher(var failures: Int, private val error: () -> Exception) : SoftwareShareCipher() {
    override fun decrypt(data: ByteArray, aad: ByteArray): ByteArray {
        if (failures > 0) {
            failures--
            throw error()
        }
        return super.decrypt(data, aad)
    }
}

/** Fixed bounds for every image, so intake tests control the pixel cap without real image data. */
class FakeBoundsProbe(var bounds: ImageBounds? = ImageBounds(1080, 2400)) : ImageBoundsProbe {
    var lastLength = -1
    override fun bounds(data: ByteArray, length: Int): ImageBounds? {
        lastLength = length
        return bounds
    }
}

class FakeShareSource(
    override val intentType: String? = null,
    override val text: CharSequence? = null,
    override val streamScheme: String? = null,
    override val streamHost: String? = null,
    override val streamHasUserInfo: Boolean = false,
    override val streamProviderPackage: String? = null,
    private val resolverMime: String? = null,
    private val opener: () -> InputStream? = { null },
) : ShareSource {
    var opened = 0
    var cancelled = false

    override fun resolverType(): String? = resolverMime
    override fun open(): InputStream? {
        opened++
        return opener()
    }

    override fun cancel() {
        cancelled = true
    }

    companion object {
        fun stream(
            mime: String,
            bytes: ByteArray,
            host: String = "com.example.provider",
            scheme: String = "content",
        ) = FakeShareSource(
            intentType = mime,
            streamScheme = scheme,
            streamHost = host,
            opener = { ByteArrayInputStream(bytes) },
        )

        /**
         * Parses [uri] like a ContentResolver caller would see it (scheme, host
         * without user info or port, user info present or not).
         */
        fun fromUri(uri: String, mime: String, bytes: ByteArray, providerPackage: String? = null): FakeShareSource {
            val u = URI(uri)
            return FakeShareSource(
                intentType = mime,
                streamScheme = u.scheme?.lowercase(),
                streamHost = u.host?.lowercase(),
                streamHasUserInfo = u.rawUserInfo != null,
                streamProviderPackage = providerPackage,
                opener = { ByteArrayInputStream(bytes) },
            )
        }

        /** A stream of [length] bytes that starts with [head], generated lazily (no big allocation). */
        fun bigStream(mime: String, head: ByteArray, length: Long) = FakeShareSource(
            intentType = mime,
            streamScheme = "content",
            streamHost = "com.example.provider",
            opener = {
                object : InputStream() {
                    var pos = 0L
                    override fun read(): Int = if (pos >= length) -1 else {
                        val b = if (pos < head.size) head[pos.toInt()].toInt() and 0xFF else 0x41
                        pos++
                        b
                    }
                    override fun read(b: ByteArray, off: Int, len: Int): Int {
                        if (pos >= length) return -1
                        val n = minOf(len.toLong(), length - pos).toInt()
                        for (i in 0 until n) b[off + i] = read().toByte()
                        return n
                    }
                }
            },
        )

        /** A never-ending stream that returns one byte per read and calls [onRead] first (drip-feed). */
        fun dripStream(mime: String, head: ByteArray, onRead: () -> Unit) = FakeShareSource(
            intentType = mime,
            streamScheme = "content",
            streamHost = "com.example.provider",
            opener = {
                object : InputStream() {
                    var pos = 0
                    override fun read(): Int = throw UnsupportedOperationException()
                    override fun read(b: ByteArray, off: Int, len: Int): Int {
                        onRead()
                        if (pos < head.size) {
                            b[off] = head[pos++]
                            return 1
                        }
                        b[off] = 0x41
                        return 1
                    }
                }
            },
        )
    }
}

val PNG_HEAD = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52)
val JPEG_HEAD = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 0, 0x10, 0x4A, 0x46, 0x49, 0x46, 0)
val GIF_HEAD = "GIF89a".toByteArray() + ByteArray(10)
val PDF_HEAD = "%PDF-1.7\n".toByteArray()

fun ByteArray.contains(needle: ByteArray): Boolean {
    if (needle.isEmpty()) return true
    outer@ for (i in 0..size - needle.size) {
        for (j in needle.indices) if (this[i + j] != needle[j]) continue@outer
        return true
    }
    return false
}

fun File.allBytes(): List<ByteArray> = listFiles().orEmpty().filter { it.isFile }.map { it.readBytes() }

fun assertNoLeftovers(dir: File) {
    val names = dir.listFiles().orEmpty().map { it.name }
    if (names.isNotEmpty()) throw AssertionError("expected an empty store but found $names")
}

class ThrowingStreamException : IOException("synthetic")
