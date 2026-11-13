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
  });

  /// Stable per dedupe key.
  final int id;
  final String title;
  final String body;
  final String? payload;

  /// Null: show now. Otherwise the UTC instant to show at.
  final DateTime? at;
}

/// The platform port (flutter_local_notifications adapter lands with the
/// device wiring; tests use a fake).
abstract interface class NotificationGateway {
  Future<void> show(PlatformNotification n);
  Future<void> schedule(PlatformNotification n);
}
