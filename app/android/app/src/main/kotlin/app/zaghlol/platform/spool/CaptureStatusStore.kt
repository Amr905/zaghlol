package app.zaghlol.platform.spool

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.nio.file.NoSuchFileException
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.AEADBadTagException

/**
 * Alert counters of the capture path (T-039 design note section 5). Counts
 * are unsigned 32-bit and saturate; times are wall-clock ms, -1 = none.
 * Holds no message content.
 */
data class CaptureStatus(
    val seq: Long = 0,
    val refusedFull: Long = 0,
    val refusedGeneric: Long = 0,
    val rateLimited: Long = 0,
    val missedNotifications: Long = 0,
    val firstMissedSmsAtMs: Long = -1,
    val lastRefusedAtMs: Long = -1,
    val decryptDeleted: Long = 0,
    val keyInvalidatedAtMs: Long = -1,
)

/** The status file can't be read now (I/O or Keystore); nothing was overwritten. */
class CaptureStatusUnavailableException : Exception("CAPTURE_STATUS_UNAVAILABLE")

/**
 * `noBackupFilesDir/capture/status.bin`: AES-GCM with the spool key, AAD
 * `zaghlol.capture.v1|status`, a fixed binary record v1 (platform-channels.md
 * 1.3). Written only on an alert (a refusal, a rate-limit drop of a kept
 * message, a delete-on-proof, a lost key) and on [clear]; never for a normal
 * keep or a non-financial drop, so a personal SMS leaves no file.
 *
 * Failure rules (self-check section 1):
 * - Absent file → all zero.
 * - Tag failure / malformed on the first attempt and the 100/300/900 ms
 *   retries (proof, e.g. the spool key was lost) → restart from zero with
 *   `keyInvalidatedAtMs = now` and a fresh random `seq` (so a `clear` with an
 *   old seq can't match), then overwrite.
 * - I/O or Keystore error in any attempt → the alert stays in memory as a
 *   pending delta, merged at the next successful read; the unread file is
 *   never overwritten.
 *
 * Every alert and every [clear] advances `seq`; [clear] zeroes the counters
 * only if the caller's `seq` still matches, so alerts that arrived after the
 * caller's read survive.
 *
 * Invariant (T-039 review #1): the lock and the pending in-memory delta
 * belong to the **file**, not to the instance. Every `CaptureStatusStore` in
 * the process over the same canonical file path shares them, so two instances
 * never write the fixed `status.bin.tmp` at the same time and a delta is
 * merged exactly once, as if there were one instance.
 */
