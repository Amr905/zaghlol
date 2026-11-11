package app.zaghlol.platform.spool

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.security.SecureRandom
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Software AES-256-GCM with the same format and AAD use as [KeystoreSpoolCipher]. Synthetic test key. */
open class SoftwareSpoolCipher(keyBytes: ByteArray = ByteArray(32) { (it * 7).toByte() }) : SpoolCipher {
    private val key = SecretKeySpec(keyBytes, "AES")
    private val random = SecureRandom()
    var decrypts = 0
    var encrypts = 0

    override fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray {
        encrypts++
        val iv = ByteArray(SpoolCipher.NONCE_BYTES).also { random.nextBytes(it) }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
        c.updateAAD(aad)
        return iv + c.doFinal(plain)
    }

    override fun decrypt(data: ByteArray, aad: ByteArray): ByteArray {
        decrypts++
        if (data.size < SpoolCipher.NONCE_BYTES + SpoolCipher.TAG_BYTES) throw AEADBadTagException("truncated")
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, data, 0, SpoolCipher.NONCE_BYTES))
        c.updateAAD(aad)
        return c.doFinal(data, SpoolCipher.NONCE_BYTES, data.size - SpoolCipher.NONCE_BYTES)
    }
}

/** A different synthetic key: decrypting another key's data fails the tag. */
fun otherKeyCipher() = SoftwareSpoolCipher(ByteArray(32) { (it * 13 + 1).toByte() })

/** Fails the next [failures] decrypts (and encrypts while [failEncrypt]) with a Keystore-style transient error. */
class FlakySpoolCipher(
    var failures: Int,
    private val message: String = "keystore busy",
    var failEncrypt: Boolean = false,
) : SoftwareSpoolCipher() {
    override fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray {
        if (failEncrypt) throw IllegalStateException(message)
        return super.encrypt(plain, aad)
    }

    override fun decrypt(data: ByteArray, aad: ByteArray): ByteArray {
        if (failures > 0) {
            failures--
            decrypts++
            throw IllegalStateException(message)
        }
        return super.decrypt(data, aad)
    }
}

fun tempDir(): File = Files.createTempDirectory("spool").toFile().also { it.deleteOnExit() }

fun record(
    body: String = "spike: you paid EGP 12.50 at SYNTH SHOP",
    source: String = "5550100",
    rxNs: Long = 1_000_000L,
    channel: String = "sms",
) = SpoolRecord(
    channel = channel,
    source = source,
    body = body,
    receivedAtMs = 1_700_000_000_000L,
    simSlot = 1,
    guardInst = "spike",
    guardLast4 = null,
    rxElapsedNs = rxNs,
    bootCount = 7,
)

class RecordingSleep {
    val calls = ArrayList<Long>()
    val fn: (Long) -> Unit = { calls += it }
}

/** Monotonic test clock. */
class FakeClock(var now: Long = 1_000_000L) {
    val fn: () -> Long = { now }
}

fun storeIn(
    dir: File,
    cipher: SpoolCipher = SoftwareSpoolCipher(),
    sleep: RecordingSleep = RecordingSleep(),
    limits: SpoolLimits = SpoolLimits(),
    status: CaptureStatusStore? = null,
    keyCreatedAtMs: () -> Long? = { null },
    files: SpoolFileOps = DefaultSpoolFileOps,
    mono: () -> Long = { System.nanoTime() / 1_000_000 },
    wall: () -> Long = System::currentTimeMillis,
    ids: UlidGenerator = UlidGenerator(wall),
) = SpoolStore(
    dir = dir,
    cipher = cipher,
    status = status,
    keyCreatedAtMs = keyCreatedAtMs,
    ids = ids,
    wallClock = wall,
    monoClockMs = mono,
    sleep = sleep.fn,
    files = files,
    limits = limits,
)

fun statusIn(
    dir: File,
    cipher: SpoolCipher = SoftwareSpoolCipher(),
    sleep: RecordingSleep = RecordingSleep(),
    files: SpoolFileOps = DefaultSpoolFileOps,
    wall: () -> Long = { 1_700_000_000_000L },
    seq: () -> Long = { 777L },
) = CaptureStatusStore(File(dir, "capture/status.bin"), cipher, sleep.fn, wall, files, seq)

/** Writes a priority entry and returns its id. */
fun SpoolStore.put(body: String = "m", cls: AdmissionClass = AdmissionClass.PRIORITY, channel: String = "sms"): String =
    (write(record(body = body, channel = channel), cls) as SpoolStore.WriteResult.Written).id

/** The steps of [SpoolFileOps], for fault injection. */
enum class FileStep { OPEN, WRITE, PARTIAL_WRITE, SYNC, MOVE, SYNC_DIR }

/**
 * Real file operations that throw IOException at [failAt] (once, or every
 * time while [sticky]). PARTIAL_WRITE writes half the bytes, then throws.
 */
class FaultyFileOps(var failAt: FileStep?, private val sticky: Boolean = false) : SpoolFileOps {
    val steps = ArrayList<FileStep>()

    private fun hit(step: FileStep): Boolean {
        steps += step
        if (failAt != step) return false
        if (!sticky) failAt = null
        return true
    }

    override fun open(file: File): FileOutputStream {
        if (hit(FileStep.OPEN)) throw IOException("open")
        return DefaultSpoolFileOps.open(file)
    }

    override fun write(out: FileOutputStream, bytes: ByteArray) {
        if (failAt == FileStep.PARTIAL_WRITE && hit(FileStep.PARTIAL_WRITE)) {
            out.write(bytes, 0, bytes.size / 2)
            throw IOException("disk full")
        }
        if (hit(FileStep.WRITE)) throw IOException("write")
        out.write(bytes)
    }

    override fun sync(out: FileOutputStream) {
        if (hit(FileStep.SYNC)) throw IOException("sync")
        out.fd.sync()
    }

    override fun move(from: File, to: File) {
        if (hit(FileStep.MOVE)) throw IOException("rename")
        DefaultSpoolFileOps.move(from, to)
    }

    override fun syncDir(dir: File) {
        if (hit(FileStep.SYNC_DIR)) throw IOException("dirsync")
    }
}
