package app.zaghlol.platform.capture

import android.app.Notification
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Bank / wallet / online-bank notification capture (T-043, FR-ING-A-03/07).
 * Thin glue; every flavour (in `*NoSms` it is the primary live channel).
 * Access is granted by the user in system settings (T-044 sends them there).
 *
 * `onNotificationPosted` runs on the main thread and does no I/O and reads no
 * extras: it drops our own notification, group summaries, ongoing and
 * foreground-service notifications, and hands everything else to the
 * listener's own intake thread ([NotificationCapture]), where the package is
 * admitted **before** the extras are read.
 *
 * Not recovered (shown in the capture-health copy, T-047): notifications that
 * were refused, rate-limited or overflowed, and notifications posted while
 * the listener is unbound (app update, force stop, OEM kill, access revoked,
 * before first unlock). Only the `missedNotifications` count reaches Dart;
 * active notifications are not replayed on reconnect (PO decision). Nothing
 * is logged and no notification, extras or entry is ever put into a string.
 */
class BankNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val posted = sbn?.let(::SbnPosted) ?: return
        if (!NotificationFilter.accepts(posted, packageName)) return
        val wallMs = System.currentTimeMillis()
        val elapsedNs = SystemClock.elapsedRealtimeNanos()
        NotificationCapture.dispatcher(applicationContext).submit(NotificationItem(posted, wallMs, elapsedNs))
    }

    private class SbnPosted(private val sbn: StatusBarNotification) : PostedNotification {
        override val packageName: String? get() = sbn.packageName
        override val flags: Int get() = sbn.notification?.flags ?: Notification.FLAG_ONGOING_EVENT
        override fun fields(): NotificationFields = ExtrasFields(sbn.notification)

        override fun toString(): String = "PostedNotification"
    }

    private class ExtrasFields(private val n: Notification?) : NotificationFields {
        override fun title(): CharSequence? = n?.extras?.getCharSequence(Notification.EXTRA_TITLE)

        override fun text(): CharSequence? = n?.extras?.getCharSequence(Notification.EXTRA_TEXT)

        override fun bigText(): CharSequence? = n?.extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)

        override fun textLines(): Array<CharSequence>? = n?.extras?.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)

        override fun toString(): String = "NotificationFields"
    }
}
