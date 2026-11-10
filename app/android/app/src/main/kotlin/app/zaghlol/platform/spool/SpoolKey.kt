package app.zaghlol.platform.spool

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.security.ProviderException
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * The only owner of the Android Keystore spool key (platform-channels.md 1.3,
 * security-model K_spool). Every caller in this process (share intake T-060,
 * spool T-039, receivers and workers T-040/T-041/T-043) must get the key here
 * and never call KeyGenerator for [ALIAS] itself.
 *
 * Alias contract:
 * - Alias `zaghlol_spool_v1`: AES-256-GCM, encrypt + decrypt, no padding,
 *   randomized encryption (the Keystore picks a fresh 12-byte nonce per
 *   operation), 128-bit tag, non-exportable, no user authentication,
 *   StrongBox when available with a software-TEE fallback.
 * - Get-or-create runs under one process-wide lock ([GetOrCreate]). All
 *   capture components run in the app's default process; a component moved to
 *   another process would need a cross-process scheme instead.
 * - A missing key is created silently. Data encrypted with a lost key then
 *   fails authentication and is deleted by its owner. Mapping a lost or
 *   invalidated key to `KEY_INVALIDATED` (platform-channels.md section 5) is
 *   owned by T-039; this object never deletes the alias.
 */
object SpoolKey {
    const val ALIAS = "zaghlol_spool_v1"
    private const val PROVIDER = "AndroidKeyStore"

    private val holder = GetOrCreate(load = ::load, create = ::create)

    fun get(): SecretKey = holder.get()

    private fun load(): SecretKey? {
        val ks = KeyStore.getInstance(PROVIDER).apply { load(null) }
        return ks.getKey(ALIAS, null) as? SecretKey
    }

    private fun create(): SecretKey = generate(strongBox = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)

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
}
