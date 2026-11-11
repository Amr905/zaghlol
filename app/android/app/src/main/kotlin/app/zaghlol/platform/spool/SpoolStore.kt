package app.zaghlol.platform.spool

import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.NoSuchFileException
import java.nio.file.StandardCopyOption
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.AEADBadTagException

/**
 * Which share of the spool a write may use (T-039 design note section 4,
 * T-035 security L-3). The caller maps the Guard's keep kind: `registry` /
 * `user` → [PRIORITY], `generic` → [GENERIC]. The class is never written to
 * disk (a per-kind file name would leak the content class).
 */
enum class AdmissionClass { PRIORITY, GENERIC }

/** Why a write was refused. Old entries are never evicted for a new one. */
enum class RefusalReason {
    /** 500 entries or 4 MiB on disk. */
    FULL,

    /** A generic keep while the spool already holds half its caps. */
    GENERIC_BUDGET,

    /** More than [SpoolPolicy.GENERIC_PER_WINDOW] generic writes in the window (in memory, per process). */
    GENERIC_RATE,
}

/**
 * Caps of the spool. The total caps come from platform-channels.md 1.3; the
 * generic budget and rate are **provisional — PO to confirm** (T-039 PO Q1),
 * each one constant here.
 */
object SpoolPolicy {
    const val MAX_ENTRIES = 500
    const val MAX_BYTES = 4L * 1024 * 1024

    /** Provisional — PO to confirm (T-039 Q1): generic keeps use at most half the spool. */
    const val GENERIC_MAX_ENTRIES = 250

    /** Provisional — PO to confirm (T-039 Q1). */
    const val GENERIC_MAX_BYTES = 2L * 1024 * 1024

    /** Provisional — PO to confirm (T-039 Q1): at most 10 generic writes per minute, all senders. */
    const val GENERIC_PER_WINDOW = 10

    const val GENERIC_WINDOW_MS = 60_000L
}

/** The spool's limits; tests shrink them, production uses [SpoolPolicy]. */
data class SpoolLimits(
    val maxEntries: Int = SpoolPolicy.MAX_ENTRIES,
    val maxBytes: Long = SpoolPolicy.MAX_BYTES,
    val genericMaxEntries: Int = SpoolPolicy.GENERIC_MAX_ENTRIES,
    val genericMaxBytes: Long = SpoolPolicy.GENERIC_MAX_BYTES,
    val genericPerWindow: Int = SpoolPolicy.GENERIC_PER_WINDOW,
    val genericWindowMs: Long = SpoolPolicy.GENERIC_WINDOW_MS,
)

/**
 * The file steps of an atomic write, behind a seam so JVM tests inject a
 * fault at every step and the instrumented test can halt the process between
 * fsync and rename.
 */
interface SpoolFileOps {
    fun open(file: File): FileOutputStream

    fun write(out: FileOutputStream, bytes: ByteArray)

    fun sync(out: FileOutputStream)

    /** Atomic rename; replaces nothing (the target is a fresh ULID). */
    fun move(from: File, to: File)

    /** Best effort; failures are ignored by the caller. */
    fun syncDir(dir: File)
}

object DefaultSpoolFileOps : SpoolFileOps {
    override fun open(file: File) = FileOutputStream(file)

    override fun write(out: FileOutputStream, bytes: ByteArray) = out.write(bytes)

    override fun sync(out: FileOutputStream) = out.fd.sync()

    override fun move(from: File, to: File) {
        try {
            Files.move(from.toPath(), to.toPath(), StandardCopyOption.ATOMIC_MOVE)
        } catch (_: AtomicMoveNotSupportedException) {
            if (!from.renameTo(to)) throw IOException("SPOOL_RENAME")
        }
    }

    override fun syncDir(dir: File) {
        val fd = Os.open(dir.path, OsConstants.O_RDONLY, 0)
        try {
            Os.fsync(fd)
        } finally {
            Os.close(fd)
        }
    }
}

