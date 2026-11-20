// FU-253: wiring of [Housekeeping] (housekeeping.dart): what follows every
// ingest batch (and a manual add) and what start / resume run. Best effort
// everywhere: a failure here never fails the ingest that triggered it.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart' hide Settings;
import '../../../core/db/app_database_providers.dart';
import '../../../core/l10n/locale_providers.dart' show digitsModeProvider;
import '../../../core/l10n/money_format.dart';
import '../../budget/application/budget_alert_runner.dart';
import '../../budget/application/budget_alert_service.dart';
import '../../budget/application/budget_providers.dart';
import '../../budget/application/cycle_app_wiring.dart'
    show domainEventBusProvider;
import '../../budget/data/payday_schedule_store.dart' show localToday;
import '../../capture/application/capture_providers.dart'
    show ingestionPauseGateProvider;
import '../../recurring/application/send_due_reminders.dart';
import '../../recurring/data/recurring_repository.dart';
import '../../transactions/application/dangling_links_sweep.dart';
import '../../transactions/application/refund_matching.dart';
import '../../transactions/application/transfer_pairing.dart';
import '../../transactions/data/transactions_providers.dart' show clockProvider;
import '../domain/notification_types.dart';
import 'housekeeping.dart';
import 'notification_providers.dart';
import '../../../core/settings/settings_providers.dart';

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
      final hidden = ref.read(hideAmountsProvider);
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
          await (await recurring()).detectAndSuggest(
            shouldStop: restoreWaiting,
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
                      hidden: ref.read(hideAmountsProvider),
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
                    hidden: ref.read(hideAmountsProvider),
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
