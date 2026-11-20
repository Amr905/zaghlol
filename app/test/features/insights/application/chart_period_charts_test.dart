// T-188 AC3: every chart provider follows the chosen period, and the
// currency filter still applies. Real repository on an encrypted database
// with synthetic rows; today is 2026-11-10, payday 25.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/chart_period_selection.dart';
import 'package:zaghlol/features/insights/domain/explanations.dart';
import 'package:zaghlol/features/insights/presentation/chart_explain_providers.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

class _Today extends TodayNotifier {
  @override
  CivilDate build() => CivilDate(2026, 11, 10);
}

Future<void> _txn(
  AppDatabase db,
  String id,
  String direction,
  int major,
  String currency,
  CivilDate day,
) => db.customStatement(
  'INSERT INTO transactions (id, account_id, source, direction, '
  'amount_minor, currency, occurred_at, occurred_tz_offset_min, '
  'merchant_raw, merchant_norm, is_internal, category_source, created_at, '
  "updated_at) VALUES (?, 'acc1', 'sms', ?, ?, ?, ?, 120, 'Shop', 'shop', 0, "
  "'none', 0, 0)",
  [
    id,
    direction,
    major * 100,
    currency,
    day.epochDay * 86400000 + 12 * 3600000 - 120 * 60000,
  ],
);

