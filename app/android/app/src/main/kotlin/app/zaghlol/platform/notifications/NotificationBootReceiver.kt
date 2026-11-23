package app.zaghlol.platform.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * T-230: re-arms the saved schedules after a reboot. Not exported; only the
 * system's BOOT_COMPLETED reaches it (any other action is ignored). Not
 * direct-boot aware on purpose: the store lives in credential-protected
 * storage, so it runs once the user has unlocked the phone.
 */
class NotificationBootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
    try {
      NotificationPresenter(context).rearmAfterBoot(System.currentTimeMillis())
    } catch (_: RuntimeException) {
      // Never log; the app re-schedules at its next run.
    }
  }
}
