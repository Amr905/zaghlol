package app.zaghlol.platform.ocr

import java.io.File
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest

/** The one bundled Tesseract model: `ara` from tessdata_fast (Apache-2.0), pinned by size and SHA-256. */
object TessdataSpec {
    const val ASSET_PATH = "tessdata/ara.traineddata"
    const val FILE_NAME = "ara.traineddata"
    const val SIZE_BYTES = 1_432_056L
    const val SHA256 = "e3206d3dc87fd50c24a0fb9f01838615911d25168f4e64415244b67d2bb3e729"
}

/**
 * Copies the bundled model to `<root>/tessdata/` (Tesseract needs a real
 * directory) and verifies it against the pinned hash. Public, re-creatable
 * data: a copy that is proven wrong (hash mismatch) is replaced from the APK; a
 * read error is never treated as proof (it is thrown). Pure `java.io`.
 */
class TessdataInstaller(
    private val root: File,
    private val openAsset: () -> InputStream,
    private val expectedSha256: String = TessdataSpec.SHA256,
    private val expectedSize: Long = TessdataSpec.SIZE_BYTES,
) {
    private val dir = File(root, "tessdata")
    private val target = File(dir, TessdataSpec.FILE_NAME)

    /** Directory to pass to Tesseract `init`: it contains `tessdata/`. */
    val dataPath: String get() = root.absolutePath

    @Synchronized
    @Throws(IOException::class)
    fun ensureInstalled() {
        dir.mkdirs()
        if (target.isFile && sha256Of(target.inputStream()) == expectedSha256) return
        val tmp = File(dir, TessdataSpec.FILE_NAME + ".tmp")
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            var total = 0L
            openAsset().use { input ->
                tmp.outputStream().use { out ->
                    val buf = ByteArray(32 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        total += n
                        if (total > expectedSize) throw IOException("model asset has the wrong size")
                        digest.update(buf, 0, n)
                        out.write(buf, 0, n)
                    }
                }
            }
            if (total != expectedSize || hex(digest.digest()) != expectedSha256) throw IOException("model asset does not match the pinned hash")
            if (!tmp.renameTo(target)) throw IOException("model install failed")
        } finally {
            tmp.delete()
        }
    }

    companion object {
        fun sha256Of(input: InputStream): String {
            val digest = MessageDigest.getInstance("SHA-256")
            input.use {
                val buf = ByteArray(32 * 1024)
                while (true) {
                    val n = it.read(buf)
                    if (n < 0) break
                    digest.update(buf, 0, n)
                }
            }
            return hex(digest.digest())
        }

        private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }
    }
}
