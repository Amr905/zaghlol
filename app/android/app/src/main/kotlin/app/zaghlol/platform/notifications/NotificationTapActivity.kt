package app.zaghlol.platform.notifications

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import app.zaghlol.MainActivity

/**
 * L-1: the target of every notification PendingIntent. Not exported, so only
 * our own PendingIntents reach it. It has no UI: it forwards the route and
 * cancel id to `MainActivity` together with the per-process
 * [NotificationHandOff] token and finishes. `MainActivity` ignores both
 * extras without that token.
 */
class NotificationTapActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val forward =
      Intent(this, MainActivity::class.java)
        .setAction(NotificationHandOff.ACTION_TAP)
        .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        .putExtra(NotificationHandOff.EXTRA_TOKEN, NotificationHandOff.token.value)
    try {
      intent?.getStringExtra(NotificationRoutes.EXTRA_ROUTE)?.let { forward.putExtra(NotificationRoutes.EXTRA_ROUTE, it) }
      if (intent?.hasExtra(NotificationRoutes.EXTRA_CANCEL_ID) == true) {
        forward.putExtra(
          NotificationRoutes.EXTRA_CANCEL_ID,
          intent.getIntExtra(NotificationRoutes.EXTRA_CANCEL_ID, Int.MIN_VALUE),
        )
      }
    } catch (_: RuntimeException) {
      // A malformed extra: open the app with nothing.
    }
    startActivity(forward)
    finish()
  }
}
