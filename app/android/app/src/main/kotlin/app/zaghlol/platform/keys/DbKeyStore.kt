package app.zaghlol.platform.keys

import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Result of a slot read. [value] is set only for [SecretStatusMsg.FOUND]. */
class SlotRead(val status: SecretStatusMsg, val value: ByteArray?, val attempts: Int)

/** Thrown by writes; the host maps it to `KEY_STORE_FAILED` with no message. */
class KeyStoreFailure : Exception()

/** One secret slot (platform-channels §5). */
interface SecretSlotStore {
  fun read(): SlotRead

  /** Stores [candidate] unless a usable secret exists; returns the stored value. */
  fun createIfAbsent(candidate: ByteArray): ByteArray

  /** Deletes this slot only. Idempotent. */
  fun delete()
}

/**
 * The key-encryption key (KEK) behind a slot. The app uses the Android
 * Keystore ([AndroidKeystoreKek]); JVM tests use a software key.
 */
interface Kek {
  /** The current KEK, or null when its alias does not exist. May throw. */
  fun get(): SecretKey?

  /** Deletes any stale alias and generates a fresh, non-exportable KEK. */
  fun createFresh(): SecretKey

  /** Deletes the alias. Idempotent. */
  fun delete()
}

/**
 * T-015: K_db wrapped by a Keystore AES-256-GCM key (design note §2).
 *
 * Blob `<dir>/db_key_v1.bin` = `0x01 ‖ iv(12) ‖ ct(32) ‖ tag(16)`, AAD
 * `zaghlol/k_db/v1`. Written as tmp, fsync, rename; read back and compared
 * before a create returns. `dir` is under `noBackupFilesDir` (never in an OS
 * backup). Reads classify: blob absent → NOT_FOUND; malformed blob, alias
 * missing, tag failure or an invalidated key → UNUSABLE; anything else →
 * UNAVAILABLE after retries ([retryDelaysMs]).
 *
 * Every method is synchronized: one instance per process serves all engines.
 * Nothing here logs (FU-050).
 */
