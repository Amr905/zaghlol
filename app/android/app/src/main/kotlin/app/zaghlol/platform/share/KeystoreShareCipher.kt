package app.zaghlol.platform.share

import app.zaghlol.platform.spool.SpoolKey
import java.io.OutputStream
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.CipherOutputStream
import javax.crypto.spec.GCMParameterSpec

/**
 * [ShareCipher] over the Keystore spool key. The key itself (alias, parameters,
 * get-or-create lock) is owned by [SpoolKey], shared with T-039.
 */
class KeystoreShareCipher : ShareCipher {
    override fun wrapEncrypt(out: OutputStream, aad: ByteArray): OutputStream {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, SpoolKey.get())
        cipher.updateAAD(aad)
        val iv = cipher.iv
        check(iv.size == ShareCipher.NONCE_BYTES) { "unexpected GCM nonce length" }
        out.write(iv)
        return CipherOutputStream(out, cipher)
    }

    override fun decrypt(data: ByteArray, aad: ByteArray): ByteArray {
        if (data.size < ShareCipher.NONCE_BYTES + ShareCipher.TAG_BYTES) throw AEADBadTagException("truncated")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            SpoolKey.get(),
            GCMParameterSpec(ShareCipher.TAG_BYTES * 8, data, 0, ShareCipher.NONCE_BYTES),
        )
        cipher.updateAAD(aad)
        return cipher.doFinal(data, ShareCipher.NONCE_BYTES, data.size - ShareCipher.NONCE_BYTES)
    }

    private companion object {
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
