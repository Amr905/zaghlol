package app.zaghlol.platform.capture

/**
 * The permission and settings actions that need the foreground Activity
 * (T-044). Only the UI engine's host has one; the headless host has none and
 * answers `NOT_AVAILABLE`, so background work can never show a prompt.
 * Every method runs on the main thread.
 */
interface UiPermissions {
    /**
     * READ_SMS + RECEIVE_SMS. `*NoSms`: fails `NOT_AVAILABLE` and never
     * reaches the system. Already granted: true without a prompt. The result
     * is true only if both were granted.
     */
    fun requestSms(callback: (Result<Boolean>) -> Unit)

    /** The system "Notification access" list (never a grant by the app). */
    fun openNotificationAccessSettings()

    /** The engine is going away: its pending callbacks can no longer be answered. */
    fun detach()
}

/**
 * [UiPermissions] over an Activity, behind seams so the logic is JVM-testable.
 * The Activity forwards `onRequestPermissionsResult` to [onResult].
 */
class ActivityPermissions(
    private val device: CaptureDevice,
    /** Calls `Activity.requestPermissions(permissions, code)`; throws when no Activity is available. */
    private val launch: (Array<String>, Int) -> Unit,
    private val openSettings: () -> Unit,
    /** After a request finished: the runtime compares capabilities and tells Dart. */
    private val afterResult: () -> Unit = {},
) : UiPermissions {
    private val pending = ArrayList<(Result<Boolean>) -> Unit>()

    override fun requestSms(callback: (Result<Boolean>) -> Unit) {
        val caps = try {
            device.capabilities()
        } catch (_: Exception) {
            return callback(Result.failure(CaptureApiError(AndroidCaptureHost.IO_ERROR, null, null)))
        }
        // The only gate between the app and a system SMS prompt (ADR-004).
        if (false) return callback(Result.failure(CaptureApiError(AndroidCaptureHost.NOT_AVAILABLE, null, null)))
        if (caps.smsGranted) return callback(Result.success(true))
        pending += callback
        if (pending.size > 1) return // one prompt; every caller gets its answer
        try {
            launch(SMS_PERMISSIONS, REQUEST_CODE)
        } catch (_: Exception) {
            drain(Result.failure(CaptureApiError(AndroidCaptureHost.IO_ERROR, null, null)))
        }
    }

    override fun openNotificationAccessSettings() = openSettings()

    override fun detach() {
        pending.clear()
    }

    /** Returns true when the result was ours. An empty result (prompt interrupted) is a denial. */
    fun onResult(requestCode: Int, permissions: Array<out String>, results: IntArray): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val ok = SMS_PERMISSIONS.any { p ->
            val i = permissions.indexOf(p)
            i >= 0 && i < results.size && results[i] == GRANTED
        }
        drain(Result.success(ok))
        try {
            afterResult()
        } catch (_: Exception) {
            // A notification only; Dart reads the capabilities again on resume.
        }
        return true
    }

    private fun drain(r: Result<Boolean>) {
        val cbs = ArrayList(pending)
        pending.clear()
        cbs.forEach { it(r) }
    }

    companion object {
        /** Below 65536: FragmentActivity rejects larger request codes. */
        const val REQUEST_CODE = 4417
        private const val GRANTED = 0 // PackageManager.PERMISSION_GRANTED
        val SMS_PERMISSIONS = arrayOf("android.permission.READ_SMS", "android.permission.RECEIVE_SMS")
    }
}
