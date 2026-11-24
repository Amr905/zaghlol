// T-237 E2E-05: payday 25, a monthly budget, SMS spending up to 80 % of it,
// the 80 % alert and the safe-to-spend figure (FR-BUD-01..04, BR-BUD-01..03).
//
// .github/scripts/e2e-device.sh sends the synthetic SMS through the emulator
// modem when this test prints `E2E_DEVICE SEND <phase>`: p1 = 310 + 290
// (60 % of 1,000), p2 = 200 (80 %). The script also checks `dumpsys
// notification` for the budget channel before p2 (none) and after (posted).
// The expected numbers come from the spec, not from the app: cycle 25..24,
// safe per day = floor((budget - spend) / days left including today).
//
// Run: flutter test integration_test/e2e05_budget_device_test.dart
//      --flavor devSms -d <device> --no-uninstall

import 'dart:async';

import 'package:flutter/widgets.dart' show Text;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zaghlol/app/app_navigation.dart' show openBudget;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/money_format.dart';
import 'package:zaghlol/core/platform/notifications_api.g.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/budget/presentation/budget_edit_draft.dart';
import 'package:zaghlol/features/budget/presentation/budget_saver.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_format.dart'
    show trimZeroFraction;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'support/e2e_common.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final e = E2e('E2E05', binding);
  final egp = Currency.of('EGP');

  testWidgets('payday 25 budget, 80 % alert, safe to spend', (t) async {
    final semantics = t.ensureSemantics();
    try {
      // Quiet hours would delay the alert on a CI clock in the night.
      final c = await e.boot(
        t,
        seed: (s) async {
          await s.set(Settings.quietHoursEnabled, false);
        },
      );
      final db = await c.read(appDatabaseProvider.future);

      // ---- payday 25 and a 1,000 EGP overall monthly budget (the app's own
      // store and saver, as the editor uses them)
      final store = await c.read(paydayScheduleStoreProvider.future);
      await store.setPayday(25);
      final save = await c.read(budgetSaverProvider.future);
      await save(
        egp,
        BudgetValidated(
          total: Money(egp, 100000),
          limits: const {},
          thresholds: const [80, 100],
        ),
        false,
      );
      await e.settle(t, 1000);

      // ---- the cycle by the spec: 25th .. 24th around today
      final now = DateTime.now();
      final today = DateTime.utc(now.year, now.month, now.day);
      final start = now.day >= 25
          ? DateTime.utc(now.year, now.month, 25)
          : DateTime.utc(now.year, now.month - 1, 25);
      final end = DateTime.utc(start.year, start.month + 1, 24);
      String iso(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      final daysLeft = end.difference(today).inDays + 1;
      final schedule = await c.read(paydayScheduleProvider.future);
      final cycle = schedule.cycleOn(CivilDate(now.year, now.month, now.day));
      e.check(cycle.key == iso(start), 'cycle starts on the 25th');
      e.check(cycle.end.toIso() == iso(end), 'cycle ends on the 24th');
      e.say('CYCLE daysLeft=$daysLeft');

      Future<int> txns() async => e.count(
        db,
        'SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NULL',
      );
      Future<int> alerts() async =>
          e.count(db, 'SELECT COUNT(*) AS n FROM fired_alerts');
      Future<int> cycleSpend() async {
        final repo = await c.read(cycleRepositoryProvider.future);
        return (await repo.totals(cycle))[egp]?.spend.minor ?? 0;
      }

      // ---- 60 %: no alert yet
      e.send('p1');
      final got2 = await e.waitUntil(
        t,
        () async => await txns() >= 2,
        timeout: const Duration(seconds: 120),
      );
      e.check(got2, 'two SMS purchases saved');
      await e.settle(t, 8000);
      e.check(await cycleSpend() == 60000, 'cycle spend after p1 is 60 %');
      e.check(await alerts() == 0, 'no alert recorded at 60 %');
      e.say('P1_DONE');

      // ---- 80 %: the alert
      e.send('p2');
      final got3 = await e.waitUntil(
        t,
        () async => await txns() >= 3,
        timeout: const Duration(seconds: 120),
      );
      e.check(got3, 'third SMS purchase saved');
      final fired = await e.waitUntil(
        t,
        () async => await alerts() >= 1,
        timeout: const Duration(seconds: 60),
      );
      e.check(fired, 'an alert was recorded at 80 %');
      final th = await e.rows(db, 'SELECT threshold FROM fired_alerts');
      e.check(
        th.any((r) => r['threshold'] == 80) &&
            !th.any((r) => r['threshold'] == 100),
        'only the 80 threshold fired',
      );
      e.check(await cycleSpend() == 80000, 'cycle spend after p2 is 80 %');
      e.say('P2_DONE');
      e.send('alertcheck');
      await e.settle(t, 8000);
      // Diagnostics: the permission, and a control notification on the same
      // channel (static text), so the script can tell "alert not shown" from
      // "this emulator shows nothing".
      await e.settle(t, 8000);
      final api = NotificationsHostApi();
      e.say('NOTIF permission=${(await api.permissionStatus()).name}');
      e.say(
        'NOTIF fired_alerts rows later: '
        '${await e.count(db, 'SELECT COUNT(*) AS n FROM fired_alerts')}',
      );
      e.send('probe');
      await api.show(
        NotifMsg(
          id: 424242,
          channelId: 'zaghlol_alert_budget',
          title: 'e2e probe',
          body: 'e2e probe',
          publicTitle: 'e2e probe',
        ),
      );
      await e.settle(t, 5000);

      // ---- safe to spend by the spec, in the provider and on the screen
      final wantSafe = (100000 - 80000) ~/ daysLeft;
      c.invalidate(currentCycleOverviewProvider);
      final ov = await c.read(currentCycleOverviewProvider.future);
      e.check(
        ov.byCurrency[egp]?.safeToSpend?.minor == wantSafe,
        'safe per day provider equals floor(left / days) = $wantSafe',
      );
      e.check(ov.daysRemaining == daysLeft, 'days remaining incl. today');

      unawaited(openBudget(rootNavigatorKey.currentContext!));
      await e.settle(t, 2500);
      final l = AppLocalizations.of(rootNavigatorKey.currentContext!);
      final shownMoney = trimZeroFraction(
        MoneyFormat.format(
          Money(egp, wantSafe),
          languageCode: 'en',
          digits: DigitsMode.resolve(DigitsPref.auto, 'en'),
          hidden: false,
        ),
      );
      final want = cleanBidi(l.budgetOverviewSafePerDay(shownMoney));
      final safeText = find.byWidgetPredicate(
        (w) => w is Text && cleanBidi(w.data ?? '') == want,
      );
      await e.waitFor(
        t,
        safeText,
        timeout: const Duration(seconds: 20),
        what: 'the safe-per-day line on the Budget screen',
      );
      e.check(e.found(safeText), 'Budget screen shows the safe-per-day figure');
      await e.shot(t, 'e2e05-budget');

      e.say('RESULT problems=${e.problems.length}');
      expect(e.problems, isEmpty, reason: e.problems.join('; '));
    } finally {
      e.restoreErrors();
      semantics.dispose();
    }
  });
}