/**
 * The encrypted spool (platform-channels.md section 1.3, ADR-005; T-008
 * spike productionised by T-039). Directory `noBackupFilesDir/spool/`, one
 * file per message, `<ulid>.bin` = AES-GCM(record) with AAD
 * `zaghlol.spool.v1|entry|<ulid>`.
 *
 * Rules:
 * - At-least-once: an entry is deleted only by [ack] (after the DB commit;
 *   the host scopes acks to what its engine drained) or on proof that it is
 *   not authentic ([read]). I/O and Keystore errors never delete. No age purge.
 * - Admission ([write]): full caps for every keep, a half-spool budget and a
 *   per-minute rate for generic keeps; a refused write is recorded in the
 *   capture status and old entries are never evicted.
 * - No spool-level dedupe: the DB's unique `body_hash` is the only dedupe.
 * - File names never carry content (a ULID only; they reveal receive times,
 *   accepted in platform-channels.md 1.3).
 *
 * Locks: writes and [sweepTmp] hold the store lock; inside it the status
 * lock and then the SpoolKey lock may be taken, never the reverse.
 *
 * Invariant (T-039 review #1): the store lock and the generic rate window
 * belong to the **directory**, not to the instance. Every `SpoolStore` in the
 * process over the same canonical directory path (receiver, listener, one host
 * per engine, ...) shares one lock and one window ([shared]). So no `.tmp` is
 * ever in flight while [sweepTmp] runs on any instance, and the generic rate
 * bound is per process, not per instance. Other processes never open the
 * spool (single-process app, ADR-005).
 */
