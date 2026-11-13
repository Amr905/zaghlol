package app.zaghlol.platform.device

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.view.WindowManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import java.lang.ref.WeakReference

/** What the host needs from the platform; a seam so unit tests need no Android framework. */
interface DeviceEnv {
  fun fileExists(path: String): Boolean

  fun buildTags(): String?

  fun isDeviceSecure(): Boolean

  /** Applies the secure window to the current activity, if there is one. */
  fun applySecureWindow(secure: Boolean)

  /** Shows the OS unlock prompt; [onResult] is called exactly once, on the main thread. */
  fun authenticate(reason: String, onResult: (NativeAuthOutcome) -> Unit)
}

/**
 * T-103: the Pigeon `DeviceSecurityHostApi` (platform-channels section 5).
 * Reads and flips platform switches only; no app logic. Nothing here is
 * logged or returned beyond a boolean.
 */
class DeviceSecurityHost(private val env: DeviceEnv) : DeviceSecurityHostApi {
  /** FR-SEC-07 heuristic: warns only, trivially bypassable. */
  override fun isDeviceRooted(): Boolean {
    if (env.buildTags()?.contains("test-keys") == true) return true
    return SU_PATHS.any {
      try {
        env.fileExists(it)
      } catch (_: SecurityException) {
        false
      }
    }
  }

  override fun setSecureWindow(secure: Boolean) {
    SecureWindowState.requested = secure
    env.applySecureWindow(secure)
  }

  override fun isDeviceSecure(): Boolean =
    try {
      env.isDeviceSecure()
    } catch (_: RuntimeException) {
      // Can't tell: report "not secure" so Dart refuses to enable the lock on
      // a guess; it never changes any stored data.
      false
    }

  override fun authenticate(reason: String, callback: (Result<NativeAuthOutcome>) -> Unit) {
    try {
      env.authenticate(reason) { callback(Result.success(it)) }
    } catch (_: RuntimeException) {
      // A failed prompt is never a pass.
      callback(Result.success(NativeAuthOutcome.FAILED))
    }
  }

  companion object {
    val SU_PATHS =
      listOf(
        "/system/app/Superuser.apk",
        "/sbin/su",
        "/system/bin/su",
        "/system/xbin/su",
        "/data/local/xbin/su",
        "/data/local/bin/su",
        "/data/local/su",
        "/system/sd/xbin/su",
        "/system/bin/failsafe/su",
        "/su/bin/su",
        "/system/xbin/daemonsu",
        "/sbin/magisk",
      )
  }
}

/**
 * The last value Dart asked for, kept per process so a re-created activity
 * (rotation, theme change) is secured again before its first frame.
 */
object SecureWindowState {
  @Volatile var requested: Boolean = false
}

class AndroidDeviceEnv(context: Context, activity: Activity) : DeviceEnv {
  private val appContext = context.applicationContext
  private val activityRef = WeakReference(activity)

  override fun fileExists(path: String): Boolean = File(path).exists()

  override fun buildTags(): String? = Build.TAGS

  override fun isDeviceSecure(): Boolean =
    (appContext.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)?.isDeviceSecure
      ?: false

  override fun applySecureWindow(secure: Boolean) {
    activityRef.get()?.let { applyTo(it, secure) }
  }

  @Volatile private var prompting = false

  override fun authenticate(reason: String, onResult: (NativeAuthOutcome) -> Unit) {
    val activity = activityRef.get() as? FragmentActivity
    if (activity == null || prompting) {
      onResult(NativeAuthOutcome.CANCELLED)
      return
    }
    val authenticators = BiometricOutcomes.authenticators(Build.VERSION.SDK_INT)
    BiometricOutcomes.fromCanAuthenticate(
      BiometricManager.from(activity).canAuthenticate(authenticators)
    )?.let {
      onResult(it)
      return
    }
    prompting = true
    val prompt =
      BiometricPrompt(
        activity,
        ContextCompat.getMainExecutor(activity),
        object : BiometricPrompt.AuthenticationCallback() {
          override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
            prompting = false
            onResult(NativeAuthOutcome.SUCCESS)
          }

          override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
            prompting = false
            onResult(BiometricOutcomes.fromError(errorCode))
          }
          // onAuthenticationFailed (one wrong finger) is not final: the prompt stays up.
        },
      )
    // No negative button: not allowed together with DEVICE_CREDENTIAL.
    val info =
      BiometricPrompt.PromptInfo.Builder()
        .setTitle(reason)
        .setAllowedAuthenticators(authenticators)
        .build()
    prompt.authenticate(info)
  }

  companion object {
    /** FLAG_SECURE hides the window from screenshots and from the recents thumbnail. */
    fun applyTo(activity: Activity, secure: Boolean) {
      val window = activity.window
      if (secure) {
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
      } else {
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
      }
      if (Build.VERSION.SDK_INT >= 33) {
        // Android 13+: also opt the task out of the recents screenshot.
        activity.setRecentsScreenshotEnabled(!secure)
      }
    }
  }
}

/** Maps BiometricPrompt / BiometricManager codes to the contract outcome. Pure. */
object BiometricOutcomes {
  /**
   * AndroidX rule: BIOMETRIC_STRONG with DEVICE_CREDENTIAL is unsupported on API 28-29,
   * so API 26-29 use BIOMETRIC_WEAK or DEVICE_CREDENTIAL.
   */
  fun authenticators(sdkInt: Int): Int =
    if (sdkInt >= 30) {
      BiometricManager.Authenticators.BIOMETRIC_STRONG or
        BiometricManager.Authenticators.DEVICE_CREDENTIAL
    } else {
      BiometricManager.Authenticators.BIOMETRIC_WEAK or
        BiometricManager.Authenticators.DEVICE_CREDENTIAL
    }

  fun fromCanAuthenticate(code: Int): NativeAuthOutcome? =
    if (code == BiometricManager.BIOMETRIC_SUCCESS) null else NativeAuthOutcome.NOT_AVAILABLE

  fun fromError(code: Int): NativeAuthOutcome =
    when (code) {
      BiometricPrompt.ERROR_USER_CANCELED,
      BiometricPrompt.ERROR_CANCELED,
      BiometricPrompt.ERROR_NEGATIVE_BUTTON -> NativeAuthOutcome.CANCELLED
      BiometricPrompt.ERROR_LOCKOUT,
      BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> NativeAuthOutcome.LOCKED_OUT
      BiometricPrompt.ERROR_HW_NOT_PRESENT,
      BiometricPrompt.ERROR_HW_UNAVAILABLE,
      BiometricPrompt.ERROR_NO_BIOMETRICS,
      BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
      BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED -> NativeAuthOutcome.NOT_AVAILABLE
      else -> NativeAuthOutcome.FAILED
    }
}

object DeviceSecurityRegistration {
  fun register(messenger: BinaryMessenger, activity: Activity) {
    DeviceSecurityHostApi.setUp(messenger, DeviceSecurityHost(AndroidDeviceEnv(activity, activity)))
  }

  fun unregister(messenger: BinaryMessenger) {
    DeviceSecurityHostApi.setUp(messenger, null)
  }
}
