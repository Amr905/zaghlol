package app.zaghlol.platform.spool

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import app.zaghlol.platform.keys.KeyErrorClassifier
import app.zaghlol.platform.keys.ReadFailure
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * The only owner of the Android Keystore spool key (platform-channels.md 1.3,
 * security-model K_spool). Every caller in this process (share intake T-060,
 * spool T-039, receivers and workers T-040/T-041/T-043, Guard user file
 * T-038) must get the key here and never call KeyGenerator for [ALIAS] itself.
 *
 * Alias contract:
 * - Alias `zaghlol_spool_v1`: AES-256-GCM, encrypt + decrypt, no padding,
 *   randomized encryption (the Keystore picks a fresh 12-byte nonce per
 *   operation), 128-bit tag, non-exportable, no user authentication,
 *   TEE-backed AndroidKeyStore, deliberately NOT StrongBox (bulk data up to
 *   20 MiB inside the 20 s intake deadline is too slow on StrongBox; Lead
 *   decision 2026-11-10, T-060 review C1). Never call setIsStrongBoxBacked for
 *   this alias. K_db (T-015) is separate and keeps StrongBox-with-fallback.
 * - Get-or-create runs under one process-wide lock ([SpoolKeyManager]). All
 *   capture components run in the app's default process; a component moved to
 *   another process would need a cross-process scheme instead.
 * - A missing key is created silently. An existing key is deleted and
 *   recreated only on proof (T-039 design note section 2): its load fails as
 *   `UNUSABLE` (T-015 [KeyErrorClassifier]) on the first attempt and on the
 *   100/300/900 ms retries. Any `UNAVAILABLE` failure throws and deletes
 *   nothing. Data written under a lost key fails authentication and is
 *   deleted by its owner; the spool reports it as `keyInvalidatedAtMs`.
 */
object SpoolKey {
    const val ALIAS = "zaghlol_spool_v1"

    /** Spool key is TEE-only; see the class KDoc. Asserted by SpoolKeySpecTest. */
    internal const val REQUEST_STRONGBOX = false
    private const val PROVIDER = "AndroidKeyStore"

    private val manager = SpoolKeyManager(AndroidKeystoreOps)

    fun get(): SecretKey = manager.get()

    /**
     * Wall-clock creation time of the current key (`KeyStore.getCreationDate`),
     * or null when there is no key or it can't be read. Used only to choose
     * "ladder or no ladder" for an entry that already failed authentication.
     */
    fun creationDateMs(): Long? = manager.creationDateMs()

    private object AndroidKeystoreOps : KeystoreOps<SecretKey> {
        private fun keyStore(): KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

        override fun load(): SecretKey? = keyStore().getKey(ALIAS, null) as? SecretKey

        override fun create(): SecretKey = generate()

        override fun delete() = keyStore().deleteEntry(ALIAS)

        override fun creationDateMs(): Long? = keyStore().getCreationDate(ALIAS)?.time
    }

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

/** The Keystore calls [SpoolKeyManager] needs, behind a seam so the policy is JVM-tested. */
interface KeystoreOps<K : Any> {
    /** The key, or null when the alias does not exist. Throws when it exists but can't be loaded. */
    fun load(): K?

    fun create(): K

    fun delete()

    fun creationDateMs(): Long?
}

/** The spool key could not be loaded now (transient or unclassified); nothing was deleted. */
class SpoolKeyUnavailableException : Exception("SPOOL_KEY_UNAVAILABLE")

/**
 * Get-or-create with delete-on-proof (T-039 design note section 2). Runs
 * under one lock, so two first-time callers never both create and a
 * recreation can't race a load.
 */
class SpoolKeyManager<K : Any>(
    private val ops: KeystoreOps<K>,
    private val classifier: KeyErrorClassifier = KeyErrorClassifier(),
    private val sleep: (Long) -> Unit = Thread::sleep,
) {
    private val lock = Any()

    fun get(): K = synchronized(lock) {
        for ((attempt, delayMs) in RETRY_DELAYS_MS.withIndex()) {
            if (attempt > 0) sleep(delayMs)
            val loaded = try {
                ops.load()
            } catch (e: Exception) {
                // Only positive evidence (every attempt UNUSABLE) leads to a
                // delete; one UNAVAILABLE answer proves nothing.
                if (classifier.classify(e) != ReadFailure.UNUSABLE) throw SpoolKeyUnavailableException()
                continue
            }
            return loaded ?: ops.create()
        }
        ops.delete()
        ops.create()
    }

    fun creationDateMs(): Long? = synchronized(lock) {
        try {
            ops.creationDateMs()
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        /** First attempt, then the 100/300/900 ms retries (same ladder as entry reads). */
        val RETRY_DELAYS_MS = longArrayOf(0, 100, 300, 900)
    }
}
