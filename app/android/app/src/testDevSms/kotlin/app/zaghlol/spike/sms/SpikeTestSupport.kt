package app.zaghlol.spike.sms

import java.io.File
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

    override fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray {
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

/** Fails the next [failures] decrypts with a Keystore-style transient error. */
class FlakySpoolCipher(var failures: Int, private val message: String = "keystore busy") : SoftwareSpoolCipher() {
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
) = SpoolRecord(
    channel = "sms",
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

fun storeIn(
    dir: File,
    cipher: SpoolCipher = SoftwareSpoolCipher(),
    sleep: RecordingSleep = RecordingSleep(),
    maxEntries: Int = SpoolStore.MAX_ENTRIES,
    maxBytes: Long = SpoolStore.MAX_BYTES,
    clock: () -> Long = System::currentTimeMillis,
) = SpoolStore(dir, cipher, UlidGenerator(), clock, sleep.fn, maxEntries, maxBytes)

class FakeScheduler : IngestScheduler {
    var enqueued = 0
    var fail = false
    override fun enqueue() {
        if (fail) throw IllegalStateException("enqueue failed")
        enqueued++
    }
}
