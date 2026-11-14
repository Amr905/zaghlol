package app.zaghlol.platform.notifications

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * NOTIF-GW: fires a scheduled alert (quiet hours delay). Not exported; only the
 * app's own explicit PendingIntent reaches it.
 */
class NotificationAlarmReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val id = intent.getIntExtra(NotificationPresenter.K_ID, Int.MIN_VALUE)
    if (id == Int.MIN_VALUE) return
    val m =
      mapOf<String, Any?>(
        NotificationPresenter.K_ID to id,
        NotificationPresenter.K_CHANNEL to intent.getStringExtra(NotificationPresenter.K_CHANNEL),
        NotificationPresenter.K_TITLE to intent.getStringExtra(NotificationPresenter.K_TITLE),
        NotificationPresenter.K_BODY to intent.getStringExtra(NotificationPresenter.K_BODY),
        NotificationPresenter.K_PUBLIC to intent.getStringExtra(NotificationPresenter.K_PUBLIC),
        NotificationPresenter.K_ROUTE to intent.getStringExtra(NotificationPresenter.K_ROUTE),
      )
    try {
      val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      if (!nm.areNotificationsEnabled()) return
      nm.notify(id, NotificationPresenter.build(context, m))
    } catch (_: RuntimeException) {
      // Dropped; never log the text.
    } finally {
      PrefsPendingIds(context).remove(id)
    }
  }
}
