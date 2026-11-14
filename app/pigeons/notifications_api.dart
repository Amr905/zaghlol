// Pigeon contract: local notifications (NOTIF-GW). Local only: no push, no FCM,
// no APNs remote registration. Contract text: platform-channels.md section 4c.
// Regenerate with app/tool/generate_pigeon.sh; CI fails when stale.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/notifications_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/notifications/NotificationsApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.notifications',
      errorClassName: 'NotificationsApiError',
    ),
    swiftOut: 'ios/Runner/Platform/NotificationsApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'NotificationsApiError'),
  ),
)
enum NotifPermissionMsg { granted, denied, undetermined }

/// One Android channel (ignored on iOS). [id] is stable across releases;
/// [name] is the localized label shown in system settings.
class NotifChannelMsg {
  NotifChannelMsg({required this.id, required this.name});
  String id;
  String name;
}

/// One notification, already redacted by Dart. [publicTitle] is what the lock
/// screen shows on Android when the device hides sensitive content: a label
/// that carries no amount. [route] is a route id, never data.
class NotifMsg {
  NotifMsg({
    required this.id,
    required this.channelId,
    required this.title,
    required this.body,
    required this.publicTitle,
    this.route,
  });
  int id;
  String channelId;
  String title;
  String body;
  String publicTitle;
  String? route;
}

@HostApi()
abstract class NotificationsHostApi {
  /// iOS: the authorization status; Android: POST_NOTIFICATIONS on API 33+
  /// (granted below 33 unless the user turned notifications off).
  @async
  NotifPermissionMsg permissionStatus();

  /// Shows the system prompt when the status is undetermined (iOS alert, sound,
  /// badge; Android 13+ POST_NOTIFICATIONS). True when notifications are
  /// allowed afterwards. Never prompts twice for a denied answer.
  @async
  bool requestPermission();

  /// Creates or renames the channels (Android 8+; no-op on iOS).
  void ensureChannels(List<NotifChannelMsg> channels);

  void show(NotifMsg n);

  /// Shows [n] at [atEpochMs] (UTC). Android: an inexact alarm that is lost at
  /// reboot; iOS: a pending request that survives it.
  void schedule(NotifMsg n, int atEpochMs);

  /// Cancels shown and scheduled notifications.
  void cancelAll();

  /// The route of the notification that launched the app, once.
  String? takeLaunchRoute();

  /// Opens the system notification settings of this app (Android: the app's
  /// notification page; iOS: the app's page in Settings).
  void openSystemSettings();
}

@FlutterApi()
abstract class NotificationsEventsApi {
  /// The user tapped a notification while the app was running.
  void onTap(String route);
}
