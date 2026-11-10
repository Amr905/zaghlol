package app.zaghlol.platform.share

import java.io.OutputStream

/**
 * AES-256-GCM with the spool key (security-model K_spool). File format:
 * nonce(12) || ciphertext || tag(16). [aad] binds a file to its share id,
 * role and kind (F11), so files cannot be swapped between shares or roles.
 * Production: [KeystoreShareCipher].
 */
interface ShareCipher {
    /** Writes the nonce to [out] and returns a stream that encrypts into it; closing it writes the tag and closes [out]. */
    fun wrapEncrypt(out: OutputStream, aad: ByteArray): OutputStream

    /**
     * Decrypts a whole file. Throws `javax.crypto.AEADBadTagException` when the
     * data is not authentic (tampered, truncated, wrong key or wrong [aad]);
     * any other exception means the attempt itself failed and may be retried.
     */
    fun decrypt(data: ByteArray, aad: ByteArray): ByteArray

    companion object {
        const val NONCE_BYTES = 12
        const val TAG_BYTES = 16
    }
}
