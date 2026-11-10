package app.zaghlol.platform.keys

import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/** A software KEK for JVM tests (the Android Keystore is not available). */
class SoftwareKek : Kek {
  var key: SecretKey? = null
  var creates = 0
  var deletes = 0
  var getError: Throwable? = null

  /** Simulates a KEK that changes right after a create (verify must fail). */
  var swapAfterCreate = false

  override fun get(): SecretKey? {
    getError?.let { throw it }
    return key
  }

  override fun createFresh(): SecretKey {
    creates++
    val fresh = newKey()
    key = if (swapAfterCreate) newKey() else fresh
    return fresh
  }

  override fun delete() {
    deletes++
    key = null
  }

  companion object {
    fun newKey(): SecretKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
  }
}

/** A synthetic candidate key: never a real key, never printed. */
fun syntheticKey(seed: Int = 61): ByteArray = ByteArray(32) { i -> ((seed + 97 * i) and 0xFF).toByte() }
