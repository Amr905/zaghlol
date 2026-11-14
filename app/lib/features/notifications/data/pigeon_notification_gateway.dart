// NOTIF-GW: the local-notification gateway over the Pigeon host
// (platform-channels 4c). Local only: no push, no analytics. The text is
// already redacted by NotificationService when the user hides amounts; the
// lock-screen "public" label on Android is the channel name, which never
// carries an amount. Nothing here logs; errors drop the native message.

import 'dart:async';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/platform/notifications_api.g.dart';
import '../domain/notification_types.dart';

/// Stable Android channel ids, one per alert type. Never rename a released id:
/// the user's per-channel settings hang on it.
String notificationChannelId(NotificationType t) => switch (t) {
  NotificationType.budgetThreshold => 'zaghlol_alert_budget',
  NotificationType.spendingSpike => 'zaghlol_alert_spike',
  NotificationType.upcomingDue => 'zaghlol_alert_due',
  NotificationType.duplicateCharge => 'zaghlol_alert_duplicate',
  NotificationType.subscriptionRenewal => 'zaghlol_alert_renewal',
  NotificationType.backupFailure => 'zaghlol_alert_backup_failure',
  NotificationType.weeklySummary => 'zaghlol_alert_weekly',
};

String _channelName(AppLocalizations l, NotificationType t) => switch (t) {
  NotificationType.budgetThreshold => l.notificationsSettingsBudget,
  NotificationType.spendingSpike => l.notificationsSettingsSpikes,
  NotificationType.upcomingDue => l.notificationsSettingsDues,
  NotificationType.duplicateCharge => l.notificationsSettingsDuplicates,
  NotificationType.subscriptionRenewal => l.notificationsSettingsRenewals,
  NotificationType.backupFailure => l.notificationsSettingsBackup,
  NotificationType.weeklySummary => l.notificationsSettingsWeekly,
};

final class PigeonNotificationGateway implements NotificationGateway {
  PigeonNotificationGateway({NotificationsHostApi? api, required this.l10n})
    : _api = api ?? NotificationsHostApi();

  final NotificationsHostApi _api;
  final AppLocalizations Function() l10n;
  String? _channelsFor;

  /// Creates or renames the channels in the current language, once per
  /// language.
  Future<void> ensureChannels() async {
    final l = l10n();
    if (_channelsFor == l.localeName) return;
    await _api.ensureChannels([
      for (final t in NotificationType.values)
        NotifChannelMsg(id: notificationChannelId(t), name: _channelName(l, t)),
    ]);
    _channelsFor = l.localeName;
  }

  NotifMsg _msg(PlatformNotification n) {
    final type = n.type ?? NotificationType.budgetThreshold;
    return NotifMsg(
      id: n.id,
      channelId: notificationChannelId(type),
      title: n.title,
      body: n.body,
      publicTitle: _channelName(l10n(), type),
      route: n.payload,
    );
  }

  @override
  Future<void> show(PlatformNotification n) async {
    await ensureChannels();
    await _api.show(_msg(n));
  }

  @override
  Future<void> schedule(PlatformNotification n) async {
    await ensureChannels();
    final at = n.at;
    if (at == null) return show(n);
    await _api.schedule(_msg(n), at.toUtc().millisecondsSinceEpoch);
  }

  /// Taken from the platform on cancel-all paths and tests.
  Future<void> cancelAll() => _api.cancelAll();
}

final class PigeonNotificationPermission implements NotificationPermissionPort {
  PigeonNotificationPermission({NotificationsHostApi? api, this.onGranted})
    : _api = api ?? NotificationsHostApi();

  final NotificationsHostApi _api;

  /// Runs after a grant (the channels are created in the user's language).
  final Future<void> Function()? onGranted;

  @override
  Future<bool> isAllowed() async {
    try {
      return await _api.permissionStatus() == NotifPermissionMsg.granted;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> request() async {
    try {
      final ok = await _api.requestPermission();
      if (ok) await onGranted?.call();
      return ok;
    } on Object {
      return false;
    }
  }
}

/// Taps through the Pigeon events API. Registers itself as the handler.
final class PigeonNotificationTaps
    implements NotificationTapSource, NotificationsEventsApi {
  PigeonNotificationTaps({NotificationsHostApi? api})
    : _api = api ?? NotificationsHostApi() {
    NotificationsEventsApi.setUp(this);
  }

  final NotificationsHostApi _api;
  final _controller = StreamController<String>.broadcast();

  @override
  Stream<String> get taps => _controller.stream;

  @override
  void onTap(String route) => _controller.add(route);

  @override
  Future<String?> takeLaunchRoute() async {
    try {
      return await _api.takeLaunchRoute();
    } on Object {
      return null;
    }
  }
}
