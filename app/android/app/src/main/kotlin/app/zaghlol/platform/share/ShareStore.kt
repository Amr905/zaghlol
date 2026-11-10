package app.zaghlol.platform.share

import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FilterOutputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream
import java.security.SecureRandom

/**
 * Encrypted store for pending shares in app-private no-backup storage
 * (T-165: callers pass a directory under noBackupFilesDir). Each share is
 * `<id>.bin` (body) plus `<id>.meta` (kind, MIME, size, time); both are
 * encrypted. The meta file is written last and marks a committed share.
 * Nothing here logs.
 */
class ShareStore(
    private val dir: File,
    private val cipher: ShareCipher,
    private val clock: () -> Long = System::currentTimeMillis,
    private val newId: () -> String = { randomId() },
) {
    class NotFound : Exception("unknown share")
    class DecryptFailed(cause: Throwable) : Exception("share could not be decrypted", cause)

    /** An in-progress encrypted write. Call [commit] or [abort] exactly once. */
    inner class Writer internal constructor(private val id: String) {
        private val bodyTmp = File(dir, "$id.bin.tmp")
        private val fos = FileOutputStream(bodyTmp)
        private val enc: OutputStream = try {
            cipher.wrapEncrypt(NonClosing(fos))
        } catch (e: Throwable) {
            fos.close()
            bodyTmp.delete()
            throw e
        }
        private var size = 0L

        fun write(buf: ByteArray, off: Int, len: Int) {
            enc.write(buf, off, len)
            size += len
        }

        fun commit(kind: ShareKind, mime: String): ShareDescriptor {
            try {
                enc.close()
                fos.fd.sync()
                fos.close()
                if (!bodyTmp.renameTo(body(id))) throw IOException("rename failed")
                val d = ShareDescriptor(id, kind, mime, size, clock())
                writeMeta(d)
                return d
            } catch (e: Throwable) {
                abort()
                throw e
            }
        }

        fun abort() {
            runCatching { enc.close() }
            runCatching { fos.close() }
            bodyTmp.delete()
            body(id).delete()
            meta(id).delete()
            File(dir, "$id.meta.tmp").delete()
        }
    }

    fun newWriter(): Writer {
        dir.mkdirs()
        purgeStale()
        return Writer(newId())
    }

    /** Pending shares, oldest first. Also purges stale files. */
    fun list(): List<ShareDescriptor> {
        purgeStale()
        val files = dir.listFiles { f -> f.name.endsWith(".meta") } ?: return emptyList()
        return files.mapNotNull { f ->
            val id = f.name.removeSuffix(".meta")
            if (!ID.matches(id)) null else runCatching { readMeta(id) }.getOrNull()
        }.sortedBy { it.id }
    }

    fun read(id: String): ShareContent {
        requireValid(id)
        if (!meta(id).isFile || !body(id).isFile) throw NotFound()
        try {
            val d = readMeta(id)
            val plain = cipher.decrypt(body(id).readBytes())
            return if (d.kind == ShareKind.TEXT) {
                ShareContent(d, text = String(plain, Charsets.UTF_8))
            } else {
                ShareContent(d, bytes = plain)
            }
        } catch (e: Exception) {
            discard(id)
            throw DecryptFailed(e)
        }
    }

    fun discard(id: String) {
        requireValid(id)
        body(id).delete()
        meta(id).delete()
        File(dir, "$id.bin.tmp").delete()
        File(dir, "$id.meta.tmp").delete()
    }

    /** Deletes anything (including orphans and `.tmp` leftovers) older than [ShareLimits.STALE_AFTER_MS]. */
    fun purgeStale() {
        val cutoff = clock() - ShareLimits.STALE_AFTER_MS
        dir.listFiles()?.forEach { if (it.isFile && it.lastModified() < cutoff) it.delete() }
    }

    private fun writeMeta(d: ShareDescriptor) {
        val raw = ByteArrayOutputStream()
        DataOutputStream(raw).use {
            it.writeInt(d.kind.raw)
            it.writeUTF(d.mimeType)
            it.writeLong(d.sizeBytes)
            it.writeLong(d.receivedAtMs)
        }
        val tmp = File(dir, "${d.id}.meta.tmp")
        val fos = FileOutputStream(tmp)
        try {
            cipher.wrapEncrypt(NonClosing(fos)).use { it.write(raw.toByteArray()) }
            fos.fd.sync()
        } finally {
            fos.close()
        }
        if (!tmp.renameTo(meta(d.id))) {
            tmp.delete()
            throw IOException("rename failed")
        }
    }

    private fun readMeta(id: String): ShareDescriptor {
        val plain = cipher.decrypt(meta(id).readBytes())
        DataInputStream(plain.inputStream()).use {
            val kind = ShareKind.ofRaw(it.readInt()) ?: throw IOException("bad meta")
            return ShareDescriptor(id, kind, it.readUTF(), it.readLong(), it.readLong())
        }
    }

    private fun body(id: String) = File(dir, "$id.bin")
    private fun meta(id: String) = File(dir, "$id.meta")

    private fun requireValid(id: String) {
        if (!ID.matches(id)) throw NotFound()
    }

    private class NonClosing(out: OutputStream) : FilterOutputStream(out) {
        override fun write(b: ByteArray, off: Int, len: Int) = out.write(b, off, len)
        override fun close() = flush()
    }

    companion object {
        val ID = Regex("[0-9a-f]{28}")
        private val random = SecureRandom()

        /** 12 hex chars of time (sortable) + 16 hex chars of randomness. */
        fun randomId(): String {
            val time = System.currentTimeMillis().toString(16).padStart(12, '0').takeLast(12)
            val rnd = ByteArray(8).also { random.nextBytes(it) }
            return time + rnd.joinToString("") { "%02x".format(it) }
        }
    }
}
