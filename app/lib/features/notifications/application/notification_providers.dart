// T-100 wiring (WIRE-2): the notification service over the app database and
// settings, the l10n text of the alerts, the duplicate-charge check after an
// ingest batch or a manual add, and the weekly summary (run on app start and
// resume when 7 days have passed; no periodic scheduler exists yet). Text
// comes from l10n; nothing here logs or carries a raw message.

import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart' hide Settings;
import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/fired_alerts_dao.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../backup/application/schedule_providers.dart';
import '../../budget/application/budget_providers.dart';
import '../../budget/data/payday_schedule_store.dart' show localToday;
import '../../insights/data/chart_providers.dart';
import '../../transactions/data/transactions_providers.dart' show clockProvider;
import '../data/notification_service.dart';
import '../data/pigeon_notification_gateway.dart';
import '../domain/duplicate_charge.dart';
import '../domain/notification_types.dart';
import '../domain/quiet_hours.dart';
import 'backup_alert_sink.dart';
import 'duplicate_charge_alerts.dart';
import 'weekly_summary_alert.dart';

/// Shows and schedules platform notifications. Default: drops them (tests and
/// the headless engine). `main.dart` overrides it with [notificationWiringOverrides]
/// (NOTIF-GW: the Pigeon host, local notifications only). Dedupe state is
/// released when the gateway throws, but a silent gateway shows nothing.
final notificationGatewayProvider = Provider<NotificationGateway>(
  (ref) => const _SilentGateway(),
  name: 'notificationGatewayProvider',
);

/// The notification permission. Default: never allowed, never asks.
final notificationPermissionProvider = Provider<NotificationPermissionPort>(
  (ref) => const _NoPermission(),
  name: 'notificationPermissionProvider',
);

/// Taps on notifications. Default: none.
final notificationTapSourceProvider = Provider<NotificationTapSource>(
  (ref) => const _NoTaps(),
  name: 'notificationTapSourceProvider',
);

/// Asks for the notification permission once the user has a reason to:
/// after onboarding and when an alert type is first turned on. Never throws.
Future<bool> ensureNotificationPermission(WidgetRef ref) =>
    ref.read(notificationPermissionProvider).request();

/// The real notification wiring (NOTIF-GW), for the root ProviderScope.
final List<Override> notificationWiringOverrides = [
  notificationGatewayProvider.overrideWith(
    (ref) => PigeonNotificationGateway(l10n: () => notificationL10n(ref)),
  ),
  notificationPermissionProvider.overrideWith((ref) {
    final gateway = ref.watch(notificationGatewayProvider);
    return PigeonNotificationPermission(
      onGranted: gateway is PigeonNotificationGateway
          ? gateway.ensureChannels
          : null,
    );
  }),
  notificationTapSourceProvider.overrideWith((ref) => PigeonNotificationTaps()),
];

final class _NoPermission implements NotificationPermissionPort {
  const _NoPermission();

  @override
  Future<bool> isAllowed() async => false;

  @override
  Future<bool> request() async => false;
}

final class _NoTaps implements NotificationTapSource {
  const _NoTaps();

  @override
  Future<String?> takeLaunchRoute() async => null;

  @override
  Stream<String> get taps => const Stream<String>.empty();
}

final class _SilentGateway implements NotificationGateway {
  const _SilentGateway();

  @override
  Future<void> show(PlatformNotification n) async {}

  @override
  Future<void> schedule(PlatformNotification n) async {}
}

/// The strings of the language shown now (the setting, else the device).
AppLocalizations notificationL10n(Ref ref) {
  final locale =
      ref.read(appLocaleProvider) ?? PlatformDispatcher.instance.locale;
  final code = supportedLanguageCodes.contains(locale.languageCode)
      ? locale.languageCode
      : 'en';
  return lookupAppLocalizations(Locale(code));
}

String _lang(Ref ref) => notificationL10n(ref).localeName;

String _money(Ref ref, Money m) {
  final lang = _lang(ref);
  return MoneyFormat.format(
    m,
    languageCode: lang,
    digits: ref.read(digitsModeProvider(lang)),
  );
}

final notificationServiceProvider = FutureProvider<NotificationService>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final settings = await ref.watch(settingsRepositoryProvider.future);
  final fired = FiredAlertsDao(db);
  return NotificationService(
    gateway: ref.watch(notificationGatewayProvider),
    now: ref.watch(clockProvider),
    loadPrefs: () async {
      final enabled = <NotificationType, bool>{
        for (final t in NotificationType.values)
          t: await settings.get(t.toggle),
      };
      return NotificationPrefs(
        typeEnabled: (t) => enabled[t] ?? true,
        quietHours: QuietHours(
          enabled: await settings.get(Settings.quietHoursEnabled),
          startMin: await settings.get(Settings.quietHoursStartMin),
          endMin: await settings.get(Settings.quietHoursEndMin),
        ),
        hideAmounts: await settings.get(Settings.hideAmountsNotifications),
      );
    },
    markFired:
        ({
          required kind,
          required subjectId,
          required periodKey,
          required threshold,
          required at,
        }) => fired.markFired(
          kind: kind,
          subjectId: subjectId,
          periodKey: periodKey,
          threshold: threshold,
          at: at,
        ),
    unmarkFired:
        ({
          required kind,
          required subjectId,
          required periodKey,
          required threshold,
        }) => fired.unmarkFired(
          kind: kind,
          subjectId: subjectId,
          periodKey: periodKey,
          threshold: threshold,
        ),
  );
}, name: 'notificationServiceProvider');

