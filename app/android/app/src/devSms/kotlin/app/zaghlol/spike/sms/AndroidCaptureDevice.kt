package app.zaghlol.spike.sms

import android.Manifest
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import app.zaghlol.platform.capture.CaptureCapabilities

/** [CaptureDevice] over the Android framework (devSms spike). */
class AndroidCaptureDevice(private val app: Context) : CaptureDevice {
    override fun capabilities(): CaptureCapabilities = CaptureCapabilities(
        smsGranted = granted(Manifest.permission.RECEIVE_SMS) && granted(Manifest.permission.READ_SMS),
        smsFlavor = true,
        notificationAccess = notificationAccess(),
        postNotifications = Build.VERSION.SDK_INT < 33 || granted("android.permission.POST_NOTIFICATIONS"),
        sdkInt = Build.VERSION.SDK_INT.toLong(),
    )

    override fun isIgnoringBatteryOptimizations(): Boolean =
        app.getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(app.packageName) == true

    /**
     * Q3 default: the system list, no `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
     * permission (the direct dialog is Play-restricted and is not declared).
     */
    override fun openBatteryOptimizationSettings() {
        app.startActivity(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    /** Device conditions for a metrics row (no identifiers). */
    fun conditions(lingerMs: Long): SpikeMetrics.Conditions {
        val pm = app.getSystemService(PowerManager::class.java)
        val bucket = if (Build.VERSION.SDK_INT >= 28) {
            try {
                app.getSystemService(UsageStatsManager::class.java)?.appStandbyBucket ?: -1
            } catch (_: Exception) {
                -1
            }
        } else {
            -1
        }
        return SpikeMetrics.Conditions(
            sdk = Build.VERSION.SDK_INT,
            batteryExempt = pm?.isIgnoringBatteryOptimizations(app.packageName) == true,
            deviceIdle = pm?.isDeviceIdleMode == true,
            standbyBucket = bucket,
            lingerMs = lingerMs,
        )
    }

    private fun granted(p: String) = app.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    private fun notificationAccess(): Boolean = try {
        Settings.Secure.getString(app.contentResolver, "enabled_notification_listeners")
            ?.split(':')
            ?.any { it.substringBefore('/') == app.packageName } == true
    } catch (_: Exception) {
        false
    }
}
