// T-105: the chart queries on an encrypted database. Synthetic data only.
// Local zone for every row is +02:00 (stored offset 120).

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/features/budget/data/cycle_repository.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/insights/data/chart_repository.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

final egp = Currency.of('EGP');
final gbp = Currency.of('GBP');

int at(int y, int m, int d, [int h = 10, int min = 0]) =>
    DateTime.utc(y, m, d, h, min).millisecondsSinceEpoch;

CivilDate day(int y, int m, int d) => CivilDate(y, m, d);

T ready<T>(ChartResult<T> r) {
  expect(r, isA<ChartReady<T>>());
  return (r as ChartReady<T>).data;
}

ChartNotEnoughData<T> notEnough<T>(ChartResult<T> r) {
  expect(r, isA<ChartNotEnoughData<T>>());
  return r as ChartNotEnoughData<T>;
}

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late ChartRepository repo;
  final schedule = PaydaySchedule.single(25);
  final cycle = schedule.cycleOn(day(2026, 11, 10)); // 25 Oct .. 24 Nov
  final period = ChartPeriod.cycle(cycle);
  final fEgp = ChartFilter(currency: egp);

  Future<void> add(
    String id, {
    int amount = 1000,
    String direction = 'expense',
    String status = 'posted',
    String currency = 'EGP',
    int? when,
    int offset = 120,
    bool internal = false,
    bool deleted = false,
    String account = 'acc1',
    String? category,
    String? merchant,
    String? merchantRaw,
  }) => db
      .into(db.transactions)
      .insert(
        txn(
          id,
          accountId: account,
          direction: direction,
          amountMinor: amount,
          currency: currency,
          occurredAt: when ?? at(2026, 11, 3),
          merchantNorm: merchant,
          merchant: merchantRaw ?? merchant,
        ).copyWith(
          status: Value(status),
          occurredTzOffsetMin: Value(offset),
          isInternal: Value(internal ? 1 : 0),
          deletedAt: Value(deleted ? t0 : null),
          categoryId: Value(category),
        ),
      );

  Future<void> category(String id, String bucket) => db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: id,
          nameAr: id,
          nameEn: id,
          icon: 'x',
          color: '#000000',
          bucket: bucket,
          sort: 0,
          isCustom: const Value(1),
        ),
      );

  Future<void> linkRow(String id, String expense, String source, int amt) => db
      .into(db.offsetLinks)
      .insert(link(id, expense: expense, source: source, amountMinor: amt));

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    await db.into(db.accounts).insert(account('acc1', kind: 'debit'));
    await db
        .into(db.accounts)
        .insert(account('acc2', kind: 'credit', last4: '5678'));
    await category('cn', 'needs');
    await category('cw', 'wants');
    await category('cs', 'savings');
    await category('cg', 'giving');
    repo = ChartRepository(db);
  });
  tearDown(() => edb.close());

  group('1 cash flow', () {
    test('income and spend per bucket; excluded rows never count', () async {
      await add('inc', amount: 50000, direction: 'income');
      await add('e1', amount: 1000);
      await add('e2', amount: 2000, direction: 'fee');
      await add('t-out', amount: 4000, direction: 'transfer_out'); // to others
      await add(
        'internal',
        amount: 9000,
        direction: 'transfer_out',
        internal: true,
      );
      await add(
        'internal-in',
        amount: 9000,
        direction: 'transfer_in',
        internal: true,
      );
      await add('declined', amount: 700, status: 'declined');
      await add('reversed', amount: 700, status: 'reversed');
      await add('gone', amount: 700, deleted: true);
      await add('gbp', amount: 123456, currency: 'GBP');
      final r = ready(await repo.cashFlow([period], fEgp));
      expect(r.single.income, Money(egp, 50000));
      expect(r.single.spend, Money(egp, 7000));
      expect(r.single.net, Money(egp, 43000));
      final g = ready(
        await repo.cashFlow([period], ChartFilter(currency: gbp)),
      );
      expect(g.single.spend, Money(gbp, 123456));
      expect(g.single.income.minor, 0);
    });

    test(
      'matches the cycle engine to the minor unit (refund, reimbursement)',
      () async {
        await add('inc', amount: 80000, direction: 'income');
        await add('e1', amount: 10000, category: 'cn');
        await add('e2', amount: 5000);
        await add('refund', amount: 3000, direction: 'refund');
        await add('friend', amount: 4000, direction: 'income');
        await add('p', amount: 700, status: 'pending');
        await linkRow('l1', 'e1', 'refund', 2000);
        await linkRow('l2', 'e2', 'friend', 4000);
        final engine = CycleRepository(
          db,
          nowUtcMs: () => at(2026, 11, 10),
          zone: const FixedLocalZone(120),
        );
        final totals = (await engine.totals(cycle))[egp]!;
        final r = ready(await repo.cashFlow([period], fEgp)).single;
        expect(r.spend, totals.spend);
        expect(r.income, totals.income);
        // 10000-2000 + 5000-4000 + 700 = 9700; income 80000 + (3000-2000) + 0.
        expect(r.spend.minor, 9700);
        expect(r.income.minor, 81000);
      },
    );

    test('a deleted refund stops reducing the expense', () async {
      await add('e1', amount: 10000);
      await add('refund', amount: 3000, direction: 'refund', deleted: true);
      await linkRow('l1', 'e1', 'refund', 3000);
      expect(
        ready(await repo.cashFlow([period], fEgp)).single.spend.minor,
        10000,
      );
    });

    test('local day boundary uses the row own offset', () async {
      // 22:30Z + 02:00 = 00:30 on 25 Nov: next cycle, not this one.
      await add('late', amount: 100, when: at(2026, 11, 24, 22, 30));
      // 21:30Z + 02:00 = 23:30 on 24 Nov: this cycle.
      await add('edge', amount: 200, when: at(2026, 11, 24, 21, 30));
      final next = ChartPeriod.cycle(schedule.cycleOn(day(2026, 11, 26)));
      final r = ready(await repo.cashFlow([period, next], fEgp));
      expect(r[0].spend.minor, 200);
      expect(r[1].spend.minor, 100);
      // Same instant, different stored offset: moves across the boundary.
      await add(
        'minus',
        amount: 50,
        when: at(2026, 11, 25, 1, 0),
        offset: -120,
      );
      repo.invalidate();
      final r2 = ready(await repo.cashFlow([period, next], fEgp));
      expect(r2[0].spend.minor, 250); // 23:00 on 24 Nov
    });

    test(
      'several buckets in one call; the first one is partial (EC-23)',
      () async {
        await add('old', amount: 100, when: at(2026, 10, 3));
        await add('now', amount: 300);
        final prev = ChartPeriod.cycle(schedule.cycleOn(day(2026, 10, 10)));
        final r = ready(await repo.cashFlow([prev, period], fEgp));
        expect(r[0].spend.minor, 100);
        expect(r[1].spend.minor, 300);
        expect(r[0].isPartial, isTrue); // data starts on 3 Oct, cycle on 25 Sep
        expect(r[1].isPartial, isFalse);
      },
    );

    test('no data: not enough data; empty bucket list is a bug', () async {
      expect(
        notEnough(await repo.cashFlow([period], fEgp)).reason,
        NotEnoughReason.noData,
      );
      expect(() => repo.cashFlow([], fEgp), throwsArgumentError);
    });

    test('account filter narrows; no filter is all', () async {
      await add('a', amount: 100, account: 'acc1');
      await add('b', amount: 200, account: 'acc2');
      final one = ChartFilter(currency: egp, accountIds: {'acc2'});
      expect(ready(await repo.cashFlow([period], one)).single.spend.minor, 200);
      expect(
        ready(await repo.cashFlow([period], fEgp)).single.spend.minor,
        300,
      );
    });
  });

  group('2 category donut', () {
    test(
      'net of links, shares add up to 10000, uncategorized is null',
      () async {
        await add('a', amount: 6000, category: 'cn');
        await add('b', amount: 3000, category: 'cw');
        await add('c', amount: 1000);
        await add('refund', amount: 1000, direction: 'refund');
        await linkRow('l', 'a', 'refund', 1000);
        await add('zero', amount: 500, category: 'cs');
        await add('zr', amount: 500, direction: 'refund');
        await linkRow('lz', 'zero', 'zr', 500); // net zero: not a slice
        final d = ready(await repo.categoryDonut(period, fEgp));
        expect(d.total.minor, 9000);
        expect([for (final s in d.slices) s.categoryId], ['cn', 'cw', null]);
        expect([for (final s in d.slices) s.amount.minor], [5000, 3000, 1000]);
        expect(d.slices.fold<int>(0, (a, s) => a + s.shareBp), 10000);
      },
    );

    test(
      'internal transfers and other currencies are not in the donut',
      () async {
        await add('x', amount: 100, category: 'cn');
        await add('in', amount: 9999, category: 'cn', internal: true);
        await add('g', amount: 9999, category: 'cn', currency: 'GBP');
        expect(ready(await repo.categoryDonut(period, fEgp)).total.minor, 100);
      },
    );

    test('empty period', () async {
      expect(
        notEnough(await repo.categoryDonut(period, fEgp)).reason,
        NotEnoughReason.noData,
      );
    });
  });

  group('3 burn curve', () {
    test('cumulative by day, even-pace line, projection', () async {
      await db
          .into(db.budgets)
          .insert(
            BudgetsCompanion.insert(
              id: 'b1',
              currency: 'EGP',
              limitMinor: 31000,
              period: 'cycle',
              createdAt: t0,
            ),
          );
      // Cycle starts 25 Oct; today 3 Nov = day 10.
      await add('d1', amount: 1000, when: at(2026, 10, 25));
      await add('d3', amount: 2000, when: at(2026, 10, 27));
      await add('d10', amount: 500, when: at(2026, 11, 3));
      await add('future', amount: 9999, when: at(2026, 11, 20));
      final b = ready(await repo.burnCurve(cycle, day(2026, 11, 3), fEgp));
      expect(b.elapsedDays, 10);
      expect(
        [for (final m in b.cumulative) m.minor],
        [1000, 1000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3500],
      );
      expect(b.budget, Money(egp, 31000));
      expect(b.idealAt(10)!.minor, 31000 * 10 ~/ 31);
      expect(
        b.projectedTotal!.minor,
        3500 * 31 ~/ 10 + (3500 * 31 % 10 >= 5 ? 1 : 0),
      );
    });

    test(
      'no projection before 3 days; none before the cycle; none empty',
      () async {
        await add('d1', amount: 1000, when: at(2026, 10, 25));
        final b = ready(await repo.burnCurve(cycle, day(2026, 10, 26), fEgp));
        expect(b.projectedTotal, isNull);
        expect(b.budget, isNull);
        expect(
          notEnough(await repo.burnCurve(cycle, day(2026, 10, 20), fEgp))
              .reason,
          NotEnoughReason.noData,
        );
        final empty = ChartFilter(currency: gbp);
        expect(
          notEnough(await repo.burnCurve(cycle, day(2026, 11, 3), empty))
              .reason,
          NotEnoughReason.noData,
        );
      },
    );

    test('a closed cycle is cut at its length; category budgets sum', () async {
      for (final (id, cat, lim) in [('b1', 'cn', 1000), ('b2', 'cw', 2000)]) {
        await db
            .into(db.budgets)
            .insert(
              BudgetsCompanion.insert(
                id: id,
                categoryId: Value(cat),
                currency: 'EGP',
                limitMinor: lim,
                period: 'cycle',
                createdAt: t0,
              ),
            );
      }
      await add('x', amount: 100);
      final b = ready(await repo.burnCurve(cycle, day(2027, 3, 1), fEgp));
      expect(b.elapsedDays, cycle.length);
      expect(b.budget!.minor, 3000);
      expect(b.cumulative.length, cycle.length);
    });

    test('a budget change shows at once (live read)', () async {
      await add('x', amount: 100);
      expect(
        ready(await repo.burnCurve(cycle, day(2026, 11, 3), fEgp)).budget,
        isNull,
      );
      await db
          .into(db.budgets)
          .insert(
            BudgetsCompanion.insert(
              id: 'b',
              currency: 'EGP',
              limitMinor: 500,
              period: 'cycle',
              createdAt: t0,
            ),
          );
      expect(
        ready(await repo.burnCurve(cycle, day(2026, 11, 3), fEgp))
            .budget!
            .minor,
        500,
      );
    });
  });

  group('4 50/30/20', () {
    test('buckets, unspent income counts as savings', () async {
      await add('inc', amount: 100000, direction: 'income');
      await add('n', amount: 40000, category: 'cn');
      await add('w', amount: 20000, category: 'cw');
      await add('s', amount: 5000, category: 'cs');
      await add('g', amount: 3000, category: 'cg');
      await add('u', amount: 2000);
      final r = ready(await repo.fiftyThirtyTwenty(period, fEgp));
      expect(r.needs.minor, 40000);
      expect(r.wants.minor, 20000);
      expect(r.other.minor, 5000);
      expect(r.savings.minor, 5000 + (100000 - 70000));
      expect(r.shareBp(r.needs), 4000);
      expect(r.shareBp(r.wants), 2000);
    });

    test(
      'overspending leaves no negative savings; no income says so',
      () async {
        await add('n', amount: 40000, category: 'cn');
        expect(
          notEnough(await repo.fiftyThirtyTwenty(period, fEgp)).reason,
          NotEnoughReason.noIncome,
        );
        await add('inc', amount: 10000, direction: 'income');
        repo.invalidate();
        expect(
          ready(await repo.fiftyThirtyTwenty(period, fEgp)).savings.minor,
          0,
        );
      },
    );

    test('a reimbursement that repays an expense is not income', () async {
      await add('n', amount: 10000, category: 'cn');
      await add('friend', amount: 10000, direction: 'income');
      await linkRow('l', 'n', 'friend', 10000);
      expect(
        notEnough(await repo.fiftyThirtyTwenty(period, fEgp)).reason,
        NotEnoughReason.noIncome,
      );
    });
  });

  group('5 day / hour pattern', () {
    test('weekday and local hour from the row offset', () async {
      // 9 Nov 2026 is a Monday. 10:00Z + 2 h = 12:00 local.
      for (var i = 0; i < 6; i++) {
        await add('m$i', amount: 100, when: at(2026, 11, 9));
      }
      // 22:30Z on Friday 13 Nov = 00:30 Saturday 14 Nov local.
      for (var i = 0; i < 5; i++) {
        await add('s$i', amount: 10, when: at(2026, 11, 13, 22, 30));
      }
      final p = ready(await repo.dayHourPattern(period, fEgp));
      expect(p.byWeekday.length, 7);
      expect(p.byHour.length, 24);
      expect(p.byWeekday[1]!.spend.minor, 600);
      expect(p.byWeekday[1]!.count, 6);
      expect(p.byWeekday[6]!.spend.minor, 50); // Saturday
      expect(p.byWeekday[5]!.count, 0); // Friday
      expect(p.byHour[12]!.spend.minor, 600);
      expect(p.byHour[0]!.spend.minor, 50);
    });

    test('fewer than 10 rows is not enough data', () async {
      for (var i = 0; i < 9; i++) {
        await add('r$i');
      }
      final n = notEnough(await repo.dayHourPattern(period, fEgp));
      expect(n.reason, NotEnoughReason.tooFewTransactions);
      expect(n.have, 9);
      expect(n.need, 10);
    });
  });

  group('6 top merchants', () {
    test(
      'ranked by net spend, limited, nameless and refunded excluded',
      () async {
        for (var i = 0; i < 7; i++) {
          await add('m$i', amount: 1000 * (i + 1), merchant: 'shop$i');
        }
        await add(
          'twice',
          amount: 500,
          merchant: 'shop0',
          merchantRaw: 'Shop 0',
        );
        await add('nameless', amount: 99999);
        await add('refunded', amount: 9999999, merchant: 'gone');
        await add('rf', amount: 9999999, direction: 'refund');
        await linkRow('l', 'refunded', 'rf', 9999999);
        final five = ready(await repo.topMerchants(period, fEgp, limit: 5));
        expect(
          [for (final m in five) m.merchantNorm],
          ['shop6', 'shop5', 'shop4', 'shop3', 'shop2'],
        );
        expect(five.first.amount.minor, 7000);
        final all = ready(await repo.topMerchants(period, fEgp, limit: 50));
        expect(all.length, 7);
        final shop0 = all.firstWhere((m) => m.merchantNorm == 'shop0');
        expect(shop0.amount.minor, 1500);
        expect(shop0.count, 2);
      },
    );

    test('limit is clamped; empty period', () async {
      await add('a', merchant: 'a');
      expect(ready(await repo.topMerchants(period, fEgp, limit: 0)).length, 1);
      expect(
        notEnough(await repo.topMerchants(period, ChartFilter(currency: gbp)))
            .reason,
        NotEnoughReason.noData,
      );
    });
  });

  group('7 month vs 3-cycle average', () {
    ChartPeriod c(int y, int m, int d) =>
        ChartPeriod.cycle(schedule.cycleOn(day(y, m, d)));
    final p1 = c(2026, 10, 10); // 25 Sep - 24 Oct
    final p2 = c(2026, 9, 10); // 25 Aug - 24 Sep
    final p3 = c(2026, 8, 10); // 25 Jul - 24 Aug

    test('same-day-aligned comparison with a per-category delta', () async {
      // Current cycle 25 Oct - 24 Nov; today 30 Oct = day 6.
      await add('c', amount: 3000, when: at(2026, 10, 26), category: 'cn');
      await add('c2', amount: 1000, when: at(2026, 10, 30), category: 'cw');
      // Earlier cycles, days 1-6 only: 1000 + 3000 + 2000 over 3 cycles.
      await add('a1', amount: 1000, when: at(2026, 9, 26), category: 'cn');
      await add('a2', amount: 9999, when: at(2026, 10, 15), category: 'cn');
      await add('b1', amount: 3000, when: at(2026, 8, 26), category: 'cn');
      await add('d1', amount: 2000, when: at(2026, 7, 25), category: 'cn');
      final cur = c(2026, 10, 26);
      final r = ready(
        await repo.monthVsAverage(cur, [p1, p2, p3], day(2026, 10, 30), fEgp),
      );
      expect(r.elapsedDays, 6);
      expect(r.cyclesCounted, 3);
      expect(r.current.minor, 4000);
      expect(r.average.minor, 2000);
      expect(r.deltaBp, 10000);
      expect(r.byCategory.first.categoryId, 'cn');
      expect(r.byCategory.first.current.minor, 3000);
      expect(r.byCategory.first.average.minor, 2000);
      expect(r.byCategory.first.deltaBp, 5000);
      expect(r.byCategory.last.categoryId, 'cw');
      expect(r.byCategory.last.deltaBp, isNull); // average zero
    });

    test(
      'needs 2 complete earlier cycles: the first cycle is partial (EC-23)',
      () async {
        await add('now', amount: 100, when: at(2026, 10, 27));
        await add('p1', amount: 100, when: at(2026, 9, 27)); // data from 27 Sep
        final cur = c(2026, 10, 26);
        final n = notEnough(
          await repo.monthVsAverage(cur, [p1, p2, p3], day(2026, 10, 30), fEgp),
        );
        // First data 27 Sep > 25 Sep (p1 start): p1 incomplete, none counted.
        expect(n.reason, NotEnoughReason.tooFewCycles);
        expect(n.have, 0);
        expect(n.need, 2);
      },
    );

    test(
      'exactly two complete cycles are enough; the third is optional',
      () async {
        await add('p3', amount: 100, when: at(2026, 8, 1)); // before p2 start
        await add('p2', amount: 300, when: at(2026, 9, 1));
        await add('p1', amount: 500, when: at(2026, 10, 1));
        await add('now', amount: 100, when: at(2026, 10, 27));
        final cur = c(2026, 10, 26);
        final r = ready(
          await repo.monthVsAverage(cur, [p1, p2], day(2026, 10, 30), fEgp),
        );
        expect(r.cyclesCounted, 2);
      },
    );

    test('a cycle that has not started has nothing to compare', () async {
      await add('p', amount: 1, when: at(2026, 1, 1));
      final cur = c(2026, 10, 26);
      expect(
        notEnough(
          await repo.monthVsAverage(cur, [p1, p2], day(2026, 10, 1), fEgp),
        ).reason,
        NotEnoughReason.noData,
      );
    });
  });

  group('8 installment timeline', () {
    Future<void> item(
      String id, {
      String kind = 'installment',
      String status = 'active',
      String currency = 'EGP',
      int amount = 100000,
      String cadence = 'monthly',
      int? cadenceDays,
      int? dueDay,
      String? next,
      int? total,
      int paid = 0,
      String? account,
    }) => db
        .into(db.recurringItems)
        .insert(
          RecurringItemsCompanion.insert(
            id: id,
            kind: kind,
            status: status,
            name: 'Item $id',
            amountMinor: amount,
            currency: currency,
            cadence: cadence,
            cadenceDays: Value(cadenceDays),
            dueDay: Value(dueDay),
            nextDueDate: Value(next),
            totalCount: Value(total),
            paidCount: Value(paid),
            accountId: Value(account),
            createdAt: t0,
          ),
        );

    test('remaining payments by month, per currency', () async {
      await item('a', next: '2026-11-28', total: 4, paid: 1, dueDay: 31);
      await item('b', next: '2026-12-05', total: 12, amount: 50000);
      await item('gbp', next: '2026-11-10', currency: 'GBP', total: 3);
      await item('sub', kind: 'subscription', next: '2026-11-10');
      await item('done', status: 'completed', next: '2026-11-10', total: 3);
      final t = ready(await repo.installmentTimeline(day(2026, 11, 10), fEgp));
      expect(t.length, 6);
      expect(
        [for (final m in t) (m.year, m.month)],
        [(2026, 11), (2026, 12), (2027, 1), (2027, 2), (2027, 3), (2027, 4)],
      );
      // a: 3 left from 28 Nov, then day 31 clamped: Dec 31, Jan 31.
      expect(t[0].total.minor, 100000);
      expect(t[1].total.minor, 100000 + 50000);
      expect(t[2].total.minor, 100000 + 50000);
      expect(t[3].total.minor, 50000);
      expect(t[0].total.currency, egp);
      expect(t[1].dues.map((d) => d.itemId), ['b', 'a']);
    });

    test(
      'overdue goes into the first month, flagged; account filter',
      () async {
        await item('late', next: '2026-10-20', total: 2, account: 'acc1');
        final t = ready(
          await repo.installmentTimeline(day(2026, 11, 10), fEgp),
        );
        expect([for (final d in t[0].dues) d.overdue], [true, false]);
        expect(t[0].total.minor, 200000);
        expect(t[1].dues, isEmpty);
        final other = ChartFilter(currency: egp, accountIds: {'acc2'});
        expect(
          notEnough(await repo.installmentTimeline(day(2026, 11, 10), other))
              .reason,
          NotEnoughReason.noData,
        );
      },
    );

    test('no installments: not enough data; changes show at once', () async {
      expect(
        notEnough(await repo.installmentTimeline(day(2026, 11, 10), fEgp))
            .reason,
        NotEnoughReason.noData,
      );
      await item('x', next: '2026-11-20', total: 1);
      ready(await repo.installmentTimeline(day(2026, 11, 10), fEgp));
    });
  });

  group('9 subscriptions x12', () {
    test('annual cost by cadence, sorted, per currency', () async {
      Future<void> sub(
        String id,
        int amount,
        String cadence, {
        int? days,
        String currency = 'EGP',
        String status = 'active',
      }) => db
          .into(db.recurringItems)
          .insert(
            RecurringItemsCompanion.insert(
              id: id,
              kind: 'subscription',
              status: status,
              name: id,
              amountMinor: amount,
              currency: currency,
              cadence: cadence,
              cadenceDays: Value(days),
              createdAt: t0,
            ),
          );
      await sub('m', 10000, 'monthly');
      await sub('y', 90000, 'yearly');
      await sub('w', 1000, 'weekly');
      await sub('c', 1000, 'custom_days', days: 10);
      await sub('usd', 5, 'monthly', currency: 'GBP');
      await sub('off', 99999, 'monthly', status: 'dismissed');
      final r = ready(await repo.subscriptionsAnnual(fEgp));
      expect([for (final i in r.items) i.itemId], ['m', 'y', 'w', 'c']);
      expect(
        [for (final i in r.items) i.annual.minor],
        [120000, 90000, 52000, 36500],
      );
      expect(r.annualTotal.minor, 120000 + 90000 + 52000 + 36500);
      expect(r.annualTotal.currency, egp);
      expect(
        ready(await repo.subscriptionsAnnual(ChartFilter(currency: gbp)))
            .annualTotal
            .minor,
        60,
      );
    });

    test('none: not enough data', () async {
      expect(
        notEnough(await repo.subscriptionsAnnual(fEgp)).reason,
        NotEnoughReason.noData,
      );
    });
  });

  group('10 cards split', () {
    test('per card shares add up; currencies stay apart', () async {
      await add('a', amount: 7500, account: 'acc1');
      await add('b', amount: 2500, account: 'acc2');
      await add('g', amount: 100, account: 'acc2', currency: 'GBP');
      await add('in', amount: 5000, account: 'acc1', internal: true);
      final r = ready(await repo.cardsSplit(period, fEgp));
      expect([for (final c in r) c.accountId], ['acc1', 'acc2']);
      expect([for (final c in r) c.spend.minor], [7500, 2500]);
      expect([for (final c in r) c.shareBp], [7500, 2500]);
      expect(r[1].kind, 'credit');
      final g = ready(
        await repo.cardsSplit(period, ChartFilter(currency: gbp)),
      );
      expect(g.single.spend, Money(gbp, 100));
      expect(g.single.shareBp, 10000);
    });

    test('refund reduces the card that paid; empty', () async {
      await add('a', amount: 1000, account: 'acc1');
      await add('rf', amount: 400, direction: 'refund', account: 'acc1');
      await linkRow('l', 'a', 'rf', 400);
      expect(
        ready(await repo.cardsSplit(period, fEgp)).single.spend.minor,
        600,
      );
      expect(
        notEnough(await repo.cardsSplit(period, ChartFilter(currency: gbp)))
            .reason,
        NotEnoughReason.noData,
      );
    });

    test('currenciesWithActivity lists each currency once, sorted', () async {
      await add('a', currency: 'GBP');
      await add('b', currency: 'EGP');
      await add('c', currency: 'EGP', direction: 'income');
      await add('d', currency: 'USD', internal: true);
      expect(await repo.currenciesWithActivity(period), [egp, gbp]);
      expect(
        await repo.currenciesWithActivity(period, accountIds: {'acc2'}),
        isEmpty,
      );
    });
  });

  group('11 net worth', () {
    Future<void> snap(String on, String unit, int assets, int liab) => db
        .into(db.networthSnapshots)
        .insert(
          NetworthSnapshotsCompanion.insert(
            takenOn: on,
            unit: unit,
            assetsMinor: assets,
            liabilitiesMinor: liab,
          ),
        );

    test('one unit at a time, oldest first, signed values kept', () async {
      await snap('2026-09-24', 'EGP', 100000, 20000);
      await snap('2026-10-24', 'EGP', 90000, 120000); // negative net
      await snap('2026-10-24', 'XAU_21K_G', 5000, 0);
      await snap('2026-11-24', 'EGP', 150000, 20000);
      final r = ready(
        await repo.netWorth(
          ChartPeriod(day(2026, 1, 1), day(2026, 12, 31)),
          'EGP',
        ),
      );
      expect(
        [for (final p in r) p.takenOn.toIso()],
        ['2026-09-24', '2026-10-24', '2026-11-24'],
      );
      expect([for (final p in r) p.netMinor], [80000, -30000, 130000]);
      expect(r.every((p) => p.unit == 'EGP'), isTrue);
      expect(await repo.netWorthUnits(), ['EGP', 'XAU_21K_G']);
    });

    test('window applies; fewer than 2 snapshots is not enough', () async {
      await snap('2026-09-24', 'EGP', 1, 0);
      await snap('2026-10-24', 'EGP', 2, 0);
      var n = notEnough(
        await repo.netWorth(
          ChartPeriod(day(2026, 10, 1), day(2026, 12, 1)),
          'EGP',
        ),
      );
      expect(n.reason, NotEnoughReason.tooFewSnapshots);
      expect(n.have, 1);
      n = notEnough(
        await repo.netWorth(
          ChartPeriod(day(2026, 10, 1), day(2026, 12, 1)),
          'USD',
        ),
      );
      expect(n.reason, NotEnoughReason.noData);
    });
  });

  group('12 personal inflation', () {
    test('index over repeated merchants, per currency', () async {
      Future<void> buy(
        String id,
        String m,
        int y,
        int mo,
        int amount, {
        String currency = 'EGP',
      }) => add(
        id,
        merchant: m,
        amount: amount,
        when: at(y, mo, 5),
        currency: currency,
      );
      for (final m in ['a', 'b', 'c']) {
        await buy('$m-1', m, 2026, 1, 10000);
        await buy('$m-2', m, 2026, 6, 11000);
        await buy('$m-3', m, 2026, 11, 12000);
      }
      await buy('g-1', 'a', 2026, 1, 1, currency: 'GBP');
      await buy('g-2', 'a', 2026, 11, 100, currency: 'GBP');
      final r = ready(
        await repo.personalInflationIndex(day(2026, 11, 20), fEgp),
      );
      expect(
        [for (final p in r) (p.month, p.indexBp)],
        [(1, 10000), (6, 11000), (11, 12000)],
      );
      expect(r.last.merchants, 3);
      // GBP has one merchant only.
      final n = notEnough(
        await repo.personalInflationIndex(
          day(2026, 11, 20),
          ChartFilter(currency: gbp),
        ),
      );
      expect(n.reason, NotEnoughReason.tooFewMerchants);
    });

    test(
      'older than 12 months is outside the window; refunds ignored',
      () async {
        for (final m in ['a', 'b', 'c']) {
          await add('$m-0', merchant: m, amount: 5000, when: at(2025, 10, 5));
          await add('$m-1', merchant: m, amount: 10000, when: at(2025, 12, 5));
          await add('$m-2', merchant: m, amount: 10000, when: at(2026, 11, 5));
        }
        final r = ready(
          await repo.personalInflationIndex(day(2026, 11, 20), fEgp),
        );
        expect(r.first.year, 2025);
        expect(r.first.month, 12);
        expect(r.first.indexBp, 10000);
      },
    );

    test('empty: no data', () async {
      expect(
        notEnough(await repo.personalInflationIndex(day(2026, 11, 20), fEgp))
            .reason,
        NotEnoughReason.noData,
      );
    });
  });

  group('memoization', () {
    test('same request is answered once until invalidated', () async {
      await add('a', amount: 100);
      final first = await repo.cashFlow([period], fEgp);
      await add('b', amount: 200);
      final second = await repo.cashFlow([period], fEgp);
      expect(identical(first, second), isTrue); // memo hit
      repo.invalidate();
      expect(repo.memoSize, 0);
      final third = ready(await repo.cashFlow([period], fEgp));
      expect(third.single.spend.minor, 300);
    });

    test('key includes currency, period and accounts', () async {
      await add('a', amount: 100);
      await add('b', amount: 100, currency: 'GBP');
      final e = await repo.categoryDonut(period, fEgp);
      final g = await repo.categoryDonut(period, ChartFilter(currency: gbp));
      final one = await repo.categoryDonut(
        period,
        ChartFilter(currency: egp, accountIds: {'acc2'}),
      );
      expect(identical(e, g), isFalse);
      expect(one, isA<ChartNotEnoughData<CategoryDonut>>());
      expect(ready(e).total.currency, egp);
      expect(ready(g).total.currency, gbp);
    });

    test('the memo is bounded', () async {
      final small = ChartRepository(db, maxMemo: 3);
      await add('a');
      for (var d = 1; d <= 6; d++) {
        await small.categoryDonut(
          ChartPeriod(day(2026, 11, 1), day(2026, 11, d + 1)),
          fEgp,
        );
      }
      expect(small.memoSize, lessThanOrEqualTo(3));
    });
  });

  test('a database failure carries no query text or amounts', () async {
    await db.close();
    try {
      await repo.categoryDonut(period, fEgp);
      fail('should throw');
    } on Object catch (e) {
      expect(e.toString(), isNot(contains('EGP')));
    }
    // tearDown closes again: reopen is not needed, close is idempotent.
  });
}