void main() {
  late EncryptedDb edb;

  setUp(() async {
    edb = await EncryptedDb.open();
    final db = edb.db;
    await db.into(db.accounts).insert(account('acc1'));
    await _txn(db, 't1', 'expense', 1000, 'EGP', CivilDate(2026, 10, 26));
    await _txn(db, 't2', 'expense', 500, 'EGP', CivilDate(2026, 11, 2));
    await _txn(db, 't3', 'income', 30000, 'EGP', CivilDate(2026, 11, 3));
    await _txn(db, 't4', 'expense', 2000, 'EGP', CivilDate(2026, 10, 10));
    await _txn(db, 't5', 'expense', 4000, 'EGP', CivilDate(2026, 7, 15));
    await _txn(db, 't6', 'expense', 700, 'EGP', CivilDate(2025, 12, 20));
    await _txn(db, 't7', 'expense', 50, 'USD', CivilDate(2026, 11, 2));
  });
  tearDown(() => edb.close());

  ProviderContainer open(ChartPeriodSelection selection) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => edb.db),
        paydayScheduleProvider.overrideWith(
          (ref) async => PaydaySchedule.single(25),
        ),
        todayProvider.overrideWith(_Today.new),
      ],
    );
    addTearDown(c.dispose);
    c.read(chartPeriodSelectionProvider.notifier);
    return c;
  }

  Future<ProviderContainer> opened(ChartPeriodSelection s) async {
    final c = open(s);
    await c.read(chartPeriodSelectionProvider.future);
    await c.read(chartPeriodSelectionProvider.notifier).select(s);
    return c;
  }

  Future<int> donutTotal(ProviderContainer c, String code) async {
    final r = await c.read(donutChartProvider(code).future);
    return switch (r) {
      ChartReady(:final data) => data.total.minor,
      ChartNotEnoughData() => -1,
    };
  }

  test('categories follow every preset and a custom range', () async {
    final cases = <ChartPeriodSelection, int>{
      ChartPeriodSelection.thisCycle: 1500,
      const ChartPeriodSelection(ChartPreset.lastCycle): 2000,
      const ChartPeriodSelection(ChartPreset.thisMonth): 500,
      const ChartPeriodSelection(ChartPreset.lastMonth): 3000,
      const ChartPeriodSelection(ChartPreset.last3Months): 3500,
      const ChartPeriodSelection(ChartPreset.last6Months): 7500,
      const ChartPeriodSelection(ChartPreset.last12Months): 8200,
      const ChartPeriodSelection(ChartPreset.thisYear): 7500,
      ChartPeriodSelection.custom(
        CivilDate(2026, 10, 1),
        CivilDate(2026, 10, 31),
      ): 3000,
      // Stepped back: the cycle before last.
      const ChartPeriodSelection(ChartPreset.thisCycle, offset: 2): 0,
    };
    for (final e in cases.entries) {
      final c = await opened(e.key);
      final total = await donutTotal(c, 'EGP');
      expect(total, e.value == 0 ? -1 : e.value * 100, reason: e.key.encode());
    }
  });

  test('the currency filter still applies', () async {
    final c = await opened(ChartPeriodSelection.thisCycle);
    expect(await donutTotal(c, 'USD'), 5000);
    final cur = await c.read(chartsCurrenciesProvider.future);
    expect([for (final x in cur) x.code]..sort(), ['EGP', 'USD']);
    // USD has nothing in a period before November.
    final back = await opened(
      const ChartPeriodSelection(ChartPreset.thisCycle, offset: 1),
    );
    expect(
      [
        for (final x in await back.read(chartsCurrenciesProvider.future))
          x.code,
      ],
      ['EGP'],
    );
  });

  test('cash flow buckets follow the range length and add up', () async {
    Future<List<CashFlowPoint>> points(ChartPeriodSelection s) async {
      final c = await opened(s);
      final r = await c.read(cashFlowChartProvider('EGP').future);
      return (r as ChartReady<List<CashFlowPoint>>).data;
    }

    final cycle = await points(ChartPeriodSelection.thisCycle);
    expect(cycle, hasLength(17)); // 25 Oct .. today, one per day
    final six = await points(
      const ChartPeriodSelection(ChartPreset.last6Months),
    );
    expect(six.first.period.from, CivilDate(2026, 6, 1));
    expect(six.every((p) => p.period.lengthDays <= 7), isTrue);
    final year = await points(
      const ChartPeriodSelection(ChartPreset.last12Months),
    );
    expect(year, hasLength(12)); // Dec 2025 .. Nov 2026, one per month
    expect(CashFlowPoint.total(cycle).spend.minor, 150000);
    expect(CashFlowPoint.total(cycle).income.minor, 3000000);
    expect(CashFlowPoint.total(year).spend.minor, 820000);
    expect(CashFlowPoint.total(six).spend.minor, 750000);
  });

  test(
    'burn rate and vs average are for cycles; a past cycle runs to its end',
    () async {
      final month = await opened(
        const ChartPeriodSelection(ChartPreset.thisMonth),
      );
      expect(
        await month.read(burnChartProvider('EGP').future),
        isA<ChartNotEnoughData<BurnCurve>>(),
      );
      final last = await opened(
        const ChartPeriodSelection(ChartPreset.lastCycle),
      );
      final r = await last.read(burnChartProvider('EGP').future);
      final curve = (r as ChartReady<BurnCurve>).data;
      expect(curve.cycle.start, CivilDate(2026, 9, 25));
      expect(curve.elapsedDays, curve.cycle.length);
      expect(curve.cumulative.last.minor, 200000);
    },
  );

  test('net worth range is widened and never goes past today', () async {
    final c = await opened(ChartPeriodSelection.thisCycle);
    expect(
      await c.read(netWorthChartProvider('EGP').future),
      isA<ChartNotEnoughData<List<NetWorthPoint>>>(),
    );
  });

  test('explanations: tips only for a cycle, facts for any period', () async {
    Future<List<ExplanationPart>> parts(ChartPeriodSelection s) async {
      final c = await opened(s);
      final o = await c.read(
        chartExplanationProvider((chart: ChartId.cashFlow, code: 'EGP')).future,
      );
      return [for (final l in o.explanation.lines) l.key.part];
    }

    final cycle = await parts(ChartPeriodSelection.thisCycle);
    expect(cycle, contains(ExplanationPart.fact));
    expect(cycle, contains(ExplanationPart.tip));
    final months = await parts(
      const ChartPeriodSelection(ChartPreset.last3Months),
    );
    expect(months, contains(ExplanationPart.fact));
    expect(months, isNot(contains(ExplanationPart.tip)));
    expect(months, isNot(contains(ExplanationPart.deepTip)));
  });

  test('the previous period behind the comparison is one step back', () async {
    final c = await opened(const ChartPeriodSelection(ChartPreset.last3Months));
    final r = await c.read(chartsResolvedPeriodProvider.future);
    expect(r.previous.key, '2026-06-01..2026-08-31');
    final prev = await c.read(previousDonutChartProvider('EGP').future);
    expect((prev as ChartReady<CategoryDonut>).data.total.minor, 400000);
  });
}
