package app.zaghlol.platform.share

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import app.zaghlol.MainActivity
import java.util.concurrent.Executors

/**
 * Exported share target (ACTION_SEND for text/plain, image, PDF, CSV). It has
 * no UI: it encrypts the payload on a worker thread, then opens
 * [MainActivity] with an intent that carries no content. It stays alive until
 * the copy is done because the sender's read grant is tied to this activity.
 * Never logs, and never reads the clipboard.
 */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val incoming = intent
        if (incoming?.action != Intent.ACTION_SEND) {
            finish()
            return
        }
        val source = IntentShareSource(contentResolver, incoming)
        val context = applicationContext
        val pkg = packageName
        EXECUTOR.execute {
            val outcome = try {
                ShareIntake(ShareStores.create(context), pkg).accept(source)
            } catch (_: Exception) {
                ShareOutcome.Rejected(ShareRejectReason.UNREADABLE)
            }
            runOnUiThread { handOff(outcome) }
        }
    }

    private fun handOff(outcome: ShareOutcome) {
        when (outcome) {
            is ShareOutcome.Accepted -> ShareIntakeState.setReceived(outcome.descriptor)
            is ShareOutcome.Rejected -> ShareIntakeState.setRejected(outcome.reason)
        }
        startActivity(
            Intent(this, MainActivity::class.java)
                .setAction(ACTION_SHARE_READY)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
        finish()
    }

    companion object {
        const val ACTION_SHARE_READY = "app.zaghlol.action.SHARE_READY"
        private val EXECUTOR = Executors.newSingleThreadExecutor()
    }
}
