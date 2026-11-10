package app.zaghlol.platform.keys

import android.annotation.TargetApi
import android.os.Build
import android.security.keystore.KeyPermanentlyInvalidatedException
import java.io.IOException
import javax.crypto.AEADBadTagException
import android.security.KeyStoreException as AndroidKeyStoreException

/** What a failed key read means (design note §2). */
enum class ReadFailure {
  /** Positive evidence the stored key can never be read again. */
  UNUSABLE,

  /** Anything else. Retried, and never a reason to wipe. */
  UNAVAILABLE,
}

/** The API 33+ facts of an `android.security.KeyStoreException`. */
data class KeystoreErrorInfo(val keyMissingOrCorrupted: Boolean, val transient: Boolean)

/**
 * Maps exceptions from a key read to [ReadFailure]. Only these are UNUSABLE:
 * `AEADBadTagException` (wrong wrapping key or a changed blob),
 * `KeyPermanentlyInvalidatedException`, and on API 33+ a KeyStoreException
 * with `ERROR_KEY_DOES_NOT_EXIST` / `ERROR_KEY_CORRUPTED` that is not
 * transient. A transient KeyStoreException, an IOException and **every other
 * exception** are UNAVAILABLE. The cause chain is searched.
 *
 * [keystoreInfo] is injectable so JVM tests can cover the API 33 branch.
 */
class KeyErrorClassifier(
  private val keystoreInfo: (Throwable) -> KeystoreErrorInfo? = ::platformKeystoreInfo,
) {
  fun classify(error: Throwable): ReadFailure {
    var current: Throwable? = error
    var depth = 0
    while (current != null && depth < MAX_DEPTH) {
      when {
        current is AEADBadTagException -> return ReadFailure.UNUSABLE
        current is KeyPermanentlyInvalidatedException -> return ReadFailure.UNUSABLE
        current is IOException -> return ReadFailure.UNAVAILABLE
      }
      val info = keystoreInfo(current)
      if (info != null) {
        if (info.transient) return ReadFailure.UNAVAILABLE
        if (info.keyMissingOrCorrupted) return ReadFailure.UNUSABLE
        return ReadFailure.UNAVAILABLE
      }
      current = current.cause?.takeIf { it !== current }
      depth++
    }
    return ReadFailure.UNAVAILABLE
  }

  private companion object {
    const val MAX_DEPTH = 8
  }
}

/** Reads an API 33+ `android.security.KeyStoreException`; null otherwise. */
fun platformKeystoreInfo(error: Throwable): KeystoreErrorInfo? {
  if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return null
  return Api33.info(error)
}

@TargetApi(Build.VERSION_CODES.TIRAMISU)
private object Api33 {
  fun info(error: Throwable): KeystoreErrorInfo? {
    val e = error as? AndroidKeyStoreException ?: return null
    val code = e.numericErrorCode
    return KeystoreErrorInfo(
      keyMissingOrCorrupted =
        code == AndroidKeyStoreException.ERROR_KEY_DOES_NOT_EXIST ||
          code == AndroidKeyStoreException.ERROR_KEY_CORRUPTED,
      transient = e.isTransientFailure,
    )
  }
}
