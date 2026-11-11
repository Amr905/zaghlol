package app.zaghlol.platform.guard

import app.zaghlol.platform.spool.SpoolKey
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec

/**
 * AES-256-GCM for the Guard user part (T-038 design note section 5). Format
 * `nonce(12) || ciphertext || tag(16)`, AAD [GuardUserConfigStore.AAD].
 * Production: [KeystoreGuardUserCipher]. Kept separate from the spool cipher
 * (T-039, built in parallel); unify in a follow-up.
 */
interface GuardUserCipher {
    fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray

    /**
     * Throws [AEADBadTagException] when the data is not authentic (tampered,
     * truncated, wrong key, wrong AAD): proof the file is unusable. Any other
     * exception means the attempt failed and may be retried.
     */
    fun decrypt(data: ByteArray, aad: ByteArray): ByteArray

    companion object {
        const val NONCE_BYTES = 12
        const val TAG_BYTES = 16
    }
}

/** [GuardUserCipher] over the Keystore spool key ([SpoolKey]; never `KeyGenerator` here, FU-068). */
class KeystoreGuardUserCipher : GuardUserCipher {
    override fun encrypt(plain: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, SpoolKey.get())
        cipher.updateAAD(aad)
        val iv = cipher.iv
        check(iv.size == GuardUserCipher.NONCE_BYTES) { "unexpected GCM nonce length" }
        return iv + cipher.doFinal(plain)
    }

    override fun decrypt(data: ByteArray, aad: ByteArray): ByteArray {
        if (data.size < GuardUserCipher.NONCE_BYTES + GuardUserCipher.TAG_BYTES) throw AEADBadTagException("truncated")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            SpoolKey.get(),
            GCMParameterSpec(GuardUserCipher.TAG_BYTES * 8, data, 0, GuardUserCipher.NONCE_BYTES),
        )
        cipher.updateAAD(aad)
        return cipher.doFinal(data, GuardUserCipher.NONCE_BYTES, data.size - GuardUserCipher.NONCE_BYTES)
    }

    private companion object {
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
