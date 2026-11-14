package app.zaghlol.platform.notifications

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import app.zaghlol.MainActivity
import app.zaghlol.R
import java.io.File

/**
 * NOTIF-GW: builds and posts the alerts. Text arrives already redacted by Dart
 * according to the hide-amounts setting. Because a user may still allow
 * amounts on the lock screen in the app but not in the system, every
 * notification also carries a public version (a label only, no amount) and has
 * private visibility. Nothing here logs; the text is never echoed.
 */
class NotificationPresenter(private val context: Context) {
  private val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
  private val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
  private val pending = FilePendingIds(context)

  fun ensureChannels(channels: List<Pair<String, String>>) {
    for ((id, name) in channels) {
      if (id !in NotificationChannels.IDS) continue
      val ch = NotificationChannel(id, name, NotificationManager.IMPORTANCE_DEFAULT)
      ch.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
      ch.setShowBadge(false)
      nm.createNotificationChannel(ch)
    }
  }

  fun show(m: Map<String, Any?>) {
    nm.notify(m.id(), build(context, m))
    pending.remove(m.id())
  }

  /** Inexact on purpose: no SCHEDULE_EXACT_ALARM permission. Lost at reboot. */
  fun schedule(m: Map<String, Any?>, atEpochMs: Long) {
    val intent = Intent(context, NotificationAlarmReceiver::class.java).setPackage(context.packageName)
    for ((k, v) in m) if (v is String) intent.putExtra(k, v) else if (v is Int) intent.putExtra(k, v)
    val pi =
      PendingIntent.getBroadcast(
        context,
        m.id(),
        intent,
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
      )
    alarms.setAndAllowWhileIdle(AlarmManager.RTC, atEpochMs, pi)
    pending.add(m.id())
  }

  fun cancelAll() {
    nm.cancelAll()
    for (id in pending.all()) {
      val pi =
        PendingIntent.getBroadcast(
          context,
          id,
          Intent(context, NotificationAlarmReceiver::class.java).setPackage(context.packageName),
          PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_NO_CREATE,
        )
      if (pi != null) {
        alarms.cancel(pi)
        pi.cancel()
      }
    }
    pending.clear()
  }

  companion object {
    const val K_ID = "id"
    const val K_CHANNEL = "channelId"
    const val K_TITLE = "title"
    const val K_BODY = "body"
    const val K_PUBLIC = "publicTitle"
    const val K_ROUTE = "route"

    private fun Map<String, Any?>.id(): Int = (this[K_ID] as Int)

    fun build(context: Context, m: Map<String, Any?>): Notification {
      val channel = NotificationChannels.resolve(m[K_CHANNEL] as? String ?: "")
      val publicVersion =
        Notification.Builder(context, channel)
          .setSmallIcon(R.mipmap.ic_launcher)
          .setContentTitle(m[K_PUBLIC] as? String ?: "")
          .build()
      val tap =
        Intent(context, MainActivity::class.java)
          .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
      NotificationRoutes.clean(m[K_ROUTE] as? String)?.let { tap.putExtra(NotificationRoutes.EXTRA_ROUTE, it) }
      val content =
        PendingIntent.getActivity(
          context,
          m[K_ID] as Int,
          tap,
          PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
      return Notification.Builder(context, channel)
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle(m[K_TITLE] as? String ?: "")
        .setContentText(m[K_BODY] as? String ?: "")
        .setStyle(Notification.BigTextStyle().bigText(m[K_BODY] as? String ?: ""))
        .setVisibility(Notification.VISIBILITY_PRIVATE)
        .setPublicVersion(publicVersion)
        .setCategory(Notification.CATEGORY_STATUS)
        .setAutoCancel(true)
        .setContentIntent(content)
        .build()
    }
  }
}

/**
 * Ids only, one per line in a file under `noBackupFilesDir` (no plain
 * preferences, T-015 AC2); cleared by cancelAll and by the wipe.
 */
class FilePendingIds(context: Context) : PendingIdStore {
  private val file = File(File(context.applicationContext.noBackupFilesDir, "notif"), "pending.ids")

  @Synchronized
  override fun all(): Set<Int> =
    try {
      if (file.exists()) file.readLines().mapNotNull { it.trim().toIntOrNull() }.toSet() else emptySet()
    } catch (_: java.io.IOException) {
      emptySet()
    }

  @Synchronized
  private fun write(ids: Set<Int>) {
    try {
      file.parentFile?.mkdirs()
      file.writeText(ids.joinToString("\n"))
    } catch (_: java.io.IOException) {
      // Best effort; a lost id only means one alarm cannot be cancelled.
    }
  }

  override fun add(id: Int) = write(all() + id)

  override fun remove(id: Int) = write(all() - id)

  @Synchronized
  override fun clear() {
    file.delete()
  }
}
