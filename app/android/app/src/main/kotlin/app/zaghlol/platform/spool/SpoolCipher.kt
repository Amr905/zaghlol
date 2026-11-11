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

/**
 * Production cipher: the key comes only from [SpoolKey] (FU-068). `Cipher.init`
 * runs inside [SpoolKey.withKey], so an init failure is classified like a key
 * load failure (FU-104 #6); a failure that proves nothing surfaces as
 * [SpoolKeyUnavailableException] (callers treat it as transient).
 */
class KeystoreSpoolCipher : SpoolCipher {
    override fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        SpoolKey.withKey { cipher.init(Cipher.ENCRYPT_MODE, it) }
        cipher.updateAAD(aad)
        val iv = cipher.iv
        check(iv.size == SpoolCipher.NONCE_BYTES) { "NONCE_LENGTH" }
        val ct = cipher.doFinal(plain)
        return iv + ct
    }

    override fun decrypt(data: ByteArray, aad: ByteArray): ByteArray {
        if (data.size < SpoolCipher.NONCE_BYTES + SpoolCipher.TAG_BYTES) throw AEADBadTagException("truncated")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        val spec = GCMParameterSpec(SpoolCipher.TAG_BYTES * 8, data, 0, SpoolCipher.NONCE_BYTES)
        SpoolKey.withKey { cipher.init(Cipher.DECRYPT_MODE, it, spec) }
        cipher.updateAAD(aad)
        return cipher.doFinal(data, SpoolCipher.NONCE_BYTES, data.size - SpoolCipher.NONCE_BYTES)
    }

    private companion object {
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
