// CAT-cash (PO CAT-CASH): the cash pool in the cycle repository and the
// chart queries, on an encrypted database. Synthetic data only.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/cash_cover_sql.dart';
import 'package:zaghlol/features/budget/data/cycle_cache_invalidator.dart';
import 'package:zaghlol/features/budget/data/cycle_repository.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/insights/data/chart_repository.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

final egp = Currency.of('EGP');
final gbp = Currency.of('GBP');

int at(int y, int m, int d, [int h = 10]) =>
    DateTime.utc(y, m, d, h).millisecondsSinceEpoch;

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late CycleRepository cycles;
  late ChartRepository charts;
  final schedule = PaydaySchedule.single(25);
  final cycle = schedule.cycleOn(CivilDate(2026, 11, 10)); // 25 Oct .. 24 Nov
  final nextCycle = schedule.cycleOn(CivilDate(2026, 12, 10));

  Future<void> cat(String id) => db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: id,
          nameAr: id,
          nameEn: id,
          icon: 'x',
          color: '#000000',
          bucket: 'wants',
          sort: 0,
        ),
      );

  Future<void> add(
    String id,
    int amount, {
    required String account,
    String? category,
    String currency = 'EGP',
    int? when,
    bool deleted = false,
    String direction = 'expense',
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
        ).copyWith(
          occurredTzOffsetMin: const Value(120),
          deletedAt: Value(deleted ? t0 : null),
          categoryId: Value(category),
        ),
      );

  Future<void> withdraw(String id, int amount, {int? when, String c = 'EGP'}) =>
      add(
        id,
        amount,
        account: 'bank',
        category: 'sys:cash',
        when: when,
        currency: c,
      );
  Future<void> payCash(
    String id,
    int amount, {
    String category = 'sys:food',
    int? when,
    String c = 'EGP',
    bool deleted = false,
  }) => add(
    id,
    amount,
    account: 'wallet',
    category: category,
    when: when,
    currency: c,
    deleted: deleted,
  );

  Future<CycleTotals> totals([Cycle? c]) async =>
      (await cycles.computeLive(c ?? cycle))[egp]!;

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    await db.into(db.accounts).insert(account('bank', kind: 'debit'));
    await db
        .into(db.accounts)
        .insert(
          account('wallet', kind: 'cash', last4: null, defaultCash: true),
        );
    await cat('sys:cash');
    await cat('sys:food');
    await cat('sys:fun');
    cycles = CycleRepository(
      db,
      nowUtcMs: () => at(2026, 11, 10),
      zone: const FixedLocalZone(120),
    );
    charts = ChartRepository(db);
  });
  tearDown(() => edb.close());

  group('cycle totals', () {
    test(
      'withdraw 1000, pay 300 cash: total 1000, Cash 700, Food 300',
      () async {
        await withdraw('w', 1000);
        await payCash('p', 300);
        final t = await totals();
        expect(t.spend.minor, 1000);
        expect(t.byCategoryMinor['sys:cash'], 700);
        expect(t.byCategoryMinor['sys:food'], 300);
      },
    );

    test('pay 1200 cash: total 1200, Cash 0, Food 1200', () async {
      await withdraw('w', 1000);
      await payCash('p', 1200);
      final t = await totals();
      expect(t.spend.minor, 1200);
      expect(t.byCategoryMinor['sys:cash'], 0);
      expect(t.byCategoryMinor['sys:food'], 1200);
    });

    test('two currencies are separate', () async {
      await withdraw('w', 1000);
      await payCash('g', 500, c: 'GBP');
      final r = await cycles.computeLive(cycle);
      expect(r[egp]!.spend.minor, 1000);
      expect(r[gbp]!.spend.minor, 500); // no GBP withdrawal: new spending
    });

    test(
      'deleting the payment restores; deleting the withdrawal too',
      () async {
        await withdraw('w', 1000);
        await payCash('p', 300);
        await payCash('q', 900, category: 'sys:fun');
        // pool 1000: p 300, q 700 covered, 200 new.
        expect((await totals()).spend.minor, 1200);
        await (db.update(db.transactions)..where((t) => t.id.equals('p')))
            .write(TransactionsCompanion(deletedAt: Value(t0)));
        var t = await totals();
        expect(t.spend.minor, 1000); // q fully covered
        expect(t.byCategoryMinor['sys:fun'], 900);
        await (db.update(db.transactions)..where((t) => t.id.equals('w')))
            .write(TransactionsCompanion(deletedAt: Value(t0)));
        t = await totals();
        expect(t.spend.minor, 900);
      },
    );

    test('the pool carries across periods; the cache follows', () async {
      await withdraw('w', 1000, when: at(2026, 11, 3));
      await payCash('p', 300, when: at(2026, 12, 3));
      final first = await totals();
      final second = await totals(nextCycle);
      expect(first.spend.minor, 1000);
      expect(second.spend.minor, 0);
      expect(second.byCategoryMinor['sys:food'], 300);
      expect(second.byCategoryMinor['sys:cash'], 0);
      expect(second.coveredEarlier.minor, 300);
      // Cache the later cycle, then delete the earlier withdrawal: the
      // later cycle's cached cover is stale and must be dropped with it.
      final cache = CycleCacheInvalidator(db);
      // Both cycles are closed by January, so their totals are cached.
      cycles = CycleRepository(
        db,
        nowUtcMs: () => at(2027, 1, 10),
        zone: const FixedLocalZone(120),
      );
      expect((await cycles.totals(nextCycle))[egp]!.spend.minor, 0);
      await (db.update(db.transactions)..where((t) => t.id.equals('w'))).write(
        TransactionsCompanion(deletedAt: Value(t0)),
      );
      await cache.onTransactionsChanged(
        TransactionsChanged(cycleKeys: {cycle.key}, accountIds: {'bank'}),
      );
      final again = (await cycles.totals(nextCycle))[egp]!;
      expect(again.spend.minor, 300);
    });

    test(
      'internal, declined and non-cash accounts never enter the pool',
      () async {
        await withdraw('w', 1000);
        await add('dp', 300, account: 'wallet', category: 'sys:food');
        await (db.update(db.transactions)..where((t) => t.id.equals('dp')))
            .write(const TransactionsCompanion(status: Value('declined')));
        await add('bankfood', 300, account: 'bank', category: 'sys:food');
        final t = await totals();
        expect(t.spend.minor, 1300);
        expect(t.byCategoryMinor['sys:cash'], 1000);
      },
    );
  });

  group('charts', () {
    final period = ChartPeriod.cycle(cycle);
    final f = ChartFilter(currency: egp);

    test('split link on a covered payment: spend 900 everywhere', () async {
      await withdraw('w', 1000);
      await payCash('p', 300);
      await add('r', 200, account: 'bank', direction: 'refund');
      await db
          .into(db.offsetLinks)
          .insert(link('l1', expense: 'p', source: 'r', amountMinor: 200));
      await payCash('q', 800, category: 'sys:fun');
      final t = await totals();
      expect(t.spend.minor, 900);
      final d = (await charts.categoryDonut(
        period,
        f,
      ) as ChartReady<CategoryDonut>).data;
      expect(d.total.minor, 900);
      final flow = (await charts.cashFlow([
        period,
      ], f) as ChartReady<List<CashFlowPoint>>).data;
      expect(flow.single.spend.minor, 900);
    });

    test('donut and cash flow agree with the cycle totals', () async {
      await withdraw('w', 1000);
      await payCash('p', 300);
      final d = (await charts.categoryDonut(
        period,
        f,
      ) as ChartReady<CategoryDonut>).data;
      expect(d.total.minor, 1000);
      final by = {for (final s in d.slices) s.categoryId: s.amount.minor};
      expect(by, {'sys:cash': 700, 'sys:food': 300});
      final flow = (await charts.cashFlow([
        period,
      ], f) as ChartReady<List<CashFlowPoint>>).data;
      expect(flow.single.spend.minor, 1000);
    });

    test('cross-cycle: no negative slice, covered shown as a note', () async {
      await withdraw('w', 1000, when: at(2026, 10, 20));
      await payCash('p', 300, when: at(2026, 11, 3));
      final d = (await charts.categoryDonut(
        period,
        f,
      ) as ChartReady<CategoryDonut>).data;
      expect(d.total.minor, 0);
      expect(d.coveredEarlier!.minor, 300);
      expect(d.slices.map((s) => s.categoryId), ['sys:food']);
    });

    test('cross-cycle budgets: Food counts it, Cash is not negative', () async {
      await withdraw('w', 1000, when: at(2026, 10, 20));
      await payCash('p', 300, when: at(2026, 11, 3));
      final t = await totals();
      expect(t.byCategoryMinor['sys:food'], 300);
      expect(t.byCategoryMinor['sys:cash'], 0);
      expect(t.spend.minor, 0);
    });

    test('overspend: total 1200', () async {
      await withdraw('w', 1000);
      await payCash('p', 1200);
      final d = (await charts.categoryDonut(
        period,
        f,
      ) as ChartReady<CategoryDonut>).data;
      expect(d.total.minor, 1200);
      expect(d.slices.map((s) => s.categoryId), ['sys:food']);
    });
  });

  group('SQL pool equals the domain reference', () {
    test('a mixed sequence, two currencies', () async {
      final ev = <CashEvent>[];
      var n = 0;
      Future<void> w(int a, int d, [String c = 'EGP']) async {
        final id = 'w${n++}';
        await withdraw(id, a, when: at(2026, 11, d), c: c);
        ev.add(
          CashEvent(
            id: id,
            kind: CashEventKind.withdrawal,
            amount: Money.fromStorage(a, c),
            localMs: at(2026, 11, d) + 120 * 60000,
          ),
        );
      }

      Future<void> p(int a, int d, [String c = 'EGP']) async {
        final id = 'p${n++}';
        await payCash(id, a, when: at(2026, 11, d), c: c);
        ev.add(
          CashEvent(
            id: id,
            kind: CashEventKind.payment,
            amount: Money.fromStorage(a, c),
            localMs: at(2026, 11, d) + 120 * 60000,
          ),
        );
      }

      await p(50, 1);
      await w(1000, 2);
      await p(300, 3);
      await p(900, 4);
      await w(200, 5);
      await p(250, 6);
      await w(70, 7, 'GBP');
      await p(100, 8, 'GBP');
      final rows = await db
          .customSelect('WITH $cashCoverCte SELECT id, covered FROM cash_cover')
          .get();
      final sql = {
        for (final r in rows) r.read<String>('id'): r.read<int>('covered'),
      };
      final ref = {
        for (final e in allocateCashPool(ev).entries) e.key: e.value.minor,
      };
      expect(sql, ref);
    });
  });
}
