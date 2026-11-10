package app.zaghlol

import android.content.Intent
import app.zaghlol.platform.share.ShareActivity
import app.zaghlol.platform.share.ShareIntakeEventsApi
import app.zaghlol.platform.share.ShareIntakeHost
import app.zaghlol.platform.share.ShareIntakeHostApi
import app.zaghlol.platform.share.ShareIntakeState
import app.zaghlol.platform.share.ShareStores
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var shareEvents: ShareIntakeEventsApi? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        ShareIntakeHostApi.setUp(messenger, ShareIntakeHost(ShareStores.create(applicationContext)))
        shareEvents = ShareIntakeEventsApi(messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ShareIntakeHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        shareEvents = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Warm start: tell Dart now. On a cold start Dart polls listPendingShares / takePendingRejection. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action != ShareActivity.ACTION_SHARE_READY) return
        val events = shareEvents ?: return
        ShareIntakeState.takeRejection()?.let { reason ->
            events.onShareRejected(reason) { result ->
                if (result.isFailure) ShareIntakeState.setRejected(reason)
            }
            return
        }
        // A received share stays on disk, so Dart finds it by polling if this event is lost.
        ShareIntakeState.takeReceived()?.let { events.onShareReceived(it) { } }
    }
}