class CaptureStatusStore(
    private val file: File,
    private val cipher: SpoolCipher,
    private val sleep: (Long) -> Unit = Thread::sleep,
    private val wallClock: () -> Long = System::currentTimeMillis,
    private val files: SpoolFileOps = DefaultSpoolFileOps,
    private val randomSeq: () -> Long = { SecureRandom().nextInt().toLong() and U32_MAX },
) {
    /** Per-file state shared by every instance over the same path. */
    private class Shared {
        val lock = Any()

        /** Under [lock]. */
        var pending = Delta()
    }

    private val shared: Shared = SHARED.computeIfAbsent(SpoolStore.canonicalKey(file)) { Shared() }
    private val lock get() = shared.lock
    private var pending: Delta
        get() = shared.pending
        set(value) {
            shared.pending = value
        }

    /** A spool write was refused (store lock held by the caller; lock order store → status). */
    fun recordRefused(reason: RefusalReason, channel: String, wallMs: Long) = record {
        when (reason) {
            RefusalReason.FULL -> refusedFull++
            RefusalReason.GENERIC_BUDGET, RefusalReason.GENERIC_RATE -> refusedGeneric++
        }
        lastRefusedAtMs = maxOf(lastRefusedAtMs, wallMs)
        missed(channel, wallMs)
    }

    /**
     * A message the Guard kept was dropped by the per-sender rate limit
     * (T-040/T-043). SMS are recovered by the catch-up from
     * `firstMissedSmsAtMs`; notifications are counted as missed.
     */
    fun recordRateLimited(channel: String, wallMs: Long) = record {
        rateLimited++
        missed(channel, wallMs)
    }

    /** [count] entries were proven not authentic and deleted. */
    fun recordDecryptDeleted(count: Int) {
        if (count <= 0) return
        record { decryptDeleted += count }
    }

    /** An entry written under an earlier spool key was found (and is about to be deleted). */
    fun recordKeyInvalidated(wallMs: Long) = record { keyInvalidated = earliest(keyInvalidated, wallMs) }

    /**
     * The alerts of one drain (FU-104 #8), recorded with one status write
     * (none when the drain found nothing). Never throws.
     */
    fun recordDrain(scope: SpoolStore.DrainScope) {
        val deleted = scope.decryptDeleted
        val keyAt = scope.keyInvalidatedAtMs
        if (deleted <= 0 && keyAt < 0) return
        record {
            if (deleted > 0) decryptDeleted += deleted
            if (keyAt >= 0) keyInvalidated = earliest(keyInvalidated, keyAt)
        }
    }

    /**
     * The current status with any pending in-memory alerts merged (and
     * persisted when possible). Throws [CaptureStatusUnavailableException]
     * when the file can't be read now.
     */
    fun read(): CaptureStatus = synchronized(lock) { mergedLocked() }

    /**
     * Zeroes the counters if [seq] is still current (compare-and-clear).
     * Returns false (and changes nothing) for a stale seq. Throws on I/O.
     */
    fun clear(seq: Long): Boolean = synchronized(lock) {
        val current = mergedLocked()
        if (current.seq != seq) return false
        writeLocked(CaptureStatus(seq = (current.seq + 1) and U32_MAX))
        // A delta whose own write failed is part of `current` (the caller saw
        // it under this seq), so it is cleared with the counters, not re-added.
        pending = Delta()
        true
    }

    /** Never throws: an alert that can't be persisted now stays in memory. */
    private fun record(change: Delta.() -> Unit) {
        synchronized(lock) {
            pending.change()
            pending.changes++
            try {
                mergedLocked()
            } catch (_: Exception) {
                // Kept in memory; merged at the next successful read.
            }
        }
    }

    private fun mergedLocked(): CaptureStatus {
        val (base, mustWrite) = when (val loaded = loadLocked()) {
            Loaded.Absent -> CaptureStatus() to false
            is Loaded.Ok -> loaded.status to false
            // Proven unreadable (lost key or corrupt): restart, flagged as a key loss.
            Loaded.Unreadable -> CaptureStatus(seq = randomSeq(), keyInvalidatedAtMs = wallClock()) to true
            Loaded.Unavailable -> throw CaptureStatusUnavailableException()
        }
        if (pending.changes == 0 && !mustWrite) return base
        val next = if (pending.changes == 0) base else pending.applyTo(base)
        try {
            writeLocked(next)
            pending = Delta()
        } catch (_: Exception) {
            // The file is unchanged; the delta stays pending (no double count).
        }
        return next
    }

    private sealed class Loaded {
        object Absent : Loaded()
        class Ok(val status: CaptureStatus) : Loaded()
        object Unreadable : Loaded()
        object Unavailable : Loaded()
    }

    private fun loadLocked(): Loaded {
        for ((attempt, delayMs) in SpoolStore.RETRY_DELAYS_MS.withIndex()) {
            if (attempt > 0) sleep(delayMs)
            val bytes = try {
                readBounded()
            } catch (_: NoSuchFileException) {
                return Loaded.Absent
            } catch (_: FileNotFoundException) {
                // Also EACCES / EMFILE: "absent" (and so a fresh file) only when proven.
                return if (SpoolStore.isProvenAbsent(file)) Loaded.Absent else Loaded.Unavailable
            } catch (_: TooLarge) {
                continue // proof
            } catch (_: IOException) {
                return Loaded.Unavailable
            }
            if (bytes.size < SpoolCipher.NONCE_BYTES + SpoolCipher.TAG_BYTES) continue // proof
            try {
                val plain = cipher.decrypt(bytes, AAD)
                return Loaded.Ok(decode(plain))
            } catch (_: AEADBadTagException) {
                // proof; retry per schedule
            } catch (_: FormatException) {
                // proof; retry per schedule
            } catch (_: Exception) {
                return Loaded.Unavailable // Keystore / provider: proves nothing
            }
        }
        return Loaded.Unreadable
    }

    private fun writeLocked(s: CaptureStatus) {
        val dir = file.parentFile ?: throw IOException("STATUS_DIR")
        if (!dir.isDirectory && !dir.mkdirs() && !dir.isDirectory) throw IOException("STATUS_DIR")
        val sealed = cipher.encrypt(encode(s), AAD)
        val tmp = File(dir, file.name + SpoolStore.TMP_SUFFIX)
        try {
            files.open(tmp).use { out ->
                files.write(out, sealed)
                files.sync(out)
            }
            files.move(tmp, file)
        } catch (e: Exception) {
            tmp.delete()
            throw e
        }
        try {
            files.syncDir(dir)
        } catch (_: Throwable) {
            // best effort
        }
    }

    private class TooLarge : IOException("STATUS_TOO_LARGE")

    private class FormatException : Exception("STATUS_FORMAT")

    private fun readBounded(): ByteArray {
        file.inputStream().use { input ->
            val buf = ByteArrayOutputStream()
            val chunk = ByteArray(256)
            while (true) {
                val n = input.read(chunk)
                if (n < 0) break
                buf.write(chunk, 0, n)
                if (buf.size() > MAX_FILE_BYTES) throw TooLarge()
            }
            return buf.toByteArray()
        }
    }

    /** Pending alerts not yet persisted. Additive counters, earliest/latest times. */
    private class Delta {
        var changes = 0
        var refusedFull = 0L
        var refusedGeneric = 0L
        var rateLimited = 0L
        var missedNotifications = 0L
        var firstMissedSms = -1L
        var lastRefusedAtMs = -1L
        var decryptDeleted = 0L
        var keyInvalidated = -1L

        fun missed(channel: String, wallMs: Long) {
            when (channel) {
                CHANNEL_SMS -> firstMissedSms = earliest(firstMissedSms, wallMs)
                CHANNEL_NOTIFICATION -> missedNotifications++
            }
        }

        fun applyTo(s: CaptureStatus) = CaptureStatus(
            seq = (s.seq + changes) and U32_MAX,
            refusedFull = sat(s.refusedFull + refusedFull),
            refusedGeneric = sat(s.refusedGeneric + refusedGeneric),
            rateLimited = sat(s.rateLimited + rateLimited),
            missedNotifications = sat(s.missedNotifications + missedNotifications),
            firstMissedSmsAtMs = earliest(s.firstMissedSmsAtMs, firstMissedSms),
            lastRefusedAtMs = maxOf(s.lastRefusedAtMs, lastRefusedAtMs),
            decryptDeleted = sat(s.decryptDeleted + decryptDeleted),
            keyInvalidatedAtMs = earliest(s.keyInvalidatedAtMs, keyInvalidated),
        )
    }

    companion object {
        /** One [Shared] per canonical status file path, for the whole process. */
        private val SHARED = ConcurrentHashMap<String, Shared>()

        const val VERSION = 1
        const val U32_MAX = 0xFFFF_FFFFL
        const val CHANNEL_SMS = "sms"
        const val CHANNEL_NOTIFICATION = "notification"
        const val RECORD_BYTES = 1 + 4 * 5 + 8 + 8 + 4 + 8
        private const val MAX_FILE_BYTES = 1024
        val AAD: ByteArray get() = "zaghlol.capture.v1|status".toByteArray(Charsets.UTF_8)

        private fun sat(v: Long) = if (v < 0 || v > U32_MAX) U32_MAX else v

        /** Earliest of two optional times (-1 = none). */
        private fun earliest(a: Long, b: Long) = when {
            a < 0 -> b
            b < 0 -> a
            else -> minOf(a, b)
        }

        /** `u8 v=1 | seq u32 | refusedFull u32 | refusedGeneric u32 | rateLimited u32 | missedNotifications u32 |
         *  firstMissedSmsAtMs i64 | lastRefusedAtMs i64 | decryptDeleted u32 | keyInvalidatedAtMs i64` (big-endian). */
        internal fun encode(s: CaptureStatus): ByteArray {
            val bos = ByteArrayOutputStream(RECORD_BYTES)
            DataOutputStream(bos).use { out ->
                out.writeByte(VERSION)
                out.writeInt(s.seq.toInt())
                out.writeInt(s.refusedFull.toInt())
                out.writeInt(s.refusedGeneric.toInt())
                out.writeInt(s.rateLimited.toInt())
                out.writeInt(s.missedNotifications.toInt())
                out.writeLong(s.firstMissedSmsAtMs)
                out.writeLong(s.lastRefusedAtMs)
                out.writeInt(s.decryptDeleted.toInt())
                out.writeLong(s.keyInvalidatedAtMs)
            }
            return bos.toByteArray()
        }

        internal fun decode(b: ByteArray): CaptureStatus {
            if (b.size != RECORD_BYTES) throw FormatException()
            DataInputStream(ByteArrayInputStream(b)).use { input ->
                if (input.readUnsignedByte() != VERSION) throw FormatException()
                fun u32() = input.readInt().toLong() and U32_MAX
                fun time(): Long = input.readLong().also { if (it < -1) throw FormatException() }
                return CaptureStatus(
                    seq = u32(),
                    refusedFull = u32(),
                    refusedGeneric = u32(),
                    rateLimited = u32(),
                    missedNotifications = u32(),
                    firstMissedSmsAtMs = time(),
                    lastRefusedAtMs = time(),
                    decryptDeleted = u32(),
                    keyInvalidatedAtMs = time(),
                )
            }
        }
    }
}
