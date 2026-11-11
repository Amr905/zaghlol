package app.zaghlol.spike.sms

import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.NoSuchFileException
import java.nio.file.StandardCopyOption
import javax.crypto.AEADBadTagException

/**
 * The encrypted SMS spool (platform-channels.md section 1.3, ADR-005;
 * T-008 design note section 4). Directory `noBackupFilesDir/spool/`, one
 * file per message, `<ulid>.bin` = AES-GCM(record) with AAD
 * `zaghlol.spool.v1|entry|<ulid>`.
 *
 * Rules:
 * - At-least-once: an entry is deleted only by [ack] (after the DB commit) or
 *   on proof that it is not authentic ([read], after the retry schedule).
 *   I/O and Keystore errors never delete. No age purge.
 * - Caps: [maxEntries] entries or [maxBytes] on disk; a new message beyond
 *   either is refused ([WriteResult.Full]); old entries are never evicted.
 * - No spool-level dedupe: the DB's unique `body_hash` is the only dedupe.
 * - File names never carry content (a ULID only).
 */
class SpoolStore(
    private val dir: File,
    private val cipher: SpoolCipher,
    private val ids: UlidGenerator = UlidGenerator(),
    private val clock: () -> Long = System::currentTimeMillis,
    private val sleep: (Long) -> Unit = Thread::sleep,
    private val maxEntries: Int = MAX_ENTRIES,
    private val maxBytes: Long = MAX_BYTES,
) {
    sealed class WriteResult {
        data class Written(val id: String) : WriteResult()
        object Full : WriteResult()
    }

    sealed class ReadResult {
        class Ok(val record: SpoolRecord) : ReadResult() {
            override fun toString(): String = "Ok(<redacted>)"
        }

        /** Proven not authentic after every attempt; the entry was deleted. */
        object Deleted : ReadResult()

        /** Already gone (acked or deleted meanwhile). */
        object Missing : ReadResult()

        /** Could not be read now (I/O, Keystore); the entry is kept. */
        object Unavailable : ReadResult()
    }

    private val lock = Any()

    /**
     * Encrypts and writes [record] atomically: `.tmp`, fsync, rename. Throws
     * IOException / GeneralSecurityException on failure (nothing is left
     * behind except possibly a `.tmp`, swept later).
     */
    fun write(record: SpoolRecord): WriteResult {
        val plain = SpoolRecordCodec.encode(record)
        try {
            synchronized(lock) {
                if (!dir.isDirectory && !dir.mkdirs() && !dir.isDirectory) throw IOException("SPOOL_DIR")
                val files = dir.listFiles() ?: throw IOException("SPOOL_LIST")
                val used = files.filter { isEntryName(it.name) || it.name.endsWith(TMP_SUFFIX) }
                val estimate = plain.size + SpoolCipher.NONCE_BYTES + SpoolCipher.TAG_BYTES
                if (used.size >= maxEntries || used.sumOf { it.length() } + estimate > maxBytes) {
                    return WriteResult.Full
                }
                val id = ids.next()
                val sealed = cipher.encrypt(plain, aad(id))
                val tmp = File(dir, "$id.bin$TMP_SUFFIX")
                try {
                    FileOutputStream(tmp).use { out ->
                        out.write(sealed)
                        out.fd.sync()
                    }
                    move(tmp, entry(id))
                } catch (e: IOException) {
                    tmp.delete()
                    throw e
                }
                return WriteResult.Written(id)
            }
        } finally {
            plain.fill(0)
        }
    }

    /** Pending entry ids, oldest first. Foreign file names are ignored. */
    fun pendingIds(): List<String> {
        val names = dir.list() ?: return emptyList()
        return names.filter(::isEntryName).map { it.removeSuffix(".bin") }.sorted()
    }

    fun pendingCount(): Int = pendingIds().size

    /**
     * Reads and decrypts one entry. Not authentic (tag failure, truncation,
     * malformed record) is retried at 100/300/900 ms; only when every attempt
     * proves it bad is the entry deleted ([ReadResult.Deleted]). Any other
     * failure in any attempt keeps it ([ReadResult.Unavailable]).
     */
    fun read(id: String): ReadResult {
        if (!UlidGenerator.isValid(id)) return ReadResult.Missing
        var transient = false
        for ((attempt, delayMs) in RETRY_DELAYS_MS.withIndex()) {
            if (attempt > 0) sleep(delayMs)
            val bytes = try {
                readBounded(entry(id))
            } catch (_: FileNotFoundException) {
                return ReadResult.Missing
            } catch (_: NoSuchFileException) {
                return ReadResult.Missing
            } catch (_: TooLarge) {
                null // proof: not a record we wrote
            } catch (_: IOException) {
                transient = true
                continue
            }
            if (bytes == null) continue
            try {
                val plain = cipher.decrypt(bytes, aad(id))
                try {
                    return ReadResult.Ok(SpoolRecordCodec.decode(plain))
                } finally {
                    plain.fill(0)
                }
            } catch (_: AEADBadTagException) {
                // proof; retry per schedule
            } catch (_: SpoolFormatException) {
                // proof; retry per schedule
            } catch (_: Exception) {
                // Keystore / provider failure: proves nothing.
                transient = true
            }
        }
        if (transient) return ReadResult.Unavailable
        val f = entry(id)
        if (f.delete() || !f.exists()) return ReadResult.Deleted
        return ReadResult.Unavailable
    }

    /** Deletes acknowledged entries. Idempotent; unknown or malformed ids are ignored. */
    fun ack(ids: List<String>): Int {
        var deleted = 0
        for (id in ids) {
            if (!UlidGenerator.isValid(id)) continue
            if (entry(id).delete()) deleted++
        }
        return deleted
    }

    /** Deletes `.tmp` files older than [TMP_STALE_MS]. A file whose age can't be read is kept. */
    fun sweepTmp() {
        val now = clock()
        val files = dir.listFiles() ?: return
        for (f in files) {
            if (!f.name.endsWith(TMP_SUFFIX)) continue
            val modified = f.lastModified()
            if (modified > 0 && now - modified > TMP_STALE_MS) f.delete()
        }
    }

    private class TooLarge : IOException("SPOOL_TOO_LARGE")

    private fun readBounded(f: File): ByteArray {
        f.inputStream().use { input ->
            val buf = java.io.ByteArrayOutputStream()
            val chunk = ByteArray(8192)
            var total = 0
            while (true) {
                val n = input.read(chunk)
                if (n < 0) break
                total += n
                if (total > MAX_FILE_BYTES) throw TooLarge()
                buf.write(chunk, 0, n)
            }
            return buf.toByteArray()
        }
    }

    private fun move(from: File, to: File) {
        try {
            Files.move(from.toPath(), to.toPath(), StandardCopyOption.ATOMIC_MOVE)
        } catch (_: AtomicMoveNotSupportedException) {
            if (!from.renameTo(to)) throw IOException("SPOOL_RENAME")
        }
    }

    private fun entry(id: String) = File(dir, "$id.bin")

    companion object {
        const val MAX_ENTRIES = 500
        const val MAX_BYTES = 4L * 1024 * 1024
        const val TMP_STALE_MS = 60_000L
        const val TMP_SUFFIX = ".tmp"
        val MAX_FILE_BYTES = SpoolRecordCodec.MAX_RECORD_BYTES + SpoolCipher.NONCE_BYTES + SpoolCipher.TAG_BYTES

        /** First attempt, then 3 retries (design note section 4). */
        val RETRY_DELAYS_MS = longArrayOf(0, 100, 300, 900)

        fun aad(id: String): ByteArray = "zaghlol.spool.v1|entry|$id".toByteArray(Charsets.UTF_8)

        fun isEntryName(name: String): Boolean =
            name.length == 30 && name.endsWith(".bin") && UlidGenerator.isValid(name.substring(0, 26))
    }
}
