// T-237 E2E-06: an own-account SMS transfer is paired (both legs internal,
// T-233 hook) and an incoming transfer is assigned as money back for an
// earlier expense through the UI; the totals follow BR-XFR-01/05 (FR-XFR-01,
// FR-XFR-06). .github/scripts/e2e-device.sh sends the synthetic SMS when the
// test prints `E2E_DEVICE SEND <phase>`:
//   x1 = purchase of 1,200 (the expense), x2 = own transfer 2,000 out of
//   one account and into another, x3 = 400 received from a person.
// Expected by the rules, not by the app: spend = 1,200 - 400 = 800; income =
// 0 (the 2,000 is internal, the 400 is money back); 1,200 + 2,000 are not
// double counted.
//
// Run: flutter test integration_test/e2e06_transfer_device_test.dart
//      --flavor devSms -d <device> --no-uninstall

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/settings/settings_keys.dart' show DigitsPref;
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/money_format.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/insights/application/chart_period_providers.dart';
import 'package:zaghlol/features/insights/data/chart_providers.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/chart_period_selection.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_format.dart'
    show trimZeroFraction;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'support/e2e_common.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final e = E2e('E2E06', binding);
  final egp = Currency.of('EGP');

  testWidgets('own transfer paired, reimbursement assigned', (t) async {
    final semantics = t.ensureSemantics();
    final c = await e.boot(t);
    final db = await c.read(appDatabaseProvider.future);
    final now = DateTime.now();

    Future<int> txns() async => e.count(
      db,
      'SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NULL',
    );
    Future<void> phase(String name, int total) async {
      e.send(name);
      final ok = await e.waitUntil(
        t,
        () async => await txns() >= total,
        timeout: const Duration(seconds: 120),
      );
      e.check(ok, 'phase $name saved (rows >= $total)');
      await e.settle(t, 5000);
    }

    // ---- the expense
    await phase('x1', 1);
    final expense = (await e.rows(
      db,
      'SELECT id, merchant_raw, merchant_norm FROM transactions '
      "WHERE amount_minor = 120000 AND direction = 'expense'",
    )).singleOrNull;
    e.check(expense != null, 'the 1,200 purchase is an expense');

    // ---- the own transfer: paired, both legs internal, same pair
    await phase('x2', 3);
    final legs = await e.rows(
      db,
      'SELECT id, direction, account_id, is_internal, transfer_pair_id '
      'FROM transactions WHERE amount_minor = 200000',
    );
    e.check(legs.length == 2, 'two 2,000 legs saved');
    e.check(
      legs.every((r) => r['is_internal'] == 1),
      'both transfer legs are internal',
    );
    e.check(
      legs.map((r) => r['account_id']).toSet().length == 2,
      'the legs are on two different accounts',
    );
    e.check(
      legs.map((r) => r['transfer_pair_id']).toSet().length == 1 &&
          legs.first['transfer_pair_id'] != null,
      'both legs share one pair',
    );
    e.check(
      await e.count(db, 'SELECT COUNT(*) AS n FROM transfer_pairs') == 1,
      'exactly one transfer pair row',
    );
    final cyc = await c.read(cycleRepositoryProvider.future);
    final schedule = await c.read(paydayScheduleProvider.future);
    final cycle = schedule.cycleOn(CivilDate(now.year, now.month, now.day));
    var tot = (await cyc.totals(cycle))[egp];
    e.check(
      tot?.spend.minor == 120000,
      'before money back: spend is 1,200 only',
    );
    e.check(tot?.income.minor == 0, 'the paired 2,000 is not income');

    // ---- the money back
    await phase('x3', 4);
    final inc = (await e.rows(
      db,
      'SELECT id FROM transactions WHERE amount_minor = 40000 '
      "AND direction = 'transfer_in'",
    )).singleOrNull;
    e.check(inc != null, 'the 400 incoming transfer saved');
    if (inc == null || expense == null) {
      expect(e.problems, isEmpty, reason: e.problems.join('; '));
      return;
    }
    e.check(
      await e.count(db, 'SELECT COUNT(*) AS n FROM offset_links') == 0,
      'no reimbursement before the assignment',
    );
    tot = (await cyc.totals(cycle))[egp];
    e.check(
      tot?.income.minor == 40000,
      'before assigning, 400 counts as income',
    );

    await e.go(t, AppRoutes.transactions);
    final incKey = find.byKey(ValueKey(inc['id']! as String));
    await e.waitFor(t, incKey, what: 'the 400 row in the list');
    await e.shot(t, 'e2e06-1-list');
    await t.tap(incKey);
    final moneyBack = find.text('This is money back for…');
    await e.waitFor(t, moneyBack, what: 'the money-back row on the detail');
    await t.ensureVisible(moneyBack);
    await e.settle(t, 300);
    await t.tap(moneyBack);
    final name =
        ((expense['merchant_norm'] ?? expense['merchant_raw']) as String? ?? '')
            .toLowerCase();
    final cand = find.byWidgetPredicate(
      (w) =>
          w is Text && name.isNotEmpty && (w.data ?? '').toLowerCase() == name,
    );
    await e.waitFor(t, cand, what: 'the 1,200 expense in the assign sheet');
    await e.shot(t, 'e2e06-2-assign');
    await t.tap(cand.first);
    await e.settle(t, 500);
    await t.tap(find.text('Save').last);
    await e.settle(t, 2500);
    final links = await e.rows(
      db,
      'SELECT kind, expense_txn_id, source_txn_id, amount_minor '
      'FROM offset_links',
    );
    e.check(links.length == 1, 'one reimbursement link saved');
    if (links.length == 1) {
      e.check(links.single['kind'] == 'reimbursement', 'link kind');
      e.check(links.single['amount_minor'] == 40000, 'link amount is 400');
      e.check(
        links.single['expense_txn_id'] == expense['id'],
        'on the expense',
      );
      e.check(links.single['source_txn_id'] == inc['id'], 'from the transfer');
    }

    // ---- totals: cycle query, chart query, Insights screen
    tot = (await cyc.totals(cycle))[egp];
    e.check(tot?.spend.minor == 80000, 'cycle spend is 1,200 - 400 = 800');
    e.check(tot?.income.minor == 0, 'cycle income is 0 (money back, internal)');

    final repo = await c.read(chartRepositoryProvider.future);
    repo.invalidate();
    final p = ChartPeriod.month(now.year, now.month);
    final cf = await repo.cashFlow([p], ChartFilter(currency: egp));
    if (cf is ChartReady<List<CashFlowPoint>>) {
      final sum = CashFlowPoint.total(cf.data);
      e.check(sum.spend.minor == 80000, 'chart spend is 800');
      e.check(sum.income.minor == 0, 'chart income is 0');
    } else {
      e.check(false, 'chart cash flow ready');
    }

    await c.read(chartPeriodSelectionProvider.future);
    await c
        .read(chartPeriodSelectionProvider.notifier)
        .select(const ChartPeriodSelection(ChartPreset.thisMonth));
    await e.go(t, AppRoutes.insights);
    await e.settle(t, 1500);
    final l = AppLocalizations.of(rootNavigatorKey.currentContext!);
    await t.tap(find.text(l.insightsV2TabOverview).first);
    await e.settle(t, 1500);
    final hero = find.byKey(const Key('hero-spent'));
    if (e.found(hero)) {
      final shown = cleanBidi((t.widget(hero) as Text).data ?? '');
      final want = cleanBidi(
        trimZeroFraction(
          MoneyFormat.format(
            Money(egp, 80000),
            languageCode: 'en',
            digits: DigitsMode.resolve(DigitsPref.auto, 'en'),
            hidden: false,
          ),
        ),
      );
      e.check(shown == want, 'Insights hero spend shows 800');
    } else {
      e.check(false, 'Insights hero found');
    }
    await e.shot(t, 'e2e06-3-insights');

    e.say('RESULT problems=${e.problems.length}');
    semantics.dispose();
    expect(e.problems, isEmpty, reason: e.problems.join('; '));
  });
}
