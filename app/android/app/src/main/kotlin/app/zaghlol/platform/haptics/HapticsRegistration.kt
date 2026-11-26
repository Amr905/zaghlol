package app.zaghlol.platform.haptics

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * T-293: `MethodChannel('app.zaghlol/haptics')`, `play({hits})` -> true when
 * the phone played it (or the user turned touch feedback off, so nothing is
 * owed), false when the hardware cannot, so Dart falls back to
 * `HapticFeedback`. The VIBRATE permission is a normal one (no prompt).
 */
object HapticsRegistration {
    private const val CHANNEL = "app.zaghlol/haptics"

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "play") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val hits = HapticsPlan.parse(call.arguments)
            if (hits == null) {
                result.error("invalid", null, null)
                return@setMethodCallHandler
            }
            result.success(play(app, hits))
        }
    }

    fun unregister(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(null)
    }

    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    private fun touchFeedbackOff(context: Context): Boolean = try {
        Settings.System.getInt(context.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) == 0
    } catch (_: RuntimeException) {
        false
    }

    private fun play(context: Context, hits: List<HapticsPlan.Hit>): Boolean {
        if (touchFeedbackOff(context)) return true
        val v = vibrator(context) ?: return false
        if (!v.hasVibrator()) return false
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val prims = HapticsPlan.primitives(hits)
                if (v.areAllPrimitivesSupported(
                        VibrationEffect.Composition.PRIMITIVE_TICK,
                        VibrationEffect.Composition.PRIMITIVE_CLICK,
                        VibrationEffect.Composition.PRIMITIVE_THUD,
                    )
                ) {
                    val c = VibrationEffect.startComposition()
                    for (p in prims) c.addPrimitive(p.id, p.scale, p.delayMs)
                    v.vibrate(c.compose())
                    return true
                }
            }
            if (v.hasAmplitudeControl()) {
                val w = HapticsPlan.waveform(hits)
                v.vibrate(VibrationEffect.createWaveform(w.timings, w.amplitudes, -1))
                return true
            }
        } catch (_: RuntimeException) {
            return false
        }
        return false
    }
}
