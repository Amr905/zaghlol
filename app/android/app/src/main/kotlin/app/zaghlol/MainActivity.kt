package app.zaghlol

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import app.zaghlol.platform.capture.ActivityPermissions
import app.zaghlol.platform.capture.CaptureRuntime
import app.zaghlol.platform.clock.TrustedClockRegistration
import app.zaghlol.platform.device.AndroidDeviceEnv
import app.zaghlol.platform.device.DeviceSecurityRegistration
import app.zaghlol.platform.device.SecureWindowState
import app.zaghlol.platform.keys.SecretStoreRegistration
import app.zaghlol.platform.share.ShareDescriptor
import app.zaghlol.platform.share.ShareHandOff
import app.zaghlol.platform.share.ShareIntakeEventsApi
import app.zaghlol.platform.share.ShareIntakeHost
import app.zaghlol.platform.share.ShareIntakeHostApi
import app.zaghlol.platform.share.ShareIntakeState
import app.zaghlol.platform.share.ShareStore
import app.zaghlol.platform.share.ShareStores
import app.zaghlol.platform.text.TextNormalizationHostApi
import app.zaghlol.platform.text.TextNormalizationRegistration
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import java.util.concurrent.Executors

// T-103: BiometricPrompt (DeviceSecurityHost.authenticate) needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    private var shareEvents: ShareIntakeEventsApi? = null
    private var shareStore: ShareStore? = null
    private var capturePermissions: ActivityPermissions? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // T-103: a re-created activity is secured again before its first frame.
        if (SecureWindowState.requested) AndroidDeviceEnv.applyTo(this, true)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // T-015: the database key store. The T-008 headless engine must register
        // it too (every engine that opens the database).
        SecretStoreRegistration.register(messenger, this)
        // T-148: NFC for the backup passphrase (UI engine only).
        TextNormalizationRegistration.register(messenger)
        // T-180: trusted clock sample for the Gold offline bound.
        TrustedClockRegistration.register(messenger, this)
        // T-103: root heuristic, secure window, passcode check (UI engine only).
        DeviceSecurityRegistration.register(messenger, this)
        val store = ShareStores.create(applicationContext)
        shareStore = store
        ShareIntakeHostApi.setUp(messenger, ShareIntakeHost(store))
        shareEvents = ShareIntakeEventsApi(messenger)
        // T-041: the capture host and CaptureEventsApi on the UI engine (every
        // flavour); shuts a headless ingestion engine down first.
        val rt = CaptureRuntime.get(applicationContext)
        // T-044: the Activity-bound permission actions of the capture host.
        val perms = rt.device?.let { device ->
            ActivityPermissions(
                device = device,
                launch = { p, code -> requestPermissions(p, code) },
                openSettings = { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) },
                afterResult = rt::checkPermissions,
            )
        }
        capturePermissions = perms
        rt.attachUi(flutterEngine, perms)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (capturePermissions?.onResult(requestCode, permissions, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        CaptureRuntime.get(applicationContext).detachUi(flutterEngine)
        ShareIntakeHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        TextNormalizationHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        TrustedClockRegistration.unregister(flutterEngine.dartExecutor.binaryMessenger)
        DeviceSecurityRegistration.unregister(flutterEngine.dartExecutor.binaryMessenger)
        shareEvents = null
        shareStore = null
        capturePermissions = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /**
     * Warm start from the share target. Only an intent carrying the
     * per-process hand-off token may consume the refusal slot (F7): this
     * activity is exported, so any app can send it the action.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val presented = try {
            intent.getStringExtra(ShareHandOff.EXTRA_TOKEN)
        } catch (_: RuntimeException) {
            null
        }
        if (!ShareHandOff.token.matches(intent.action, presented)) return
        val events = shareEvents ?: return
        ShareIntakeState.takeRejection()?.let { reason ->
            events.onShareRejected(reason) { result ->
                if (result.isFailure) ShareIntakeState.setRejected(reason)
            }
        }
    }

    /**
     * Every resume (F7): announce every pending share. It reads only the
     * store, so a spoofed intent cannot consume anything; Dart dedupes by id.
     * On a cold start Dart is not listening yet and polls by itself.
     */
    override fun onResume() {
        super.onResume()
        // T-044 (EC-13): a permission or notification access changed while away.
        CaptureRuntime.get(applicationContext).checkPermissions()
        val store = shareStore ?: return
        IO.execute {
            val pending: List<ShareDescriptor> = try {
                store.list()
            } catch (_: Exception) {
                emptyList()
            }
            if (pending.isEmpty()) return@execute
            MAIN.post {
                val events = shareEvents ?: return@post
                pending.forEach { events.onShareReceived(it) { } }
            }
        }
    }

    private companion object {
        val MAIN = Handler(Looper.getMainLooper())
        val IO = Executors.newSingleThreadExecutor { r -> Thread(r, "zaghlol-share-list").apply { isDaemon = true } }
    }
}
