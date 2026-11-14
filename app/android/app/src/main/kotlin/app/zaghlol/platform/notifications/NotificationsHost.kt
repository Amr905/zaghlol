package app.zaghlol.platform.notifications

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger

/**
 * NOTIF-GW: the Pigeon `NotificationsHostApi` (platform-channels 4c). Local
 * notifications only: no FCM, no remote registration. Text is never logged.
 */
class NotificationsHost(
  private val context: Context,
  private val presenter: NotificationPresenter,
  /** Launches the POST_NOTIFICATIONS prompt (needs the activity). Null: none. */
  private val launchPrompt: (() -> Unit)?,
) : NotificationsHostApi {
  private var waiting: MutableList<(Result<Boolean>) -> Unit> = mutableListOf()

  private fun allowed(): Boolean {
    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (!nm.areNotificationsEnabled()) return false
    return Build.VERSION.SDK_INT < 33 ||
      context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
  }

  override fun permissionStatus(callback: (Result<NotifPermissionMsg>) -> Unit) {
    // Android cannot tell "never asked" from "denied" without the prompt.
    callback(Result.success(if (allowed()) NotifPermissionMsg.GRANTED else NotifPermissionMsg.UNDETERMINED))
  }

  override fun requestPermission(callback: (Result<Boolean>) -> Unit) {
    if (allowed()) return callback(Result.success(true))
    if (Build.VERSION.SDK_INT < 33 || launchPrompt == null) return callback(Result.success(false))
    val first = waiting.isEmpty()
    waiting.add(callback)
    if (first) launchPrompt.invoke()
  }

  /** Called by the activity when the prompt ends. */
  fun onPromptResult() {
    val done = waiting
    waiting = mutableListOf()
    val ok = allowed()
    done.forEach { it(Result.success(ok)) }
  }

  override fun ensureChannels(channels: List<NotifChannelMsg>) {
    presenter.ensureChannels(channels.map { it.id to it.name })
  }

  override fun show(n: NotifMsg) = presenter.show(toMap(n))

  override fun schedule(n: NotifMsg, atEpochMs: Long) = presenter.schedule(toMap(n), atEpochMs)

  override fun cancelAll() = presenter.cancelAll()

  override fun takeLaunchRoute(): String? = NotificationRoutes.takeLaunchRoute()

  private fun toMap(n: NotifMsg): Map<String, Any?> =
    mapOf(
      NotificationPresenter.K_ID to n.id.toInt(),
      NotificationPresenter.K_CHANNEL to n.channelId,
      NotificationPresenter.K_TITLE to n.title,
      NotificationPresenter.K_BODY to n.body,
      NotificationPresenter.K_PUBLIC to n.publicTitle,
      NotificationPresenter.K_ROUTE to n.route,
    )

  companion object {
    const val REQUEST_CODE = 4418
  }
}

/** Registers the host on the UI engine. */
object NotificationsRegistration {
  fun register(messenger: BinaryMessenger, host: NotificationsHost) {
    NotificationsHostApi.setUp(messenger, host)
  }

  fun unregister(messenger: BinaryMessenger) {
    NotificationsHostApi.setUp(messenger, null)
  }
}
