package app.zaghlol

import android.content.Intent
import android.os.Handler
import android.os.Looper
import app.zaghlol.platform.attestation.AttestationRegistration
import android.provider.Settings
import app.zaghlol.platform.capture.ActivityPermissions
import app.zaghlol.platform.capture.CaptureRuntime
import app.zaghlol.platform.clock.TrustedClockRegistration
import app.zaghlol.platform.device.AndroidDeviceEnv
import app.zaghlol.platform.diag.SmsDiagChannel
import app.zaghlol.platform.device.DeviceSecurityRegistration
import app.zaghlol.platform.device.SecureWindowState
import app.zaghlol.platform.keys.SecretStoreRegistration
import app.zaghlol.platform.launchtheme.LaunchTheme
import app.zaghlol.platform.notifications.NotificationHandOff
import app.zaghlol.platform.notifications.NotificationPresenter
import app.zaghlol.platform.notifications.NotificationRoutes
import app.zaghlol.platform.notifications.NotificationsEventsApi
import app.zaghlol.platform.backupwork.BackupWorkHost
import app.zaghlol.platform.backupwork.BackupWorkHostApi
import app.zaghlol.platform.notifications.NotificationsHost
import app.zaghlol.platform.notifications.NotificationsRegistration
import app.zaghlol.platform.ocr.OcrHostApi
import app.zaghlol.platform.ocr.OcrHosts
import app.zaghlol.platform.share.ShareDescriptor
import app.zaghlol.platform.share.ShareHandOff
import app.zaghlol.platform.share.ShareIntakeEventsApi
import app.zaghlol.platform.share.ShareIntakeHost
import app.zaghlol.platform.share.ShareIntakeHostApi
import app.zaghlol.platform.share.ShareIntakeState
import app.zaghlol.platform.share.ShareStore
import app.zaghlol.platform.share.ShareStores
import app.zaghlol.platform.sharesheet.ShareImageRegistration
import app.zaghlol.platform.speech.SpeechSupportRegistration
import app.zaghlol.platform.text.TextNormalizationHostApi
import app.zaghlol.platform.text.TextNormalizationRegistration
import app.zaghlol.platform.widget.WidgetBridgeRegistration
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

