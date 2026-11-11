package app.zaghlol.platform.guard

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.NoSuchFileException
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import javax.crypto.AEADBadTagException

/** Why a user-part write failed. */
enum class GuardWriteError {
    /** The JSON did not pass the reader (or is over 64 KB); nothing was written. */
    CONFIG_INVALID,

    /** Keystore or file-system failure; the previous file is still in force. */
    IO_ERROR,
}

/**
 * A failed `writeGuardConfig`. Carries the error and, for
 * [GuardWriteError.CONFIG_INVALID], the reader's code and JSON path; never a
 * value from the config.
 */
class GuardConfigWriteException(val error: GuardWriteError, val detail: GuardConfigError? = null) :
    RuntimeException(if (detail == null) error.name else "${error.name} (${detail.code} at ${detail.path})") {
    override fun fillInStackTrace(): Throwable = this
}

/** File operations of the store, a seam for fault injection in tests. */
interface GuardFileOps {
    /**
     * Reads at most [max] + 1 bytes of [file]. Returns null only when the file
     * is positively absent (`NoSuchFileException`); any other failure throws
     * (it proves nothing about the file).
     */
    fun readBounded(file: File, max: Int): ByteArray?

    fun ensureDir(dir: File)

    /** Writes [data] to [file] (truncating) and fsyncs it. */
    fun writeAndSync(file: File, data: ByteArray)

    /** Atomically replaces [to] with [from]. */
    fun atomicReplace(from: File, to: File)

    /** Best-effort directory fsync after a rename; must not throw. */
    fun syncDir(dir: File)

    fun delete(file: File)
}

/** java.nio implementation. [dirSync] defaults to a `FileChannel` force (JVM); production passes `Os.fsync`. */
class DefaultGuardFileOps(private val dirSync: (File) -> Unit = ::channelSyncDir) : GuardFileOps {
    override fun readBounded(file: File, max: Int): ByteArray? {
        val input = try {
            Files.newInputStream(file.toPath())
        } catch (e: NoSuchFileException) {
            return null
        }
        return input.use { BaseConfigSource.readBounded(it, max) }
    }

    override fun ensureDir(dir: File) {
        Files.createDirectories(dir.toPath())
    }

    override fun writeAndSync(file: File, data: ByteArray) {
        FileOutputStream(file).use { out ->
            out.write(data)
            out.flush()
            out.fd.sync()
        }
    }

    override fun atomicReplace(from: File, to: File) {
        Files.move(from.toPath(), to.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }

    override fun syncDir(dir: File) {
        try {
            dirSync(dir)
        } catch (e: Exception) {
            // Best effort: the rename is already durable on most file systems.
        }
    }

    override fun delete(file: File) {
        try {
            Files.deleteIfExists(file.toPath())
        } catch (e: IOException) {
            // Best effort: a left-over tmp is ignored by the reader and overwritten by the next write.
        }
    }

    companion object {
        fun channelSyncDir(dir: File) {
            FileChannel.open(dir.toPath(), StandardOpenOption.READ).use { it.force(true) }
        }
    }
}

/**
 * The encrypted Guard user part on disk (T-038 design note section 5):
 * `noBackupFilesDir/guard/guard.user.enc`, AES-256-GCM ([GuardUserCipher]),
 * AAD [AAD], written via `.tmp` + fsync + atomic rename + best-effort
 * directory fsync. Holds no state; [GuardRuntime] serializes writes.
 *
 * Never deletes the user file: an unreadable one is reported and kept (the
 * app rewrites it on every start, T-047); a left-over `.tmp` is ignored.
 */
class GuardUserConfigStore(
    val dir: File,
    private val cipher: GuardUserCipher,
    private val ops: GuardFileOps = DefaultGuardFileOps(),
) {
    val file: File = File(dir, FILE_NAME)
    private val tmp: File = File(dir, "$FILE_NAME.tmp")

    /** Outcome of [read]. No case prints content. */
    sealed class Read {
        /** No user file: fresh install. */
        object Absent : Read() {
            override fun toString(): String = "Absent"
        }

        /** Decrypted plaintext; the caller zeroes it after parsing. */
        class Plain(val bytes: ByteArray) : Read() {
            override fun toString(): String = "Plain"
        }

        /** Proven unusable: failed authentication, or a size the writer never produces. */
        object Unreadable : Read() {
            override fun toString(): String = "Unreadable"
        }

        /** I/O or Keystore error: proves nothing, retry on the next message. */
        object Transient : Read() {
            override fun toString(): String = "Transient"
        }
    }

    fun read(): Read {
        val data = try {
            ops.readBounded(file, MAX_FILE_BYTES) ?: return Read.Absent
        } catch (t: Throwable) {
            rethrowIfFatal(t)
            return Read.Transient
        }
        if (data.size > MAX_FILE_BYTES) return Read.Unreadable
        return try {
            Read.Plain(cipher.decrypt(data, AAD))
        } catch (e: AEADBadTagException) {
            Read.Unreadable
        } catch (t: Throwable) {
            rethrowIfFatal(t)
            Read.Transient
        }
    }

    /**
     * Encrypts and atomically replaces the user file. On any failure the
     * previous file is untouched, the tmp is removed and
     * [GuardConfigWriteException] ([GuardWriteError.IO_ERROR]) is thrown.
     * Does not validate [plain]: [GuardRuntime.writeUser] does, first.
     */
    fun write(plain: ByteArray) {
        try {
            ops.ensureDir(dir)
            val cipherText = cipher.encrypt(plain, AAD)
            ops.writeAndSync(tmp, cipherText)
            ops.atomicReplace(tmp, file)
        } catch (t: Throwable) {
            rethrowIfFatal(t)
            ops.delete(tmp)
            throw GuardConfigWriteException(GuardWriteError.IO_ERROR)
        }
        ops.syncDir(dir)
    }

    override fun toString(): String = "GuardUserConfigStore"

    companion object {
        const val DIR_NAME = "guard"
        const val FILE_NAME = "guard.user.enc"

        /** Binds the file to its role (platform-channels section 1.1). */
        val AAD: ByteArray = "zaghlol.guard.v1|user".toByteArray(Charsets.UTF_8)

        /** Largest file the writer can produce: a 64 KB part plus nonce and tag. */
        const val MAX_FILE_BYTES = GuardConfig.MAX_USER_BYTES + GuardUserCipher.NONCE_BYTES + GuardUserCipher.TAG_BYTES

        /** The user-part directory under the no-backup directory (L-1). */
        fun dirUnder(noBackupFilesDir: File): File = File(noBackupFilesDir, DIR_NAME)
    }
}
