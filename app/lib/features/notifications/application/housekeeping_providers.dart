// FU-253: wiring of [Housekeeping] (housekeeping.dart): what follows every
// ingest batch (and a manual add) and what start / resume run. Best effort
// everywhere: a failure here never fails the ingest that triggered it.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart' hide Settings;
import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/fired_alerts_dao.dart';
import '../../../core/l10n/locale_providers.dart' show digitsModeProvider;
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../domain/quiet_hours.dart';
import '../../../core/l10n/money_format.dart';
import '../../budget/application/budget_alert_runner.dart';
import '../../budget/application/budget_alert_service.dart';
import '../../budget/application/budget_providers.dart';
import '../../budget/application/cycle_app_wiring.dart'
    show domainEventBusProvider;
import '../../budget/data/payday_schedule_store.dart' show localToday;
import '../../capture/application/capture_providers.dart'
    show ingestionPauseGateProvider;
import '../../recurring/application/notify_auto_added.dart';
import '../../salary/application/notify_salary_check.dart';
import '../../salary/application/salary_providers.dart';
import '../../recurring/application/send_due_reminders.dart';
import '../../recurring/data/recurring_repository.dart';
import '../../transactions/application/dangling_links_sweep.dart';
import '../../transactions/application/refund_matching.dart';
import '../../transactions/application/transfer_pairing.dart';
import '../../transactions/data/transactions_providers.dart' show clockProvider;
import '../domain/notification_types.dart';
import 'housekeeping.dart';
import 'notification_providers.dart';

/// The budget alert service with its l10n text. The category names are read
/// once per call (the text builder is synchronous).
Future<BudgetAlertService> _budgetAlertService(Ref ref, AppDatabase db) async {
  final service = await ref.read(notificationServiceProvider.future);
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
  return BudgetAlertService(
    notifications: service,
    nowMs: () => ref.read(clockProvider)().toUtc().millisecondsSinceEpoch,
    markFired:
        ({
          required kind,
          required subjectId,
          required periodKey,
          required threshold,
          required at,
        }) => service.markFired(
          kind: kind,
          subjectId: subjectId,
          periodKey: periodKey,
          threshold: threshold,
          at: at,
        ),
    text: (p, threshold) {
      final l = notificationL10n(ref);
      final lang = l.localeName;
      final digits = ref.read(digitsModeProvider(lang));
      final hidden = notificationHidden(ref);
      String money(Money m) => MoneyFormat.format(
        m,
        languageCode: lang,
        digits: digits,
        hidden: hidden,
      );
      final id = p.spec.categoryId;
      final category = id == null
          ? l.budgetEditOverall
          : (names['$lang|$id'] ?? l.budgetEditOverall);
      if (threshold >= 100) {
        return (
          title: l.notificationsAlertBudgetReachedTitle,
          body: l.notificationsAlertBudgetReached(
            category,
            money(p.spent),
            money(p.effectiveLimit),
          ),
          redactedTitle: l.notificationsAlertBudgetReachedTitle,
          redactedBody: l.notificationsAlertBudgetReachedHidden(category),
        );
      }
      return (
        title: l.notificationsAlertBudgetNearTitle,
        body: l.notificationsAlertBudgetNear(
          digits.render('$threshold%'),
          category,
          money(p.remaining),
        ),
        redactedTitle: l.notificationsAlertBudgetNearTitle,
        redactedBody: l.notificationsAlertBudgetNearHidden(category),
      );
    },
  );
}

