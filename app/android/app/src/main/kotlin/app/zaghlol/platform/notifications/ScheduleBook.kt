package app.zaghlol.platform.notifications

import java.io.File
import java.net.URLDecoder
import java.net.URLEncoder

/** One scheduled alert: when, and the already-redacted fields that were scheduled. */
data class ScheduledAlert(val atEpochMs: Long, val fields: Map<String, Any?>) {
  val id: Int get() = fields[NotificationPresenter.K_ID] as Int
}

interface ScheduleStore {
  fun load(): List<ScheduledAlert>

  fun save(all: List<ScheduledAlert>)
}

/**
 * T-230: the pending schedules, so a reboot (which clears AlarmManager) can
 * re-arm them. Holds only what the notification itself would show (ids, times,
 * the text Dart already redacted); never anything else. Kept in step with the
 * alarms: written on schedule, removed on fire, cancel and cancelAll.
 */
class ScheduleBook(private val store: ScheduleStore) {
  @Synchronized
  fun add(alert: ScheduledAlert) = store.save(store.load().filter { it.id != alert.id } + alert)

  @Synchronized
  fun remove(id: Int) {
    val all = store.load()
    if (all.any { it.id == id }) store.save(all.filter { it.id != id })
  }

  @Synchronized fun clear() = store.save(emptyList())

  /**
   * After a reboot: alerts still in the future are re-armed with the same id and
   * time. Past-due ones are DROPPED (not shown), so a restart never fires a
   * burst of stale alerts; the app re-derives and reschedules at its next run.
   */
  @Synchronized
  fun rearm(nowMs: Long, arm: (Map<String, Any?>, Long) -> Unit): Int {
    val (future, past) = store.load().partition { it.atEpochMs > nowMs }
    if (past.isNotEmpty()) store.save(future)
    future.forEach { arm(it.fields, it.atEpochMs) }
    return future.size
  }
}

/** File under `noBackupFilesDir/notif` (not in OS backups); wiped with the data. */
class FileScheduleStore(private val file: File) : ScheduleStore {
  constructor(context: android.content.Context) :
    this(File(File(context.applicationContext.noBackupFilesDir, "notif"), "schedules.txt"))

  private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

  private fun dec(s: String) = URLDecoder.decode(s, "UTF-8")

  override fun load(): List<ScheduledAlert> =
    try {
      if (!file.exists()) emptyList()
      else
        file.readLines().mapNotNull { line ->
          try {
            val parts = line.split('\t')
            val at = parts[0].toLong()
            val m = mutableMapOf<String, Any?>()
            for (p in parts.drop(1)) {
              val (k, t, v) = p.split('=', limit = 3)
              m[dec(k)] = if (t == "i") dec(v).toInt() else dec(v)
            }
            if (m[NotificationPresenter.K_ID] is Int) ScheduledAlert(at, m) else null
          } catch (_: RuntimeException) {
            null
          }
        }
    } catch (_: java.io.IOException) {
      emptyList()
    }

  override fun save(all: List<ScheduledAlert>) {
    try {
      if (all.isEmpty()) {
        file.delete()
        return
      }
      file.parentFile?.mkdirs()
      file.writeText(
        all.joinToString("\n") { a ->
          val kv =
            a.fields.entries.mapNotNull { (k, v) ->
              when (v) {
                is String -> "${enc(k)}=s=${enc(v)}"
                is Int -> "${enc(k)}=i=${enc(v.toString())}"
                else -> null
              }
            }
          (listOf(a.atEpochMs.toString()) + kv).joinToString("\t")
        }
      )
    } catch (_: java.io.IOException) {
      // Best effort; a lost entry only means one alert is not re-armed.
    }
  }
}
