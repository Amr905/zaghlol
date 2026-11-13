package app.zaghlol.platform.clock

import android.content.ContentResolver
import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger

/** The three raw readings; a seam so unit tests need no Android framework. */
interface ClockReadings {
  fun wallMs(): Long

  fun monotonicMs(): Long

  fun bootCount(): Long?
}

/**
 * T-180: the Pigeon `TrustedClockHostApi` (platform-channels §4b). Reads clocks
 * only; no trusted-time logic (T-144, Dart). Values are never logged.
 */
class TrustedClockHost(private val readings: ClockReadings) : TrustedClockHostApi {
  override fun sample(): ClockSample {
    // Back to back so the three values describe the same instant. The boot
    // count changes only across a reboot, so its position is not critical.
    val wall = readings.wallMs()
    val mono = readings.monotonicMs()
    val boot = readings.bootCount()
    return ClockSample(wallMs = wall, monotonicMs = mono, bootCount = boot)
  }
}

/** Real readings. `elapsedRealtime` counts deep sleep; it restarts at boot. */
class AndroidClockReadings(private val resolver: ContentResolver) : ClockReadings {
  override fun wallMs(): Long = System.currentTimeMillis()

  override fun monotonicMs(): Long = SystemClock.elapsedRealtime()

  /** BOOT_COUNT exists since API 24 (minSdk 26); null if the OEM omits it. */
  override fun bootCount(): Long? =
    try {
      Settings.Global.getInt(resolver, Settings.Global.BOOT_COUNT).toLong()
    } catch (_: Settings.SettingNotFoundException) {
      null
    } catch (_: SecurityException) {
      null
    }
}

/** Registers the clock on the UI engine. */
object TrustedClockRegistration {
  fun register(messenger: BinaryMessenger, context: Context) {
    TrustedClockHostApi.setUp(
      messenger,
      TrustedClockHost(AndroidClockReadings(context.applicationContext.contentResolver)),
    )
  }

  fun unregister(messenger: BinaryMessenger) {
    TrustedClockHostApi.setUp(messenger, null)
  }
}
