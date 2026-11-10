package app.zaghlol.platform.spool

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
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
 *   TEE-backed AndroidKeyStore, deliberately NOT StrongBox (bulk data up to
 *   20 MiB inside the 20 s intake deadline is too slow on StrongBox; Lead
 *   decision 2026-11-10, T-060 review C1). Never call setIsStrongBoxBacked for
 *   this alias. T-039 must not add a StrongBox attempt or fallback; K_db (T-015)
 *   is separate and keeps StrongBox-with-fallback.
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

    /** Spool key is TEE-only; see the class KDoc. Asserted by SpoolKeySpecTest. */
    internal const val REQUEST_STRONGBOX = false
    private const val PROVIDER = "AndroidKeyStore"

    private val holder = GetOrCreate(load = ::load, create = ::create)

    fun get(): SecretKey = holder.get()

    private fun load(): SecretKey? {
        val ks = KeyStore.getInstance(PROVIDER).apply { load(null) }
        return ks.getKey(ALIAS, null) as? SecretKey
    }

    private fun create(): SecretKey = generate()

    private fun generate(): SecretKey {
        val spec = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(false)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER).run {
            init(spec)
            generateKey()
        }
    }
}
