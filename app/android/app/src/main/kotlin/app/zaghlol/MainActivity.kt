package app.zaghlol

import android.content.Intent
import android.os.Handler
import android.os.Looper
import app.zaghlol.platform.capture.EngineHooks
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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var shareEvents: ShareIntakeEventsApi? = null
    private var shareStore: ShareStore? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // T-015: the database key store. The T-008 headless engine must register
        // it too (every engine that opens the database).
        SecretStoreRegistration.register(messenger, this)
        // T-148: NFC for the backup passphrase (UI engine only).
        TextNormalizationRegistration.register(messenger)
        val store = ShareStores.create(applicationContext)
        shareStore = store
        ShareIntakeHostApi.setUp(messenger, ShareIntakeHost(store))
        shareEvents = ShareIntakeEventsApi(messenger)
        // T-008: flavour hooks (devSms: the SMS spike's spool host). Empty in
        // every other build.
        EngineHooks.attach(flutterEngine, applicationContext)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        EngineHooks.detach(flutterEngine)
        ShareIntakeHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        TextNormalizationHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        shareEvents = null
        shareStore = null
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