/// Binds [backupAlertSinkProvider] (T-152) to the notification service.
final backupAlertSinkOverride = backupAlertSinkProvider.overrideWith(
  (ref) => (kind, {required periodKey}) async {
    final service = await ref.read(notificationServiceProvider.future);
    await backupAlertSinkOver(service, () => notificationL10n(ref))(
      kind,
      periodKey: periodKey,
    );
  },
);

/// Live expense transactions at or after [fromMs] for the duplicate check.
Future<List<DupTxn>> recentExpenses(AppDatabase db, int fromMs) async {
  final rows = await db
      .customSelect(
        'SELECT id, account_id, merchant_norm, amount_minor, currency, '
        'occurred_at FROM transactions '
        "WHERE deleted_at IS NULL AND direction = 'expense' "
        "AND status = 'posted' AND is_internal = 0 "
        'AND merchant_norm IS NOT NULL AND occurred_at >= ?1 '
        'ORDER BY occurred_at, id',
        variables: [Variable.withInt(fromMs)],
        readsFrom: {db.transactions},
      )
      .get();
  return [
    for (final r in rows)
      DupTxn(
        id: r.read<String>('id'),
        accountId: r.read<String>('account_id'),
        merchantNorm: r.read<String>('merchant_norm'),
        amountMinor: r.read<int>('amount_minor'),
        currency: r.read<String>('currency'),
        occurredAtMs: r.read<int>('occurred_at'),
      ),
  ];
}

final duplicateChargeAlertsProvider = FutureProvider<DuplicateChargeAlerts>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final service = await ref.watch(notificationServiceProvider.future);
  return DuplicateChargeAlerts(
    notifications: service,
    recent: (from) => recentExpenses(db, from),
    text: (cluster, amount) {
      final l = notificationL10n(ref);
      return (
        title: l.notificationsAlertDuplicateTitle,
        body: l.notificationsAlertDuplicate(
          cluster.first.merchantNorm,
          _money(ref, amount),
        ),
        redactedTitle: l.notificationsAlertDuplicateTitle,
        redactedBody: l.notificationsAlertDuplicateHidden,
      );
    },
  );
}, name: 'duplicateChargeAlertsProvider');

/// Runs the duplicate-charge check now. Best effort: an alert that cannot be
/// raised never fails the ingest or the add that triggered it.
final duplicateCheckProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      final alerts = await ref.read(duplicateChargeAlertsProvider.future);
      await alerts.run(
        ref.read(clockProvider)().toUtc().millisecondsSinceEpoch,
      );
    } on Object {
      // Code-free by design; the next batch looks at the same window again.
    }
  };
}, name: 'duplicateCheckProvider');

final weeklySummaryAlertProvider = FutureProvider<WeeklySummaryAlert>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final charts = await ref.watch(chartRepositoryProvider.future);
  final service = await ref.watch(notificationServiceProvider.future);
  // The text builder is synchronous, so the names are read here, once.
  final names = <String, String>{};
  final rows = await db
      .customSelect(
        'SELECT id, name_ar, name_en FROM categories',
        readsFrom: {db.categories},
      )
      .get();
  for (final r in rows) {
    final id = r.read<String>('id');
    names['ar|$id'] = r.read<String>('name_ar');
    names['en|$id'] = r.read<String>('name_en');
  }
  return WeeklySummaryAlert.over(
    charts,
    notifications: service,
    text: (spent, categoryId) {
      final l = notificationL10n(ref);
      return (
        title: l.notificationsAlertWeeklyTitle,
        body: l.notificationsAlertWeekly(
          _money(ref, spent),
          categoryId == null
              ? ''
              : (names['${l.localeName}|$categoryId'] ?? ''),
        ),
        redactedTitle: l.notificationsAlertWeeklyTitle,
        redactedBody: l.notificationsAlertWeeklyHidden,
      );
    },
  );
}, name: 'weeklySummaryAlertProvider');

/// How long between weekly summaries.
const Duration weeklySummaryInterval = Duration(days: 7);

/// Runs the weekly summary when [weeklySummaryInterval] has passed since the
/// last run (stored in settings), then stores the run time. A failure leaves
/// the stored time alone, so the next start or resume tries again.
final weeklySummaryRunProvider = Provider<Future<bool> Function()>((ref) {
  return () async {
    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      final now = ref.read(clockProvider)().toUtc();
      final last = await settings.get(Settings.notifWeeklyLastRun);
      if (last != null &&
          now.millisecondsSinceEpoch - last <
              weeklySummaryInterval.inMilliseconds) {
        return false;
      }
      final alert = await ref.read(weeklySummaryAlertProvider.future);
      final zone = ref.read(localZoneProvider);
      await alert.run(localToday(now.millisecondsSinceEpoch, zone));
      await settings.set(
        Settings.notifWeeklyLastRun,
        now.millisecondsSinceEpoch,
      );
      return true;
    } on Object {
      return false;
    }
  };
}, name: 'weeklySummaryRunProvider');

/// Called at start and on resume: the weekly summary when due, and the
/// duplicate check (catches what the headless engine stored meanwhile).
final alertsResumeProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(duplicateCheckProvider)();
    await ref.read(weeklySummaryRunProvider)();
  };
}, name: 'alertsResumeProvider');