/// The job list, in order. Public so a test can run it against a container.
final housekeepingProvider = Provider<Housekeeping>((ref) {
  Future<AppDatabase> db() => ref.read(appDatabaseProvider.future);
  Future<RecurringRepository> recurring() =>
      ref.read(recurringRepositoryProvider.future);
  // `read`, not `watch`: a gate change must not build a second runner (it
  // would lose the single-flight and throttle state).
  final gate = ref.read(ingestionPauseGateProvider);
  bool restoreWaiting() => gate.paused;
  final hk = Housekeeping(
    gate: gate,
    nowMs: () => ref.read(clockProvider)().toUtc().millisecondsSinceEpoch,
    steps: [
      (
        name: 'sweep_links',
        run: () async {
          final d = await db();
          final bus = ref.read(domainEventBusProvider);
          Future<PaydaySchedule> schedule() =>
              ref.read(paydayScheduleProvider.future);
          final pairing = TransferPairingUseCase(
            d,
            loadSchedule: schedule,
            events: bus,
          );
          final refunds = RefundMatching(
            d,
            loadSchedule: schedule,
            events: bus,
          );
          await sweepDanglingLinks(
            d,
            shouldStop: restoreWaiting,
            onPairRemoved: (id) async {
              await pairing.onRemoved(id);
            },
            onOffsetRemoved: (id) async {
              await refunds.onRemoved(id);
            },
          );
        },
      ),
      (
        name: 'recurring_detect',
        run: () async {
          // D-72: chains every 1, 3, 6 or 12 months are added as bills; one
          // notice per run says so.
          final added = await (await recurring()).detectAndAutoAdd(
            shouldStop: restoreWaiting,
          );
          if (added.isEmpty || restoreWaiting()) return;
          final now = ref.read(clockProvider)().toUtc().millisecondsSinceEpoch;
          final today = localToday(now, ref.read(localZoneProvider));
          final l = notificationL10n(ref);
          final digits = ref.read(digitsModeProvider(l.localeName));
          await notifyAutoAdded(
            added: added,
            notifications: await ref.read(notificationServiceProvider.future),
            periodKey: today.toIso(),
            buildText: (items, base) => AlertRequest(
              type: base.type,
              subjectId: base.subjectId,
              periodKey: base.periodKey,
              title: l.notificationsAutoAddedTitle,
              body: items.length == 1
                  ? l.notificationsAutoAddedOne(items.single.name)
                  : l.notificationsAutoAddedMany(
                      items.length,
                      digits.render('${items.length}'),
                    ),
              redactedTitle: l.notificationsAutoAddedTitle,
              redactedBody: l.notificationsAutoAddedHidden,
              payload: base.payload,
            ),
          );
        },
      ),
      (
        name: 'salary_check',
        run: () async {
          // D-71: tie received salary credits to the expected one, then the
          // one nudge per payday.
          if (restoreWaiting()) return;
          final now = ref.read(clockProvider)().toUtc().millisecondsSinceEpoch;
          final today = localToday(now, ref.read(localZoneProvider));
          final l = notificationL10n(ref);
          await runSalaryCheck(
            matching: await ref.read(salaryMatchingProvider.future),
            service: await ref.read(salaryServiceProvider.future),
            notifications: await ref.read(notificationServiceProvider.future),
            today: today,
            shouldStop: restoreWaiting,
            buildText: (base) => AlertRequest(
              type: base.type,
              subjectId: base.subjectId,
              periodKey: base.periodKey,
              title: l.notificationsSalaryNudgeTitle,
              body: l.notificationsSalaryNudgeBody,
              redactedTitle: l.notificationsSalaryNudgeTitle,
              redactedBody: l.notificationsSalaryNudgeBody,
              payload: base.payload,
            ),
          );
        },
      ),
      (
        name: 'card_dues',
        run: () async {
          await (await recurring()).syncCardDues();
        },
      ),
      (
        name: 'auto_mark_paid',
        run: () async {
          await (await recurring()).autoMarkPaid();
        },
      ),
      (
        name: 'due_reminders',
        run: () async {
          final now = ref.read(clockProvider)().toUtc().millisecondsSinceEpoch;
          final today = localToday(now, ref.read(localZoneProvider));
          await sendDueReminders(
            repository: await recurring(),
            shouldStop: restoreWaiting,
            notifications: await ref.read(notificationServiceProvider.future),
            buildText: (r, base) {
              final days = r.dueDate.difference(today);
              final money = Money.tryFromStorage(
                r.item.amountMinor,
                r.item.currency,
              );
              if (money == null) throw StateError('ITEM_AMOUNT_INVALID');
              final l = notificationL10n(ref);
              final digits = ref.read(digitsModeProvider(l.localeName));
              if (r.overdueDays > 0) {
                return AlertRequest(
                  type: base.type,
                  subjectId: base.subjectId,
                  periodKey: base.periodKey,
                  threshold: base.threshold,
                  title: l.notificationsAlertOverdueTitle(r.item.name),
                  body: l.notificationsAlertOverdue(
                    r.overdueDays,
                    digits.render('${r.overdueDays}'),
                    MoneyFormat.format(
                      money,
                      languageCode: l.localeName,
                      digits: digits,
                      hidden: notificationHidden(ref),
                    ),
                  ),
                  redactedTitle: l.notificationsAlertOverdueTitle(r.item.name),
                  redactedBody: l.notificationsAlertOverdueHidden(
                    r.overdueDays,
                    digits.render('${r.overdueDays}'),
                  ),
                  payload: base.payload,
                  // The label carries no amount; the route pins the due date.
                  actionTitle: l.notificationsAlertOverdueActionPaid,
                  actionRoute:
                      '/recurring/${base.subjectId}/paid/${base.periodKey}',
                );
              }
              return AlertRequest(
                type: base.type,
                subjectId: base.subjectId,
                periodKey: base.periodKey,
                title: l.notificationsAlertDueTitle,
                body: l.notificationsAlertDue(
                  days,
                  r.item.name,
                  MoneyFormat.format(
                    money,
                    languageCode: l.localeName,
                    digits: digits,
                    hidden: notificationHidden(ref),
                  ),
                  digits.render('$days'),
                ),
                redactedTitle: l.notificationsAlertDueTitle,
                redactedBody: l.notificationsAlertDueHidden,
                payload: base.payload,
              );
            },
          );
        },
      ),
      (
        name: 'budget_alerts',
        run: () async {
          final d = await db();
          final cycles = await ref.read(cycleRepositoryProvider.future);
          final schedule = await ref.read(paydayScheduleProvider.future);
          await runBudgetAlerts(
            db: d,
            cycles: cycles,
            cycle: schedule.cycleOn(cycles.today),
            schedule: schedule,
            service: await _budgetAlertService(ref, d),
            shouldStop: restoreWaiting,
          );
        },
      ),
    ],
  );
  ref.onDispose(hk.dispose);
  return hk;
}, name: 'housekeepingProvider');

