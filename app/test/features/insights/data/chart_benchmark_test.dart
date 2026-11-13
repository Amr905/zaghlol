// T-105 AC1: every chart query < 100 ms with 2 years of data. 10,000
// transactions (about 14 a day), 3 accounts, 2 currencies, 60 merchants,
// 12 categories, 500 refund/reimbursement links, 30 recurring items and 24
// snapshots, on an encrypted database in drift's background isolate (the
// app's executor). Tagged `benchmark`: excluded from app-ci's non-benchmark
// run. Each chart runs cold (memo cleared) 7 times after a warm-up; the
// gate is the 6th fastest (about p85), which ignores one stray GC pause but
// not a slow query. Synthetic data; the output carries numbers only.
@Tags(['benchmark'])
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/features/insights/data/chart_repository.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

const int _budgetMs = 100;

void main() {
  test('AC1: each chart < 100 ms on 10k transactions (2 years)', () async {
    final edb = await EncryptedDb.open();
    addTearDown(edb.close);
    final db = edb.db;
    for (final (id, kind) in [
      ('acc1', 'debit'),
      ('acc2', 'credit'),
      ('acc3', 'wallet'),
    ]) {
      await db
          .into(db.accounts)
          .insert(
            account(id, kind: kind, last4: '${1000 + id.hashCode % 8000}'),
          );
    }
    const buckets = ['needs', 'wants', 'obligations', 'savings', 'giving'];
    for (var i = 0; i < 12; i++) {
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'cat$i',
              nameAr: 'c$i',
              nameEn: 'c$i',
              icon: 'x',
              color: '#000000',
              bucket: buckets[i % buckets.length],
              sort: i,
              isCustom: const Value(1),
            ),
          );
    }
    // 2025-01-01 .. 2026-12-31 (two years), deterministic pseudo-random.
    final start = DateTime.utc(2025, 1, 1).millisecondsSinceEpoch;
    var seed = 12345;
    int next(int n) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed % n;
    }

    await db.transaction(() async {
      for (var chunk = 0; chunk < 10; chunk++) {
        await db.batch((b) {
          for (var i = chunk * 1000; i < (chunk + 1) * 1000; i++) {
            final dir = i % 10 == 0 ? 'income' : 'expense';
            final cur = i % 7 == 0 ? 'USD' : 'EGP';
            b.customStatement(
              'INSERT INTO transactions (id, account_id, source, direction, '
              'amount_minor, currency, occurred_at, occurred_tz_offset_min, '
              'merchant_raw, merchant_norm, category_id, is_internal, '
              'category_source, created_at, updated_at) '
              "VALUES (?, ?, 'sms', ?, ?, ?, ?, 120, ?, ?, ?, ?, 'none', 0, 0)",
              [
                't$i',
                'acc${1 + next(3)}',
                dir,
                1000 + next(500000),
                cur,
                start + next(730) * 86400000 + next(86400000),
                'Shop ${next(60)}',
                'shop ${next(60)}',
                'cat${next(12)}',
                i % 25 == 0 ? 1 : 0,
              ],
            );
          }
        });
      }
      // Links: refunds of an expense by a same-currency income row.
      await db.customStatement(
        'INSERT INTO offset_links (id, kind, expense_txn_id, source_txn_id, '
        'amount_minor, created_at) '
        "SELECT 'l' || e.id, 'refund', e.id, s.id, 100, 0 "
        'FROM transactions e JOIN transactions s ON s.currency = e.currency '
        "AND s.direction = 'income' AND s.amount_minor >= 100 "
        "WHERE e.direction = 'expense' AND e.amount_minor >= 100 "
        'GROUP BY e.id LIMIT 500',
      );
      for (var i = 0; i < 30; i++) {
        await db
            .into(db.recurringItems)
            .insert(
              RecurringItemsCompanion.insert(
                id: 'r$i',
                kind: i.isEven ? 'subscription' : 'installment',
                status: 'active',
                name: 'Item $i',
                amountMinor: 5000 + i,
                currency: 'EGP',
                cadence: 'monthly',
                nextDueDate: const Value('2026-11-28'),
                totalCount: Value(i.isEven ? null : 12),
                createdAt: 0,
              ),
            );
      }
      for (var m = 0; m < 24; m++) {
        await db.customStatement(
          'INSERT INTO networth_snapshots VALUES (?, ?, ?, ?)',
          [
            '${2025 + m ~/ 12}-${(m % 12 + 1).toString().padLeft(2, '0')}-24',
            'EGP',
            100000 + m,
            1000,
          ],
        );
      }
    });

    final links = await db
        .customSelect('SELECT count(*) AS c FROM offset_links')
        .getSingle();
    expect(links.read<int>('c'), greaterThan(100));
    final repo = ChartRepository(db);
    final schedule = PaydaySchedule.single(25);
    final today = CivilDate(2026, 11, 10);
    final cycle = schedule.cycleOn(today);
    final period = ChartPeriod.cycle(cycle);
    final year = ChartPeriod(CivilDate(2026, 1, 1), CivilDate(2026, 12, 31));
    final f = ChartFilter(currency: Currency.of('EGP'));
    final priors = [
      for (var k = 1; k <= 3; k++)
        ChartPeriod.cycle(schedule.cycleOn(today.plusDays(-31 * k))),
    ];
    final twelve = [
      for (var k = 11; k >= 0; k--)
        ChartPeriod.cycle(schedule.cycleOn(today.plusDays(-30 * k))),
    ];

    final charts = <String, Future<Object?> Function()>{
      'cashFlow (12 cycles)': () => repo.cashFlow(twelve, f),
      'categoryDonut (cycle)': () => repo.categoryDonut(period, f),
      'categoryDonut (year)': () => repo.categoryDonut(year, f),
      'burnCurve': () => repo.burnCurve(cycle, today, f),
      'fiftyThirtyTwenty': () => repo.fiftyThirtyTwenty(period, f),
      'dayHourPattern (year)': () => repo.dayHourPattern(year, f),
      'topMerchants (year)': () => repo.topMerchants(year, f),
      'monthVsAverage': () => repo.monthVsAverage(period, priors, today, f),
      'installmentTimeline': () => repo.installmentTimeline(today, f),
      'subscriptionsAnnual': () => repo.subscriptionsAnnual(f),
      'cardsSplit (year)': () => repo.cardsSplit(year, f),
      'netWorth': () => repo.netWorth(
        ChartPeriod(CivilDate(2025, 1, 1), CivilDate(2026, 12, 31)),
        'EGP',
      ),
      'personalInflation': () => repo.personalInflationIndex(today, f),
    };

    final slow = <String>[];
    for (final e in charts.entries) {
      repo.invalidate();
      await e.value(); // warm-up (statement cache, page cache)
      final times = <int>[];
      for (var i = 0; i < 7; i++) {
        repo.invalidate();
        final sw = Stopwatch()..start();
        await e.value();
        times.add(sw.elapsedMilliseconds);
      }
      times.sort();
      // ignore: avoid_print
      print(
        'BENCH ${e.key}: median ${times[3]} ms, p85 ${times[5]} ms, max ${times.last} ms',
      );
      if (times[5] >= _budgetMs) slow.add(e.key);
    }
    expect(slow, isEmpty, reason: 'over $_budgetMs ms');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
