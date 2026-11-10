package app.zaghlol.platform.share

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.OutputStream
import java.security.KeyStore
import java.security.ProviderException
import javax.crypto.Cipher
import javax.crypto.CipherOutputStream
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android Keystore AES-256-GCM key `zaghlol_spool_v1`: non-exportable, no user
 * authentication, StrongBox when available (platform-channels.md 1.3). The
 * alias is shared with the T-039 spool; whichever task runs first creates it.
 */
class KeystoreShareCipher : ShareCipher {
    override fun wrapEncrypt(out: OutputStream): OutputStream {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val iv = cipher.iv
        check(iv.size == NONCE_BYTES) { "unexpected GCM nonce length" }
        out.write(iv)
        return CipherOutputStream(out, cipher)
    }

    override fun decrypt(data: ByteArray): ByteArray {
        require(data.size > NONCE_BYTES + TAG_BYTES) { "ciphertext too short" }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BYTES * 8, data, 0, NONCE_BYTES))
        return cipher.doFinal(data, NONCE_BYTES, data.size - NONCE_BYTES)
    }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance(PROVIDER).apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return generate(strongBox = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
    }

    private fun generate(strongBox: Boolean): SecretKey {
        val spec = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(false)
            .apply {
                if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) setIsStrongBoxBacked(true)
            }
            .build()
        return try {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER).run {
                init(spec)
                generateKey()
            }
        } catch (e: ProviderException) {
            // StrongBoxUnavailableException (API 28+) extends ProviderException.
            if (strongBox) generate(strongBox = false) else throw e
        }
    }

    companion object {
        const val ALIAS = "zaghlol_spool_v1"
        private const val PROVIDER = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val NONCE_BYTES = 12
        const val TAG_BYTES = 16
    }
}
