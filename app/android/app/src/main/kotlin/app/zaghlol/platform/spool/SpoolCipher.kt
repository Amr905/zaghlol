package app.zaghlol.platform.spool

import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec

/**
 * AES-256-GCM over whole spool entries: `nonce(12) || ciphertext || tag(16)`.
 * [decrypt] throws `AEADBadTagException` when the data is not authentic
 * (tampered, truncated, wrong key or wrong AAD); any other exception means
 * the attempt itself failed (Keystore busy, I/O) and proves nothing.
 */
interface SpoolCipher {
    fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray

    fun decrypt(data: ByteArray, aad: ByteArray): ByteArray

    companion object {
        const val NONCE_BYTES = 12
        const val TAG_BYTES = 16
    }
}

/** Production cipher: the key comes only from [SpoolKey] (FU-068). */
class KeystoreSpoolCipher : SpoolCipher {
    override fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, SpoolKey.get())
        cipher.updateAAD(aad)
        val iv = cipher.iv
        check(iv.size == SpoolCipher.NONCE_BYTES) { "NONCE_LENGTH" }
        val ct = cipher.doFinal(plain)
        return iv + ct
    }

    override fun decrypt(data: ByteArray, aad: ByteArray): ByteArray {
        if (data.size < SpoolCipher.NONCE_BYTES + SpoolCipher.TAG_BYTES) throw AEADBadTagException("truncated")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            SpoolKey.get(),
            GCMParameterSpec(SpoolCipher.TAG_BYTES * 8, data, 0, SpoolCipher.NONCE_BYTES),
        )
        cipher.updateAAD(aad)
        return cipher.doFinal(data, SpoolCipher.NONCE_BYTES, data.size - SpoolCipher.NONCE_BYTES)
    }

    private companion object {
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
