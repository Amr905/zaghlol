// T-051: cycle totals and the cache on an encrypted database. Synthetic
// data only.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/daos/budgets_dao.dart';
import 'package:zaghlol/core/db/daos/cycle_summaries_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/budget/data/cycle_cache_invalidator.dart';
import 'package:zaghlol/features/budget/data/cycle_repository.dart';
import 'package:zaghlol/features/budget/data/payday_schedule_store.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

final Currency egp = Currency.of('EGP');
final Currency gbp = Currency.of('GBP');

int at(int y, int m, int d, [int h = 10, int min = 0]) =>
    DateTime.utc(y, m, d, h, min).millisecondsSinceEpoch;

CivilDate day(int y, int m, int d) => CivilDate(y, m, d);

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late int now;
  late CycleRepository repo;
  late CycleCacheInvalidator inv;
  late CycleSummariesDao cache;
  final schedule = PaydaySchedule.single(25);

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
    int? updatedAt,
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
          status: Value(status),
          occurredTzOffsetMin: Value(offset),
          isInternal: Value(internal ? 1 : 0),
          deletedAt: Value(deleted ? t0 : null),
          updatedAt: Value(updatedAt ?? t0),
        ),
      );

  Cycle current() => schedule.cycleOn(day(2026, 11, 10));
  Cycle closed() => schedule.cycleOn(day(2026, 10, 10)); // 25 Sep - 24 Oct

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    now = at(2026, 11, 10);
    await db.into(db.accounts).insert(account('acc1'));
    await db.into(db.accounts).insert(account('acc2', last4: '5678'));
    repo = CycleRepository(
      db,
      nowUtcMs: () => now,
      zone: const FixedLocalZone(120),
    );
    inv = CycleCacheInvalidator(db);
    cache = CycleSummariesDao(db);
  });
  tearDown(() => edb.close());

  group('live totals', () {
    test('row filter, per currency, pending and links', () async {
      await add('a', amount: 1000);
      await add('b', amount: 500, status: 'declined');
      await add('c', amount: 500, status: 'reversed');
      await add('d', amount: 500, internal: true);
      await add('e', amount: 500, deleted: true);
      await add('p', amount: 200, status: 'pending');
      await add('f', amount: 50, direction: 'fee');
      await add('t', amount: 70, direction: 'transfer_out');
      await add('i', amount: 9000, direction: 'income');
      await add('g', amount: 4000, currency: 'GBP');
      await add('r', amount: 300, direction: 'refund');
      await db
          .into(db.offsetLinks)
          .insert(
            link(
              'l1',
              expense: 'a',
              source: 'r',
              amountMinor: 300,
              kind: 'refund',
            ),
          );
      final r = await repo.totals(current());
      expect(r[egp]!.spend.minor, 1000 - 300 + 200 + 50 + 70);
      expect(r[egp]!.pendingSpend.minor, 200);
      expect(r[egp]!.income.minor, 9000);
      expect(r[gbp]!.spend.minor, 4000);
      expect(r[gbp]!.income.minor, 0);
    });

    test(
      'a soft-deleted refund stops offsetting; restoring brings it back',
      () async {
        await add('a', amount: 1000);
        await add('r', amount: 300, direction: 'refund');
        await db
            .into(db.offsetLinks)
            .insert(
              link(
                'l1',
                expense: 'a',
                source: 'r',
                amountMinor: 300,
                kind: 'refund',
              ),
            );
        expect((await repo.computeLive(current()))[egp]!.spend.minor, 700);
        await db.customStatement(
          'UPDATE transactions SET deleted_at = 1 WHERE id = ?',
          ['r'],
        );
        expect((await repo.computeLive(current()))[egp]!.spend.minor, 1000);
        await db.customStatement(
          'UPDATE transactions SET deleted_at = NULL WHERE id = ?',
          ['r'],
        );
        expect((await repo.computeLive(current()))[egp]!.spend.minor, 700);
      },
    );

    test(
      'a reimbursement in a later cycle restates the old cycle only',
      () async {
        await add('x', amount: 1000, when: at(2026, 10, 3));
        await add(
          's',
          amount: 400,
          direction: 'transfer_in',
          when: at(2026, 11, 3),
        );
        await db
            .into(db.offsetLinks)
            .insert(link('l1', expense: 'x', source: 's', amountMinor: 400));
        final old = await repo.computeLive(closed());
        final cur = await repo.computeLive(current());
        expect(old[egp]!.spend.minor, 600);
        expect(cur[egp]!.spend.minor, 0);
        expect(cur[egp]!.income.minor, 0);
      },
    );

    test(
      'local date, not UTC: 01:00 on the spring-forward day (+180)',
      () async {
        // 22:00Z on 24 Apr 2025 is 01:00 local on 25 Apr (payday 25).
        await add('a', amount: 5, when: at(2025, 4, 24, 22), offset: 180);
        await add('b', amount: 7, when: at(2025, 4, 24, 21, 59), offset: 120);
        final c = schedule.cycleOn(day(2025, 4, 25));
        expect((await repo.computeLive(c))[egp]!.spend.minor, 5);
        final prev = schedule.cycleOn(day(2025, 4, 24));
        expect((await repo.computeLive(prev))[egp]!.spend.minor, 7);
      },
    );

    test('account filter: one id, several ids', () async {
      await add('a', amount: 10);
      await add('b', amount: 20, account: 'acc2');
      expect(
        (await repo.totals(current(), accounts: {'acc2'}))[egp]!.spend.minor,
        20,
      );
      expect(
        (await repo.totals(
          current(),
          accounts: {'acc1', 'acc2'},
        ))[egp]!.spend.minor,
        30,
      );
      expect(
        (await cache.rowsFor(cycleStart: current().key, accountFilter: 'acc2')),
        hasLength(1),
      );
      expect(
        (await db.select(db.cycleSummaries).get()).any(
          (r) => r.accountFilter.contains(','),
        ),
        isFalse,
        reason: 'multi-account results are never cached',
      );
    });

    test('byCategory from the database; budgets: overall wins, else the '
        'category sum (A-16)', () async {
      for (final c in ['c1', 'c2']) {
        await db.customStatement(
          'INSERT INTO categories (id, name_ar, name_en, icon, color, bucket, '
          "sort) VALUES ('$c', 'x', 'X', 'i', '#000000', 'needs', 1)",
        );
      }
      await add('a', amount: 100);
      await db.customStatement(
        "UPDATE transactions SET category_id = 'c1' WHERE id = 'a'",
      );
      expect((await repo.computeLive(current()))[egp]!.byCategoryMinor, {
        'c1': 100,
      });
      final budgets = BudgetsDao(db);
      await budgets.insert(
        id: 'b1',
        categoryId: 'c1',
        limit: Money(egp, 300),
        period: BudgetPeriod.cycle,
        createdAt: 1,
      );
      await budgets.insert(
        id: 'b2',
        categoryId: 'c2',
        limit: Money(egp, 400),
        period: BudgetPeriod.cycle,
        createdAt: 1,
      );
      await budgets.insert(
        id: 'b3',
        categoryId: 'c2',
        limit: Money(gbp, 50),
        period: BudgetPeriod.annual,
        createdAt: 1,
      );
      expect(await repo.cycleBudgets(), {egp: Money(egp, 700)});
      await budgets.insert(
        id: 'b4',
        limit: Money(egp, 1000),
        period: BudgetPeriod.cycle,
        createdAt: 1,
      );
      expect(await repo.cycleBudgets(), {egp: Money(egp, 1000)});
    });
  });

  group('cache', () {
    test('current cycle: live, written through; hit equals live', () async {
      await add('a', amount: 1000);
      final live = await repo.totals(current());
      final cached = await repo.cachedTotals(current());
      expect(cached![egp]!.spend, live[egp]!.spend);
      expect(cached[egp]!.income, live[egp]!.income);
      expect(cached[egp]!.byCategoryMinor, live[egp]!.byCategoryMinor);
      // the current cycle is recomputed even with a cached row
      await add('b', amount: 5);
      expect((await repo.totals(current()))[egp]!.spend.minor, 1005);
    });

    test('closed cycle is served from the cache until invalidated', () async {
      await add('a', amount: 1000, when: at(2026, 10, 3));
      expect((await repo.totals(closed()))[egp]!.spend.minor, 1000);
      // a write with no event: the cache is stale by design
      await add('b', amount: 5, when: at(2026, 10, 4));
      expect((await repo.totals(closed()))[egp]!.spend.minor, 1000);
      await inv.onTransactionsChanged(
        TransactionsChanged(accountIds: {'acc1'}, cycleKeys: {closed().key}),
      );
      expect((await repo.totals(closed()))[egp]!.spend.minor, 1005);
    });

    test('TransactionsChanged only drops the listed cycles', () async {
      await add('a', amount: 1000, when: at(2026, 10, 3));
      await add('b', amount: 1, when: at(2026, 9, 3));
      await repo.totals(closed());
      final older = schedule.cycleOn(day(2026, 9, 3));
      await repo.totals(older);
      await inv.onTransactionsChanged(
        TransactionsChanged(accountIds: {}, cycleKeys: {closed().key}),
      );
      expect(await repo.cachedTotals(closed()), isNull);
      expect(await repo.cachedTotals(older), isNotNull);
    });

    test('invalidateAll drops every row', () async {
      await add('a', when: at(2026, 10, 3));
      await repo.totals(closed());
      expect(await inv.invalidateAll(), greaterThan(0));
      expect(await db.select(db.cycleSummaries).get(), isEmpty);
    });

    test(
      'resume sweep drops cycles touched after the last foreground time',
      () async {
        await add('a', amount: 1000, when: at(2026, 10, 3), updatedAt: 100);
        await repo.totals(closed());
        // The headless engine edited the row (updated_at after the last
        // foreground time) without an event in the UI isolate.
        await db.customStatement(
          'UPDATE transactions SET amount_minor = 2000, updated_at = 500 '
          "WHERE id = 'a'",
        );
        expect(await inv.sweepSince(500, schedule), 0, reason: 'not later');
        expect(await inv.sweepSince(499, schedule), 1);
        expect((await repo.totals(closed()))[egp]!.spend.minor, 2000);
      },
    );

    test('resume sweep sees a new link on both sides of it', () async {
      await add('x', amount: 1000, when: at(2026, 10, 3), updatedAt: 1);
      await add(
        's',
        amount: 400,
        direction: 'transfer_in',
        when: at(2026, 11, 3),
        updatedAt: 1,
      );
      await repo.totals(closed());
      await db.customStatement(
        'INSERT INTO offset_links (id, kind, expense_txn_id, source_txn_id, '
        "amount_minor, created_at) VALUES ('l','reimbursement','x','s',400,9)",
      );
      expect(await inv.sweepSince(5, schedule), 1);
      expect((await repo.totals(closed()))[egp]!.spend.minor, 600);
    });

    test('a payday change keeps the keys of closed cycles', () async {
      final s1 = schedule.withChange(day(2026, 11, 10), 1);
      expect(s1.cycleOn(day(2026, 10, 3)).key, closed().key);
      expect(s1.cycleOn(day(2026, 10, 3)), closed());
    });

    test('cached rows round trip other exponents', () async {
      await add('k', amount: 1500, currency: 'KWD', when: at(2026, 10, 3));
      await add('j', amount: 300, currency: 'JPY', when: at(2026, 10, 3));
      await repo.totals(closed());
      final c = (await repo.cachedTotals(closed()))!;
      expect(c[Currency.of('KWD')]!.spend.minor, 1500);
      expect(c[Currency.of('JPY')]!.spend.minor, 300);
    });
  });

  group('PaydayScheduleStore', () {
    late SettingsRepository settings;
    late PaydayScheduleStore store;
    var invalidated = 0;

    setUp(() {
      invalidated = 0;
      settings = SettingsRepository(SettingsDao(db), nowMs: () => now);
      store = PaydayScheduleStore(
        settings,
        nowUtcMs: () => now,
        zone: const FixedLocalZone(120),
        invalidateCycles: () async => invalidated++,
      );
    });

    test('nothing stored: default day 1, nothing written (A-43)', () async {
      expect((await store.load()).eras, [PaydayEra(null, 1)]);
      expect(await settings.get(Settings.paydayEras), isNull);
    });

    test('payday_day without eras: one era for all history', () async {
      await settings.set(Settings.paydayDay, 25);
      expect((await store.load()).eras, [PaydayEra(null, 25)]);
    });

    test(
      'first explicit payday rewrites history (PO Q1 provisional)',
      () async {
        await store.setPayday(25);
        expect((await settings.get(Settings.paydayEras))!.eras, [
          PaydayEra(null, 25),
        ]);
        expect(await settings.get(Settings.paydayDay), 25);
        expect(invalidated, 1);
      },
    );

    test('the second change is EC-21: appends from today', () async {
      await store.setPayday(25);
      await store.setPayday(1);
      final s = await store.load();
      expect(s.eras, [PaydayEra(null, 25), PaydayEra(day(2026, 11, 10), 1)]);
      expect(s.cycleOn(day(2026, 11, 10)).end, day(2026, 11, 30));
      expect(await settings.get(Settings.paydayDay), 1);
    });

    test('payday_day differing from the last era is reconciled and persisted '
        'once', () async {
      await store.setPayday(25);
      await settings.set(Settings.paydayDay, 5); // another writer
      final a = await store.load();
      expect(a.eras.last, PaydayEra(day(2026, 11, 10), 5));
      now = at(2026, 11, 20);
      final b = await store.load();
      expect(b, a, reason: 'does not depend on when it is read');
    });

    test('invalid day is refused without a write', () async {
      for (final bad in [0, 29, 31, -3]) {
        await expectLater(store.setPayday(bad), throwsA(isA<Exception>()));
      }
      expect(await settings.get(Settings.paydayEras), isNull);
      expect(invalidated, 0);
    });
  });
}
