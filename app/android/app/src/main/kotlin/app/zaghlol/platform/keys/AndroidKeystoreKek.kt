package app.zaghlol.platform.keys

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * T-015: the Android Keystore AES-256-GCM wrapping key for K_db (design note
 * §2). Non-exportable; no user authentication and no unlocked-device
 * requirement, so background capture (T-008) can open the database while the
 * phone is locked (security-model §3 "Background access"). StrongBox when the
 * device has it, the TEE otherwise.
 */
class AndroidKeystoreKek(private val alias: String = DB_KEK_ALIAS) : Kek {
  private fun keyStore(): KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

  override fun get(): SecretKey? = keyStore().getKey(alias, null) as? SecretKey

  override fun createFresh(): SecretKey {
    val ks = keyStore()
    if (ks.containsAlias(alias)) ks.deleteEntry(alias)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      try {
        return generate(strongBox = true)
      } catch (e: Exception) {
        // StrongBoxUnavailableException, or a StrongBox that rejects the
        // spec: fall back to the TEE.
        if (keyStore().containsAlias(alias)) keyStore().deleteEntry(alias)
      }
    }
    return generate(strongBox = false)
  }

  override fun delete() {
    val ks = keyStore()
    if (ks.containsAlias(alias)) ks.deleteEntry(alias)
  }

  private fun generate(strongBox: Boolean): SecretKey {
    val builder =
      KeyGenParameterSpec.Builder(
          alias,
          KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setKeySize(256)
        .setRandomizedEncryptionRequired(true)
        .setUserAuthenticationRequired(false)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      builder.setUnlockedDeviceRequired(false)
      builder.setIsStrongBoxBacked(strongBox)
    }
    val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
    generator.init(builder.build())
    return generator.generateKey()
  }

  companion object {
    const val PROVIDER = "AndroidKeyStore"
    const val DB_KEK_ALIAS = "zaghlol_db_kek_v1"
  }
}
