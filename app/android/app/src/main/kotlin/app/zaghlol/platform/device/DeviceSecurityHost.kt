package app.zaghlol.platform.device

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.view.WindowManager
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

object DeviceSecurityRegistration {
  fun register(messenger: BinaryMessenger, activity: Activity) {
    DeviceSecurityHostApi.setUp(messenger, DeviceSecurityHost(AndroidDeviceEnv(activity, activity)))
  }

  fun unregister(messenger: BinaryMessenger) {
    DeviceSecurityHostApi.setUp(messenger, null)
  }
}
