package app.zaghlol.platform.notifications

/**
 * NOTIF-GW: the stable ids of the alert channels (one per alert type). Dart
 * sends the localized names; ids never change after release (a renamed id
 * would orphan the user's per-channel settings). The capture channel of the
 * ingestion worker is separate and lives in IngestionWorker.
 */
object NotificationChannels {
  val IDS: List<String> =
    listOf(
      "zaghlol_alert_budget",
      "zaghlol_alert_spike",
      "zaghlol_alert_due",
      "zaghlol_alert_duplicate",
      "zaghlol_alert_renewal",
      "zaghlol_alert_backup_failure",
      "zaghlol_alert_weekly",
    )

  /** Anything not in [IDS] is shown on the first channel rather than dropped. */
  fun resolve(id: String): String = if (id in IDS) id else IDS.first()
}

/**
 * Pending alarm ids, kept so "Delete everything" can cancel alarms. Ids only,
 * never text.
 */
interface PendingIdStore {
  fun all(): Set<Int>

  fun add(id: Int)

  fun remove(id: Int)

  fun clear()
}

/** A route id is a short in-app path; anything else is dropped. */
object NotificationRoutes {
  const val EXTRA_ROUTE = "app.zaghlol.notification.route"
  private const val MAX = 96

  fun clean(route: String?): String? =
    route?.takeIf { it.length in 1..MAX && it.startsWith("/") && it.all { c -> c.code in 0x21..0x7E } }

  @Volatile private var launchRoute: String? = null

  fun setLaunchRoute(route: String?) {
    launchRoute = clean(route)
  }

  /** Once: a second call answers null. */
  @Synchronized
  fun takeLaunchRoute(): String? {
    val r = launchRoute
    launchRoute = null
    return r
  }
}
