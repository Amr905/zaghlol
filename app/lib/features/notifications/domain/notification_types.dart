// T-094 (FR-NTF-01): the alert types. Each maps to its per-type toggle.

import '../../../core/settings/setting_key.dart';
import '../../../core/settings/settings_keys.dart';

enum NotificationType {
  budgetThreshold,
  spendingSpike,
  upcomingDue,
  duplicateCharge,
  subscriptionRenewal,
  backupFailure,
  weeklySummary;

  /// The setting that switches this type off.
  SettingKey<bool> get toggle => switch (this) {
    budgetThreshold => Settings.notifBudgetThreshold,
    spendingSpike => Settings.notifSpendingSpike,
    upcomingDue => Settings.notifUpcomingDue,
    duplicateCharge => Settings.notifDuplicateCharge,
    subscriptionRenewal => Settings.notifSubscriptionRenewal,
    backupFailure => Settings.notifBackupFailure,
    weeklySummary => Settings.notifWeeklySummary,
  };

  /// The `fired_alerts.kind` slug.
  String get kind => switch (this) {
    budgetThreshold => 'budget',
    spendingSpike => 'spike',
    upcomingDue => 'due',
    duplicateCharge => 'duplicate',
    subscriptionRenewal => 'renewal',
    backupFailure => 'backup_failure',
    weeklySummary => 'weekly',
  };
}

/// One alert. [title]/[body] are the full text (may carry amounts);
/// [redactedTitle]/[redactedBody] are shown instead when the user hides
/// amounts on the lock screen and must carry none. Callers build all four
/// from l10n; never from a raw SMS body. Q-33: a budget alert keeps its
/// category name in the redacted variant, only amounts go.
final class AlertRequest {
  const AlertRequest({
    required this.type,
    required this.subjectId,
    required this.periodKey,
    this.threshold = 0,
    required this.title,
    required this.body,
    required this.redactedTitle,
    required this.redactedBody,
    this.payload,
  });

  final NotificationType type;

  /// With [periodKey] and [threshold]: the `fired_alerts` dedupe key.
  final String subjectId;
  final String periodKey;
  final int threshold;
  final String title;
  final String body;
  final String redactedTitle;
  final String redactedBody;

  /// A route, never financial text.
  final String? payload;
}

/// What the platform is asked to show or schedule. Already redacted.
final class PlatformNotification {
  const PlatformNotification({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
    this.at,
    this.type,
  });

  /// Stable per dedupe key.
  final int id;
  final String title;
  final String body;
  final String? payload;

  /// Null: show now. Otherwise the UTC instant to show at.
  final DateTime? at;

  /// Picks the Android channel; null falls back to the budget channel.
  final NotificationType? type;
}

/// The platform port (NOTIF-GW: the Pigeon host adapter; tests use a fake).
abstract interface class NotificationGateway {
  Future<void> show(PlatformNotification n);
  Future<void> schedule(PlatformNotification n);
}

/// The notification permission (POST_NOTIFICATIONS on Android 13+, the iOS
/// authorization). Asked after onboarding and when the user first turns an
/// alert type on; never from a background path.
abstract interface class NotificationPermissionPort {
  /// True when alerts can be shown.
  Future<bool> isAllowed();

  /// Shows the system prompt when the answer is still open. True when alerts
  /// can be shown afterwards. Never throws.
  Future<bool> request();
}

/// Where taps on notifications come from: the route id of the notification
/// that launched the app (once), and the taps while the app runs.
abstract interface class NotificationTapSource {
  Future<String?> takeLaunchRoute();

  Stream<String> get taps;
}