class DbKeyStore(
  private val dir: File,
  private val kek: Kek,
  private val classifier: KeyErrorClassifier = KeyErrorClassifier(),
  private val retryDelaysMs: LongArray = longArrayOf(100, 300, 900),
  private val sleeper: (Long) -> Unit = { Thread.sleep(it) },
) : SecretSlotStore {
  val blobFile: File get() = File(dir, BLOB_NAME)
  private val tmpFile: File get() = File(dir, "$BLOB_NAME.tmp")

  @Synchronized
  override fun read(): SlotRead {
    var attempts = 0
    while (true) {
      attempts++
      val result = readOnce()
      if (result.status != SecretStatusMsg.UNAVAILABLE || attempts > retryDelaysMs.size) {
        return SlotRead(result.status, result.value, attempts)
      }
      sleeper(retryDelaysMs[attempts - 1])
    }
  }

  @Synchronized
  override fun createIfAbsent(candidate: ByteArray): ByteArray {
    if (!isWellFormedKey(candidate)) throw KeyStoreFailure()
    val existing = read()
    when (existing.status) {
      SecretStatusMsg.FOUND -> return existing.value ?: throw KeyStoreFailure()
      SecretStatusMsg.NOT_FOUND -> {}
      // An unusable blob must be deleted first (the caller decides, under the
      // lease, that no database depends on it). Unknown state: never overwrite.
      SecretStatusMsg.UNUSABLE, SecretStatusMsg.UNAVAILABLE -> throw KeyStoreFailure()
    }
    try {
      write(candidate)
    } catch (e: Exception) {
      deleteQuietly()
      throw KeyStoreFailure()
    }
    val check = readOnce()
    val ok =
      check.status == SecretStatusMsg.FOUND &&
        check.value != null &&
        MessageDigest.isEqual(check.value, candidate)
    check.value?.fill(0)
    if (!ok) {
      deleteQuietly()
      throw KeyStoreFailure()
    }
    return candidate.copyOf()
  }

  @Synchronized
  override fun delete() {
    try {
      blobFile.delete()
      tmpFile.delete()
      kek.delete()
    } catch (e: Exception) {
      throw KeyStoreFailure()
    }
    if (blobFile.exists()) throw KeyStoreFailure()
  }

  private fun readOnce(): SlotRead {
    return try {
      if (!blobFile.exists()) return SlotRead(SecretStatusMsg.NOT_FOUND, null, 1)
      val blob = blobFile.readBytes()
      if (blob.size != BLOB_LENGTH || blob[0] != VERSION) {
        return SlotRead(SecretStatusMsg.UNUSABLE, null, 1)
      }
      val key = kek.get() ?: return SlotRead(SecretStatusMsg.UNUSABLE, null, 1)
      val cipher = Cipher.getInstance(TRANSFORMATION)
      cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, blob, 1, IV_LENGTH))
      cipher.updateAAD(AAD)
      val plain = cipher.doFinal(blob, 1 + IV_LENGTH, blob.size - 1 - IV_LENGTH)
      if (plain.size != KEY_LENGTH) {
        plain.fill(0)
        SlotRead(SecretStatusMsg.UNUSABLE, null, 1)
      } else {
        SlotRead(SecretStatusMsg.FOUND, plain, 1)
      }
    } catch (e: Throwable) {
      when (classifier.classify(e)) {
        ReadFailure.UNUSABLE -> SlotRead(SecretStatusMsg.UNUSABLE, null, 1)
        ReadFailure.UNAVAILABLE -> SlotRead(SecretStatusMsg.UNAVAILABLE, null, 1)
      }
    }
  }

  private fun write(candidate: ByteArray) {
    dir.mkdirs()
    // Every create makes a fresh KEK (the stale alias is deleted first).
    val key = kek.createFresh()
    val cipher = Cipher.getInstance(TRANSFORMATION)
    cipher.init(Cipher.ENCRYPT_MODE, key)
    val iv = cipher.iv
    if (iv == null || iv.size != IV_LENGTH) throw KeyStoreFailure()
    cipher.updateAAD(AAD)
    val sealed = cipher.doFinal(candidate)
    if (sealed.size != KEY_LENGTH + TAG_BITS / 8) throw KeyStoreFailure()
    val blob = ByteArray(BLOB_LENGTH)
    blob[0] = VERSION
    System.arraycopy(iv, 0, blob, 1, IV_LENGTH)
    System.arraycopy(sealed, 0, blob, 1 + IV_LENGTH, sealed.size)
    FileOutputStream(tmpFile).use { out ->
      out.write(blob)
      out.flush()
      out.fd.sync()
    }
    if (!tmpFile.renameTo(blobFile)) throw KeyStoreFailure()
  }

  private fun deleteQuietly() {
    try {
      blobFile.delete()
      tmpFile.delete()
      kek.delete()
    } catch (e: Exception) {
      // Best effort after a failed create; the caller gets KEY_STORE_FAILED.
    }
  }

  companion object {
    const val BLOB_NAME = "db_key_v1.bin"
    const val KEY_LENGTH = 32
    const val IV_LENGTH = 12
    const val TAG_BITS = 128
    const val BLOB_LENGTH = 1 + IV_LENGTH + KEY_LENGTH + TAG_BITS / 8
    const val VERSION: Byte = 0x01
    const val TRANSFORMATION = "AES/GCM/NoPadding"
    val AAD: ByteArray = "zaghlol/k_db/v1".toByteArray(Charsets.US_ASCII)

    /** 32 bytes, not all equal (a broken generator). */
    fun isWellFormedKey(bytes: ByteArray): Boolean =
      bytes.size == KEY_LENGTH && bytes.any { it != bytes[0] }
  }
}
