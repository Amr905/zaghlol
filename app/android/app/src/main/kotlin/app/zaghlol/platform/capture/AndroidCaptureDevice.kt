package app.zaghlol.platform.capture

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/** [CaptureDevice] over the Android framework (every flavour; moved from the T-008 spike by T-041). */
class AndroidCaptureDevice(private val app: Context) : CaptureDevice {
    /**
     * `*Sms` build: the merged manifest requests `RECEIVE_SMS` (ADR-004; the
     * `*NoSms` manifests remove it). Read once; an error reads as no Sms build.
     */
    private val smsFlavor: Boolean by lazy {
        try {
            @Suppress("DEPRECATION")
            app.packageManager.getPackageInfo(app.packageName, PackageManager.GET_PERMISSIONS)
                .requestedPermissions?.contains(Manifest.permission.RECEIVE_SMS) == true
        } catch (_: Exception) {
            false
        }
    }

    override fun capabilities(): CaptureCapabilities = CaptureCapabilities(
        smsGranted = smsFlavor && granted(Manifest.permission.RECEIVE_SMS) && granted(Manifest.permission.READ_SMS),
        smsFlavor = smsFlavor,
        notificationAccess = notificationAccess(),
        postNotifications = Build.VERSION.SDK_INT < 33 || granted("android.permission.POST_NOTIFICATIONS"),
        sdkInt = Build.VERSION.SDK_INT.toLong(),
    )

    override fun isIgnoringBatteryOptimizations(): Boolean =
        app.getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(app.packageName) == true

    /**
     * Q3 (PO): the system list only; the `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
     * dialog and permission are never used.
     */
    override fun openBatteryOptimizationSettings() {
        app.startActivity(
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
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