/// After an ingest batch or a manual add: the duplicate check, then the
/// follow-up jobs (throttled). Never throws.
final afterIngestProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(duplicateCheckProvider)();
    try {
      await ref.read(housekeepingProvider).run();
    } on Object {
      // Best effort; the next batch, start or resume runs them again.
    }
  };
}, name: 'afterIngestProvider');

/// Start and resume (the "daily" trigger): alerts as before, then the
/// follow-up jobs. Cold start forces the run; a resume is throttled (OS
/// dialogs, the share sheet and biometric prompts all resume the app) and
/// gets no trailing run.
const resumeJobsInterval = Duration(minutes: 5);

final resumeJobsProvider = Provider<Future<void> Function({bool coldStart})>((
  ref,
) {
  return ({bool coldStart = false}) async {
    if (coldStart) {
      // FU-267: alerts the platform still holds from before this start get
      // the text of the current "hide amounts" setting; the jobs below
      // schedule them again.
      try {
        await ref.read(rederivePendingAlertsProvider)();
      } on Object {
        // Best effort.
      }
    }
    await ref.read(alertsResumeProvider)();
    try {
      await ref
          .read(housekeepingProvider)
          .run(force: coldStart, interval: resumeJobsInterval, trailing: false);
    } on Object {
      // Best effort.
    }
  };
}, name: 'resumeJobsProvider');

/// How far back an alert can still be waiting: quiet hours delay by less
/// than a day.
const pendingAlertLookback = Duration(hours: 24);

/// FU-267: scheduled alerts are kept in memory only, so after a restart (or a
/// change of "hide amounts") the platform may hold text with or without
/// amounts that no longer matches the setting. This cancels what is
/// scheduled, releases the dedupe claim of every alert that quiet hours were
/// still holding (fired within [pendingAlertLookback] and its quiet end is in
/// the future) and, with [rerun], runs the sources again (bills due, budget
/// alerts, duplicate check, weekly summary), which schedule them again with
/// text for the current setting.
///
/// When amounts are shown it does nothing unless something was waiting.
/// Returns the number of alerts released. Never logs.
final rederivePendingAlertsProvider =
    Provider<Future<int> Function({bool rerun})>((ref) {
      return ({bool rerun = false}) async {
        final settings = await ref.read(settingsRepositoryProvider.future);
        final hidden =
            await settings.get(Settings.hideAmountsNotifications) ||
            await settings.get(Settings.hideAmountsApp);
        final db = await ref.read(appDatabaseProvider.future);
        final dao = FiredAlertsDao(db);
        final now = ref.read(clockProvider)().toUtc();
        final quiet = QuietHours(
          enabled: await settings.get(Settings.quietHoursEnabled),
          startMin: await settings.get(Settings.quietHoursStartMin),
          endMin: await settings.get(Settings.quietHoursEndMin),
        );
        final recent = await dao.firedSince(
          now.subtract(pendingAlertLookback).millisecondsSinceEpoch,
        );
        final pending = [
          for (final r in recent)
            if (quiet
                .nextAllowed(
                  DateTime.fromMillisecondsSinceEpoch(
                    r.firedAt,
                    isUtc: true,
                  ).toLocal(),
                )
                .isAfter(now.toLocal()))
              r,
        ];
        if (!hidden && pending.isEmpty) return 0;
        await ref.read(notificationGatewayProvider).cancelScheduled();
        for (final r in pending) {
          await dao.unmarkFired(
            kind: r.kind,
            subjectId: r.subjectId,
            periodKey: r.periodKey,
            threshold: r.threshold,
          );
        }
        if (pending.any((r) => r.kind == NotificationType.weeklySummary.kind)) {
          await settings.reset(Settings.notifWeeklyLastRun);
        }
        if (rerun && (pending.isNotEmpty || hidden)) {
          await ref.read(alertsResumeProvider)();
          await ref.read(housekeepingProvider).run(force: true);
        }
        return pending.length;
      };
    }, name: 'rederivePendingAlertsProvider');

/// FU-267: when "hide amounts" is switched (the eye toggle or the
/// notifications switch), waiting alerts are re-derived at once. Watched by
/// the app root.
final pendingAlertsWatcherProvider = Provider<void>((ref) {
  void onSwitch(AsyncValue<bool>? prev, AsyncValue<bool> next) {
    final before = prev?.value;
    if (before == null || before == next.value) return;
    unawaited(
      ref
          .read(rederivePendingAlertsProvider)(rerun: true)
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

  ref.listen(hideAmountsNotificationsProvider, onSwitch);
  ref.listen(hideAmountsAppProvider, onSwitch);
}, name: 'pendingAlertsWatcherProvider');
