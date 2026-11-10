package app.zaghlol.platform.share

import java.io.OutputStream

/**
 * AES-256-GCM with the spool key (security-model K_spool). File format:
 * nonce(12) || ciphertext || tag(16). Production: [KeystoreShareCipher].
 */
interface ShareCipher {
    /** Writes the nonce to [out] and returns a stream that encrypts into it; closing it writes the tag and closes [out]. */
    fun wrapEncrypt(out: OutputStream): OutputStream

    /** Decrypts a whole file; throws on a wrong key or tampering. */
    fun decrypt(data: ByteArray): ByteArray
}
