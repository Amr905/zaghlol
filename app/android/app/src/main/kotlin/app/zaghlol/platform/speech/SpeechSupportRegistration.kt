package app.zaghlol.platform.speech

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * T-120 (D-42): `MethodChannel('zaghlol/speech')` `onDeviceSupport({locale})`
 * returns true only when recognition can run on the device without the network.
 *
 * API 31+ with `isOnDeviceRecognitionAvailable`; on API 33+ the locale's
 * language pack must also be installed. Anything unconfirmed is false, and
 * Dart then asks the user before the network recognizer is used. Nothing is
 * recorded or logged here.
 */
object SpeechSupportRegistration {
    const val CHANNEL = "zaghlol/speech"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "onDeviceSupport") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val tag = call.argument<String>("locale")
            if (tag.isNullOrEmpty()) {
                result.error("bad-args", "locale is required", null)
                return@setMethodCallHandler
            }
            probe(context, tag.replace('_', '-')) { result.success(it) }
        }
    }

    fun unregister(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(null)
    }

    /** Pure decision, unit tested. [installed] is null below API 33. */
    fun decide(sdk: Int, available: Boolean, installed: List<String>?, tag: String): Boolean {
        if (sdk < Build.VERSION_CODES.S || !available) return false
        if (sdk < Build.VERSION_CODES.TIRAMISU) return true
        val wanted = tag.replace('_', '-').lowercase()
        return installed.orEmpty().any { it.replace('_', '-').lowercase() == wanted }
    }

    private fun probe(context: Context, tag: String, done: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return done(false)
        val main = Handler(Looper.getMainLooper())
        main.post {
            try {
                probeS(context, tag, main, done)
            } catch (_: Exception) {
                done(false)
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun probeS(context: Context, tag: String, main: Handler, done: (Boolean) -> Unit) {
        val sdk = Build.VERSION.SDK_INT
        val available = SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && available) {
            probeT(context, tag, main, done)
        } else {
            done(decide(sdk, available, null, tag))
        }
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun probeT(context: Context, tag: String, main: Handler, done: (Boolean) -> Unit) {
        val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        var finished = false
        fun finish(ok: Boolean) {
            if (finished) return
            finished = true
            recognizer.destroy()
            done(ok)
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, tag)
        main.postDelayed({ finish(false) }, TIMEOUT_MS)
        recognizer.checkRecognitionSupport(
            intent,
            ContextCompat.getMainExecutor(context),
            object : RecognitionSupportCallback {
                override fun onSupportResult(recognitionSupport: RecognitionSupport) =
                    finish(decide(Build.VERSION.SDK_INT, true, recognitionSupport.installedOnDeviceLanguages, tag))

                override fun onError(error: Int) = finish(false)
            },
        )
    }

    private const val TIMEOUT_MS = 3000L
}