// T-103: BiometricPrompt (DeviceSecurityHost.authenticate) needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    private var shareEvents: ShareIntakeEventsApi? = null
    private var shareStore: ShareStore? = null
    private var capturePermissions: ActivityPermissions? = null
    private var notificationsHost: NotificationsHost? = null
    private var notificationEvents: NotificationsEventsApi? = null

    // T-224: the stored in-app theme choice decides which night/day resources
    // (theme, launch drawable) resolve for this activity, before the first frame.
    override fun attachBaseContext(newBase: android.content.Context) {
        super.attachBaseContext(LaunchTheme.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // T-103: a re-created activity is secured again before its first frame.
        if (SecureWindowState.requested) AndroidDeviceEnv.applyTo(this, true)
        super.onCreate(savedInstanceState)
    }
    private var ocrExecutor: ExecutorService? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // T-015: the database key store. The T-008 headless engine must register
        // it too (every engine that opens the database).
        SecretStoreRegistration.register(messenger, this)
        // T-148: NFC for the backup passphrase (UI engine only).
        TextNormalizationRegistration.register(messenger)
        // T-118: the home-screen widget snapshot (UI engine only).
        WidgetBridgeRegistration.register(messenger, this)
        // T-180: trusted clock sample for the Gold offline bound.
        TrustedClockRegistration.register(messenger, this)
        // T-103: root heuristic, secure window, passcode check (UI engine only).
        DeviceSecurityRegistration.register(messenger, this)
        // T-178: Play Integrity for restore (UI engine only).
        AttestationRegistration.register(messenger, this)
        // T-117: system chooser for the share-studio PNG (UI engine only).
        ShareImageRegistration.register(messenger, this)
        // T-120: on-device speech support check (UI engine only).
        SpeechSupportRegistration.register(messenger, this)
        // T-224: the theme choice (light/dark/system only) for the next cold start.
        MethodChannel(messenger, "zaghlol/launch_theme").setMethodCallHandler { call, result ->
            if (call.method != "set") {
                result.notImplemented()
            } else if (LaunchTheme.write(applicationContext.noBackupFilesDir, call.arguments as? String)) {
                result.success(null)
            } else {
                result.error("invalid", null, null)
            }
        }
        // FU-229b: "Open settings" of a denied permission opens the app details page.
        MethodChannel(messenger, "zaghlol/app_settings").setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
            } else {
                try {
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.fromParts("package", packageName, null),
                        ),
                    )
                    result.success(null)
                } catch (_: RuntimeException) {
                    result.error("unavailable", null, null)
                }
            }
        }
        // NOTIF-GW: local alerts, channels, POST_NOTIFICATIONS (UI engine only).
        val notifHost = NotificationsHost(
            applicationContext,
            NotificationPresenter(applicationContext),
            launchPrompt = {
                requestPermissions(
                    arrayOf("android.permission.POST_NOTIFICATIONS"),
                    NotificationsHost.REQUEST_CODE,
                )
            },
        )
        notificationsHost = notifHost
        notificationEvents = NotificationsEventsApi(messenger)
        NotificationsRegistration.register(messenger, notifHost)
        // FU-168e: the periodic backup wake-up (UI engine only; the job runs no Dart).
        BackupWorkHostApi.setUp(messenger, BackupWorkHost(applicationContext))
        // L-1: route and cancel id only from our own trampoline.
        // A plain launch (or a Recents relaunch) clears a stale route.
        val launch = intent?.let { acceptedNotification(it) }
        NotificationRoutes.setLaunchRoute(launch?.route)
        launch?.let { dismissActionNotification(it) }
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
        // SMS-device: debug-only counters screen (dev flavours; no-op elsewhere).
        SmsDiagChannel.register(messenger, applicationContext)
        // T-159: OCR reads pending shares from the same encrypted store.
        val (ocr, executor) = OcrHosts.create(applicationContext, store)
        ocrExecutor = executor
        OcrHostApi.setUp(messenger, ocr)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == NotificationsHost.REQUEST_CODE) {
            notificationsHost?.onPromptResult()
            return
        }
        if (capturePermissions?.onResult(requestCode, permissions, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        SmsDiagChannel.unregister(flutterEngine.dartExecutor.binaryMessenger)
        CaptureRuntime.get(applicationContext).detachUi(flutterEngine)
        ShareIntakeHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        TextNormalizationHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        WidgetBridgeRegistration.unregister(flutterEngine.dartExecutor.binaryMessenger)
        TrustedClockRegistration.unregister(flutterEngine.dartExecutor.binaryMessenger)
        DeviceSecurityRegistration.unregister(flutterEngine.dartExecutor.binaryMessenger)
        AttestationRegistration.unregister(flutterEngine.dartExecutor.binaryMessenger)
        ShareImageRegistration.unregister(flutterEngine.dartExecutor.binaryMessenger)
        ShareImageRegistration.sweepAll(this)
        SpeechSupportRegistration.unregister(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zaghlol/app_settings").setMethodCallHandler(null)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zaghlol/launch_theme").setMethodCallHandler(null)
        NotificationsRegistration.unregister(flutterEngine.dartExecutor.binaryMessenger)
        BackupWorkHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        notificationsHost = null
        notificationEvents = null
        OcrHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        ocrExecutor?.shutdown()
        ocrExecutor = null
        shareEvents = null
        shareStore = null
        capturePermissions = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** L-1: the route and cancel id of [intent], or null unless it carries our hand-off token. */
    private fun acceptedNotification(intent: Intent): NotificationRoutes.Accepted? =
        try {
            val cancel = intent.getIntExtra(NotificationRoutes.EXTRA_CANCEL_ID, Int.MIN_VALUE)
            NotificationRoutes.accept(
                intent.action,
                intent.getStringExtra(NotificationHandOff.EXTRA_TOKEN),
                intent.getStringExtra(NotificationRoutes.EXTRA_ROUTE),
                if (cancel == Int.MIN_VALUE) null else cancel,
                (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0,
            )
        } catch (_: RuntimeException) {
            null
        }

    /** An action button does not auto-cancel: dismiss the notification it came from. */
    private fun dismissActionNotification(accepted: NotificationRoutes.Accepted) {
        val id = accepted.cancelId ?: return
        (getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager).cancel(id)
    }

    /**
     * Warm start from the share target. Only an intent carrying the
     * per-process hand-off token may consume the refusal slot (F7): this
     * activity is exported, so any app can send it the action.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // NOTIF-GW: a tap while running goes to Dart; the route is validated
        // here and again in Dart (allow-list).
        acceptedNotification(intent)?.let { a ->
            dismissActionNotification(a)
            a.route?.let { r -> notificationEvents?.onTap(r) { } }
        }
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
