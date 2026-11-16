package app.zaghlol.platform.diag

import android.content.Context
import app.zaghlol.platform.capture.CaptureRuntime
import app.zaghlol.platform.guard.GuardRuntime
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * SMS-device: the debug-only channel behind the "SMS diagnostics" screen
 * (dev flavours; a no-op elsewhere). Not part of the platform contract
 * (`docs/03-technical/platform-channels.md`): it carries counts, the Guard
 * mode and the number of spooled entries, never message text.
 *
 * `snapshot` -> `{guardMode, userState, pending, counts: {sender: {stage: n}}}`;
 * `reset` -> null.
 */
object SmsDiagChannel {
    const val NAME = "app.zaghlol/sms_diag"

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        val store = SmsDiag.storeFor(app.noBackupFilesDir) ?: return
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "snapshot" -> {
                        val g = GuardRuntime.get(app).state()
                        result.success(
                            mapOf(
                                "guardMode" to g.mode.wire,
                                "userState" to g.userState.name,
                                "pending" to (CaptureRuntime.get(app).store.pendingCountOrNull() ?: -1),
                                "counts" to store.snapshot(),
                            ),
                        )
                    }
                    "reset" -> {
                        store.reset()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("DIAG_FAILED", null, null)
            }
        }
    }

    fun unregister(messenger: BinaryMessenger) {
        MethodChannel(messenger, NAME).setMethodCallHandler(null)
    }
}
