package app.zaghlol.platform.notifications

import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Proof that a notification route or cancel id came from our own
 * PendingIntent (L-1). `MainActivity` is exported (launcher), so any app can
 * send it the route extras. Notification PendingIntents therefore target the
 * non-exported [NotificationTapActivity], which runs in this same process and
 * forwards to `MainActivity` with this per-process random token. The
 * PendingIntents are created long before the tap and survive process death,
 * so they carry no token themselves: the trampoline adds the current
 * process's token at tap time. Same scheme as the share path (F7,
 * `ShareHandOff`). The token never leaves the process except inside our own
 * explicit intent.
 */
class NotificationHandOffToken(random: SecureRandom = SecureRandom()) {
  val value: String = ByteArray(16).also { random.nextBytes(it) }.joinToString("") { "%02x".format(it) }

  fun matches(action: String?, presented: String?): Boolean {
    if (action != NotificationHandOff.ACTION_TAP || presented == null) return false
    return MessageDigest.isEqual(value.toByteArray(Charsets.US_ASCII), presented.toByteArray(Charsets.US_ASCII))
  }
}

object NotificationHandOff {
  const val ACTION_TAP = "app.zaghlol.action.NOTIFICATION_TAP"
  const val EXTRA_TOKEN = "app.zaghlol.extra.NOTIFICATION_TOKEN"

  val token = NotificationHandOffToken()
}
