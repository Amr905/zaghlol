package app.zaghlol.platform.share

import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.FilterOutputStream
import java.io.IOException
import java.io.OutputStream
import java.security.GeneralSecurityException
import java.security.SecureRandom
import javax.crypto.AEADBadTagException

/**
 * Encrypted store for pending shares in app-private no-backup storage
 * (T-165: callers pass `noBackupFilesDir/share`, a directory of its own, F8).
 * Each share is `<id>.bin` (body) plus `<id>.meta` (kind, MIME, size, time);
 * both are encrypted and bound to the id (and the body to the kind) as GCM
 * AAD. The meta file is written last and marks a committed share.
 *
 * Caps (F2): at most [maxPending] shares and [maxBytes] on disk
 * (defaults [ShareLimits.MAX_PENDING_SHARES], [ShareLimits.MAX_PENDING_BYTES]); [newWriter] and [Writer.write]
 * throw [Full] beyond them. Writes are expected from one thread at a time
 * (the share activity's single worker), so the caps are not re-checked
 * across concurrent writers.
 *
 * Nothing here logs.
 */
class ShareStore(
    private val dir: File,
    private val cipher: ShareCipher,
    private val clock: () -> Long = System::currentTimeMillis,
    private val newId: () -> String = { randomId() },
    private val maxPending: Int = ShareLimits.MAX_PENDING_SHARES,
    private val maxBytes: Long = ShareLimits.MAX_PENDING_BYTES,
) {
    class NotFound : Exception("unknown share")

    /** The share is not authentic (tampered, wrong key) or malformed; it has been deleted. */
    class DecryptFailed(cause: Throwable) : Exception("share could not be decrypted", cause)

    /** Reading failed for a reason that may go away (I/O, Keystore busy); the share is kept. */
    class Transient(cause: Throwable) : Exception("share could not be read now", cause)

    /** The pending-share caps are reached. */
    class Full : Exception("share store full")

    private class Corrupt : Exception("malformed share")

    /** An in-progress encrypted write. Call [commit] or [abort] exactly once. */
    inner class Writer internal constructor(
        private val id: String,
        private val kind: ShareKind,
        private val mime: String,
        private val budget: Long,
    ) {
        private val bodyTmp = File(dir, "$id.bin.tmp")
        private val fos = FileOutputStream(bodyTmp)
        private val enc: OutputStream = try {
            cipher.wrapEncrypt(NonClosing(fos), bodyAad(id, kind))
        } catch (e: Throwable) {
            fos.close()
            bodyTmp.delete()
            throw e
        }
        private var size = 0L

        fun write(buf: ByteArray, off: Int, len: Int) {
            if (size + len > budget) throw Full()
            enc.write(buf, off, len)
            size += len
        }

        fun commit(): ShareDescriptor {
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

    /** Throws [Full] when no further share fits. Cheap; call it before reading a sender's stream. */
    fun ensureCapacity() {
        capacity()
    }

    fun newWriter(kind: ShareKind, mime: String): Writer {
        val budget = capacity()
        return Writer(newId(), kind, mime, budget)
    }

    /** Pending shares, oldest first. Also purges stale files. Unreadable entries are skipped, not deleted. */
    fun list(): List<ShareDescriptor> {
        purgeStale()
        val files = dir.listFiles { f -> f.name.endsWith(".meta") } ?: return emptyList()
        return files.mapNotNull { f ->
            val id = f.name.removeSuffix(".meta")
            if (!ID.matches(id)) null else runCatching { readMeta(id, f.readBytes()) }.getOrNull()
        }.sortedBy { it.id }
    }

    /**
     * Decrypted content, in memory only. Throws [NotFound] (unknown id),
     * [DecryptFailed] (not authentic or malformed: the share is deleted) or
     * [Transient] (I/O or Keystore failure: the share is kept, F6).
     */
    fun read(id: String): ShareContent {
        requireValid(id)
        if (!meta(id).isFile || !body(id).isFile) throw NotFound()
        val metaBytes = readFile(meta(id))
        val bodyBytes = readFile(body(id))
        val d = authentic(id) { readMeta(id, metaBytes) }
        val plain = authentic(id) { cipher.decrypt(bodyBytes, bodyAad(id, d.kind)) }
        if (plain.size.toLong() != d.sizeBytes) {
            discard(id)
            throw DecryptFailed(Corrupt())
        }
        return if (d.kind == ShareKind.TEXT) {
            ShareContent(d, text = String(plain, Charsets.UTF_8))
        } else {
            ShareContent(d, bytes = plain)
        }
    }

    fun discard(id: String) {
        requireValid(id)
        body(id).delete()
        meta(id).delete()
        File(dir, "$id.bin.tmp").delete()
        File(dir, "$id.meta.tmp").delete()
    }

    /** Deletes anything in this store's own directory (orphans and `.tmp` leftovers too) older than [ShareLimits.STALE_AFTER_MS]. */
    fun purgeStale() {
        val cutoff = clock() - ShareLimits.STALE_AFTER_MS
        dir.listFiles()?.forEach { if (it.isFile && it.lastModified() < cutoff) it.delete() }
    }

    /** Purges, checks both caps and returns the byte budget left for one new share. */
    private fun capacity(): Long {
        dir.mkdirs()
        purgeStale()
        val files = dir.listFiles()?.filter { it.isFile }.orEmpty()
        val pending = files.count { it.name.endsWith(".meta") || it.name.endsWith(".bin.tmp") }
        if (pending >= maxPending) throw Full()
        val left = maxBytes - files.sumOf { it.length() }
        if (left <= 0) throw Full()
        return left
    }

    private fun readFile(f: File): ByteArray = try {
        f.readBytes()
    } catch (_: FileNotFoundException) {
        throw NotFound()
    } catch (e: IOException) {
        throw Transient(e)
    }

    /** Deletes only on proof that the data is bad (F6); anything else is transient. */
    private inline fun <T> authentic(id: String, block: () -> T): T = try {
        block()
    } catch (e: AEADBadTagException) {
        discard(id)
        throw DecryptFailed(e)
    } catch (e: Corrupt) {
        discard(id)
        throw DecryptFailed(e)
    } catch (e: GeneralSecurityException) {
        throw Transient(e)
    } catch (e: RuntimeException) {
        // Keystore failures surface as ProviderException / IllegalStateException.
        throw Transient(e)
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
            cipher.wrapEncrypt(NonClosing(fos), metaAad(d.id)).use { it.write(raw.toByteArray()) }
            fos.fd.sync()
        } finally {
            fos.close()
        }
        if (!tmp.renameTo(meta(d.id))) {
            tmp.delete()
            throw IOException("rename failed")
        }
    }

    private fun readMeta(id: String, encrypted: ByteArray): ShareDescriptor {
        val plain = cipher.decrypt(encrypted, metaAad(id))
        try {
            DataInputStream(plain.inputStream()).use {
                val kind = ShareKind.ofRaw(it.readInt()) ?: throw Corrupt()
                return ShareDescriptor(id, kind, it.readUTF(), it.readLong(), it.readLong())
            }
        } catch (_: IOException) {
            throw Corrupt()
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

        /** GCM AAD (F11): binds the meta file to its id. */
        fun metaAad(id: String): ByteArray = "zaghlol.share.v1|meta|$id".toByteArray(Charsets.US_ASCII)

        /** GCM AAD (F11): binds the body file to its id and kind. */
        fun bodyAad(id: String, kind: ShareKind): ByteArray =
            "zaghlol.share.v1|body|$id|${kind.raw}".toByteArray(Charsets.US_ASCII)

        /** 12 hex chars of time (sortable) + 16 hex chars of randomness. */
        fun randomId(): String {
            val time = System.currentTimeMillis().toString(16).padStart(12, '0').takeLast(12)
            val rnd = ByteArray(8).also { random.nextBytes(it) }
            return time + rnd.joinToString("") { "%02x".format(it) }
        }
    }
}
