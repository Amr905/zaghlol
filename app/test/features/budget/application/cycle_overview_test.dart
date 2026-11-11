// T-051: the Home-facing overview, "today" handling and the determinism
// grep. Synthetic data only.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/budget/application/cycle_overview.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart'
    show clockProvider;
import 'package:zaghlol_domain/zaghlol_domain.dart';

final Currency egp = Currency.of('EGP');
final Currency usd = Currency.of('USD');

CivilDate day(int y, int m, int d) => CivilDate(y, m, d);

CycleTotals totals(Currency c, {int income = 0, int spend = 0}) => CycleTotals(
  currency: c,
  income: Money(c, income),
  spend: Money(c, spend),
  pendingSpend: Money.zero(c),
  byCategoryMinor: const {},
);

void main() {
  final cycle = Cycle(start: day(2026, 11, 1), end: day(2026, 11, 30));

  group('buildCycleOverview', () {
    test('spec example: 2,200 left on day 24 gives 314 whole pounds', () {
      final o = buildCycleOverview(
        cycle: cycle,
        today: day(2026, 11, 24),
        totals: {egp: totals(egp, spend: 280000)},
        budgets: {egp: Money(egp, 500000)},
      );
      expect(o.daysRemaining, 7);
      final e = o.byCurrency[egp]!;
      expect(e.safeToSpend!.minor, 31428);
      expect(e.safeToSpend!.minor ~/ 100, 314);
    });

    test(
      'no budget: safe to spend null; income target is not a basis (Q4)',
      () {
        final o = buildCycleOverview(
          cycle: cycle,
          today: day(2026, 11, 10),
          totals: {egp: totals(egp, income: 900000, spend: 10)},
          budgets: const {},
          incomeTarget: Money(egp, 1000000),
        );
        expect(o.byCurrency[egp]!.safeToSpend, isNull);
        expect(o.byCurrency[egp]!.underIdealLine, isNull);
        expect(o.incomeTarget!.minor, 1000000);
      },
    );

    test('a budgeted currency without activity has zero totals', () {
      final o = buildCycleOverview(
        cycle: cycle,
        today: day(2026, 11, 10),
        totals: {egp: totals(egp, spend: 5)},
        budgets: {usd: Money(usd, 3000)},
      );
      expect(o.byCurrency[usd]!.totals.spend.minor, 0);
      expect(o.byCurrency[usd]!.safeToSpend!.minor, 3000 ~/ 21);
      expect(o.byCurrency[egp]!.totals.spend.minor, 5);
    });

    test('overspent: 0 not null; each currency independent', () {
      final o = buildCycleOverview(
        cycle: cycle,
        today: day(2026, 11, 10),
        totals: {egp: totals(egp, spend: 900), usd: totals(usd, spend: 1)},
        budgets: {egp: Money(egp, 100), usd: Money(usd, 1000)},
      );
      expect(o.byCurrency[egp]!.safeToSpend!.minor, 0);
      expect(o.byCurrency[egp]!.underIdealLine, isFalse);
      expect(o.byCurrency[usd]!.safeToSpend!.minor, 999 ~/ 21);
      expect(o.byCurrency[usd]!.underIdealLine, isTrue);
    });
  });

  group('millisUntilNextLocalMidnight', () {
    int utc(int y, int m, int d, int h, [int mi = 0]) =>
        DateTime.utc(y, m, d, h, mi).millisecondsSinceEpoch;

    test('to the next local midnight, minimum one second', () {
      expect(
        millisUntilNextLocalMidnight(utc(2026, 11, 10, 20, 30), 120),
        90 * 60000,
        reason: '22:30 local, 1.5 h to midnight',
      );
      expect(
        millisUntilNextLocalMidnight(utc(2026, 11, 10, 21, 59), 120),
        60000,
      );
      expect(
        millisUntilNextLocalMidnight(utc(2026, 11, 10, 21, 59) + 59500, 120),
        1000,
        reason: 'at least one second',
      );
      expect(
        millisUntilNextLocalMidnight(utc(2026, 11, 10, 22), 120),
        24 * 3600000,
        reason: 'exactly midnight: the next one',
      );
    });
  });

  group('todayProvider', () {
    test('rebuilds only when the date changes; re-arms', () async {
      var nowMs = DateTime.utc(2026, 11, 10, 20).millisecondsSinceEpoch;
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(
            () => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
          ),
          localZoneProvider.overrideWithValue(const FixedLocalZone(120)),
        ],
      );
      addTearDown(container.dispose);
      final seen = <CivilDate>[];
      container.listen(todayProvider, (_, n) => seen.add(n));
      expect(container.read(todayProvider), day(2026, 11, 10));
      final n = container.read(todayProvider.notifier);
      n.reevaluate();
      expect(seen, isEmpty, reason: 'same date: no rebuild');
      nowMs = DateTime.utc(2026, 11, 10, 22, 1).millisecondsSinceEpoch;
      n.reevaluate();
      expect(seen, [day(2026, 11, 11)]);
    });
  });

  test('no DateTime.now in the budget engine or feature (design note §7)', () {
    final roots = [
      '../packages/zaghlol_domain/lib/budget',
      'lib/features/budget',
    ];
    final bad = RegExp(r'DateTime\.now|DateTime\(|TimeOfDay\.now|Stopwatch');
    var files = 0;
    for (final r in roots) {
      for (final f in Directory(r).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        files++;
        final text = f.readAsStringSync();
        expect(bad.hasMatch(text), isFalse, reason: f.path);
        expect(text.contains('toLocal()'), isFalse, reason: f.path);
      }
    }
    expect(files, greaterThan(8));
  });
}