class SpoolStore(
    private val dir: File,
    private val cipher: SpoolCipher,
    private val status: CaptureStatusStore? = null,
    /** Creation time of the current key (`SpoolKey.creationDateMs`); null = unknown. */
    private val keyCreatedAtMs: () -> Long? = { null },
    private val ids: UlidGenerator = UlidGenerator(),
    private val wallClock: () -> Long = System::currentTimeMillis,
    /** Monotonic milliseconds for the generic rate window (`SystemClock.elapsedRealtime` in production). */
    private val monoClockMs: () -> Long = { System.nanoTime() / 1_000_000 },
    private val sleep: (Long) -> Unit = Thread::sleep,
    private val files: SpoolFileOps = DefaultSpoolFileOps,
    private val limits: SpoolLimits = SpoolLimits(),
) {
    sealed class WriteResult {
        class Written(val id: String) : WriteResult() {
            override fun toString(): String = "Written($id)"
        }

        class Refused(val reason: RefusalReason) : WriteResult() {
            override fun toString(): String = "Refused($reason)"
        }
    }

    sealed class ReadResult {
        class Ok(val record: SpoolRecord) : ReadResult() {
            override fun toString(): String = "Ok(<redacted>)"
        }

        /** Proven not authentic; the entry was deleted. */
        object Deleted : ReadResult()

        /** Already gone (acked or deleted meanwhile). */
        object Missing : ReadResult()

        /** Could not be read now (I/O, Keystore); the entry is kept. */
        object Unavailable : ReadResult()
    }

    /** Per-directory state shared by every instance over the same path. */
    private class Shared {
        val lock = Any()

        /** Monotonic times of the generic writes in the current window (under [lock]). */
        val genericWrites = ArrayDeque<Long>()
    }

    private val shared: Shared = SHARED.computeIfAbsent(canonicalKey(dir)) { Shared() }
    private val lock get() = shared.lock
    private val genericWrites get() = shared.genericWrites

    /**
     * Admits, encrypts and writes [record] atomically: `.tmp`, fsync, atomic
     * rename, best-effort directory fsync. Returns [WriteResult.Refused] when
     * the admission rules say no (recorded in the capture status). Throws
     * IOException / GeneralSecurityException / [SpoolKeyUnavailableException]
     * when the write itself fails; nothing is left behind except possibly a
     * `.tmp` after a crash, swept at the next drain.
     */
    fun write(record: SpoolRecord, cls: AdmissionClass): WriteResult {
        val plain = SpoolRecordCodec.encode(record)
        try {
            synchronized(lock) {
                if (!dir.isDirectory && !dir.mkdirs() && !dir.isDirectory) throw IOException("SPOOL_DIR")
                val listed = dir.listFiles() ?: throw IOException("SPOOL_LIST")
                var n = 0
                var bytes = 0L
                for (f in listed) {
                    if (isEntryName(f.name) || isTmpName(f.name)) {
                        n++
                        bytes += f.length()
                    }
                }
                val after = bytes + plain.size + SpoolCipher.NONCE_BYTES + SpoolCipher.TAG_BYTES
                val now = monoClockMs()
                val reason = when {
                    n >= limits.maxEntries || after > limits.maxBytes -> RefusalReason.FULL
                    cls == AdmissionClass.GENERIC &&
                        (n >= limits.genericMaxEntries || after > limits.genericMaxBytes) -> RefusalReason.GENERIC_BUDGET
                    cls == AdmissionClass.GENERIC && recentGenericWrites(now) >= limits.genericPerWindow ->
                        RefusalReason.GENERIC_RATE
                    else -> null
                }
                if (reason != null) {
                    status?.recordRefused(reason, record.channel, wallClock())
                    return WriteResult.Refused(reason)
                }
                val id = ids.next()
                val sealed = cipher.encrypt(plain, aad(id))
                val tmp = File(dir, "$id.bin$TMP_SUFFIX")
                try {
                    files.open(tmp).use { out ->
                        files.write(out, sealed)
                        files.sync(out)
                    }
                    files.move(tmp, entry(id))
                } catch (e: Exception) {
                    tmp.delete()
                    throw e
                }
                try {
                    files.syncDir(dir)
                } catch (_: Throwable) {
                    // Best effort (design note section 4): the entry is fsynced already.
                }
                if (cls == AdmissionClass.GENERIC) genericWrites.addLast(now)
                return WriteResult.Written(id)
            }
        } finally {
            plain.fill(0)
        }
    }

    private fun recentGenericWrites(now: Long): Int {
        while (genericWrites.isNotEmpty() && now - genericWrites.first() >= limits.genericWindowMs) {
            genericWrites.removeFirst()
        }
        return genericWrites.size
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
     *
     * Lost key (design note section 2, FU-086 I-3): when the **first** attempt
     * fails the GCM tag on a full-length entry whose ULID time is before the
     * current key's creation date, the entry was written under an earlier key.
     * It is deleted at once (no ladder) and `keyInvalidatedAtMs` is recorded
     * first. The clock only chooses ladder or not; a deletion always needs a
     * tag failure.
     */
    fun read(id: String): ReadResult {
        if (!UlidGenerator.isValid(id)) return ReadResult.Missing
        var transient = false
        for ((attempt, delayMs) in RETRY_DELAYS_MS.withIndex()) {
            if (attempt > 0) sleep(delayMs)
            val bytes = try {
                readBounded(entry(id))
            } catch (_: NoSuchFileException) {
                return ReadResult.Missing
            } catch (_: FileNotFoundException) {
                // Also raised for EACCES / EMFILE: absent only when proven.
                if (isProvenAbsent(entry(id))) return ReadResult.Missing
                transient = true
                continue
            } catch (_: TooLarge) {
                null // proof: not a record we wrote
            } catch (_: IOException) {
                transient = true
                continue
            }
            if (bytes == null || bytes.size < SpoolCipher.NONCE_BYTES + SpoolCipher.TAG_BYTES) continue // proof
            try {
                val plain = cipher.decrypt(bytes, aad(id))
                try {
                    return ReadResult.Ok(SpoolRecordCodec.decode(plain))
                } finally {
                    plain.fill(0)
                }
            } catch (_: AEADBadTagException) {
                if (attempt == 0 && !transient && writtenBeforeCurrentKey(id)) {
                    status?.recordKeyInvalidated(wallClock())
                    return deleteOnProof(id)
                }
                // proof; retry per schedule
            } catch (_: SpoolFormatException) {
                // proof; retry per schedule
            } catch (_: Exception) {
                // Keystore / provider failure: proves nothing.
                transient = true
            }
        }
        if (transient) return ReadResult.Unavailable
        return deleteOnProof(id)
    }

    private fun writtenBeforeCurrentKey(id: String): Boolean {
        val created = try {
            keyCreatedAtMs()
        } catch (_: Exception) {
            null
        } ?: return false
        return UlidGenerator.timeMs(id) < created
    }

    private fun deleteOnProof(id: String): ReadResult {
        val f = entry(id)
        if (f.delete()) return ReadResult.Deleted
        return try {
            Files.readAttributes(f.toPath(), "basic:size")
            ReadResult.Unavailable // still there: keep, retried at the next drain
        } catch (_: NoSuchFileException) {
            ReadResult.Missing // acked meanwhile
        } catch (_: Exception) {
            ReadResult.Unavailable
        }
    }

    /**
     * Deletes the given entries. Idempotent; malformed ids are ignored. The
     * caller ([app.zaghlol.platform.capture.AndroidCaptureHost]) passes only ids
     * its engine drained.
     */
    fun ack(ids: Collection<String>): Int {
        var deleted = 0
        for (id in ids) {
            if (!UlidGenerator.isValid(id)) continue
            if (entry(id).delete()) deleted++
        }
        return deleted
    }

    /**
     * Deletes every spool `.tmp`. Runs under the store lock, where no write is
     * in flight (single process; writes hold the lock from tmp to rename, and
     * the lock is shared by every instance over this directory), so
     * any `.tmp` seen here is a leftover of a killed write. No age rule, so a
     * clock change can neither keep nor lose one. Foreign files are untouched.
     */
    fun sweepTmp(): Int = synchronized(lock) {
        val names = dir.list() ?: return 0
        var swept = 0
        for (name in names) {
            if (isTmpName(name) && File(dir, name).delete()) swept++
        }
        swept
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

    private fun entry(id: String) = File(dir, "$id.bin")

    companion object {
        const val TMP_SUFFIX = ".tmp"

        /** One [Shared] per canonical directory path, for the whole process. */
        private val SHARED = ConcurrentHashMap<String, Shared>()

        /** The key of a path in the process-wide lock maps (canonical when it can be resolved). */
        internal fun canonicalKey(f: File): String = try {
            f.canonicalPath
        } catch (_: IOException) {
            f.absoluteFile.normalize().path
        }
        val MAX_FILE_BYTES = SpoolRecordCodec.MAX_RECORD_BYTES + SpoolCipher.NONCE_BYTES + SpoolCipher.TAG_BYTES

        /** First attempt, then 3 retries (T-008 design note section 4). */
        val RETRY_DELAYS_MS = longArrayOf(0, 100, 300, 900)

        /**
         * True only when the file positively does not exist (`NoSuchFileException`).
         * `FileNotFoundException` and `File.exists()` also mean "permission
         * denied" or "too many open files", which prove nothing (self-check 1).
         */
        fun isProvenAbsent(f: File): Boolean = try {
            Files.readAttributes(f.toPath(), "basic:size")
            false
        } catch (_: NoSuchFileException) {
            true
        } catch (_: Exception) {
            false
        }

        fun aad(id: String): ByteArray = "zaghlol.spool.v1|entry|$id".toByteArray(Charsets.UTF_8)

        fun isEntryName(name: String): Boolean =
            name.length == 30 && name.endsWith(".bin") && UlidGenerator.isValid(name.substring(0, 26))

        fun isTmpName(name: String): Boolean =
            name.length == 34 && name.endsWith(".bin$TMP_SUFFIX") && UlidGenerator.isValid(name.substring(0, 26))
    }
}
