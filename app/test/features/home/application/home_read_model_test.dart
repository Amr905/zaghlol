// T-052: Home read model, card filter and the app-level cycle wiring.
// Synthetic data only.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/budget/application/cycle_app_wiring.dart';
import 'package:zaghlol/features/home/application/card_filter.dart';
import 'package:zaghlol/features/home/application/home_read_model.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/ingestion/data/review_repository.dart'
    show reviewOpenCountProvider;
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

final Currency egp = Currency.of('EGP');
final Currency gbp = Currency.of('GBP');

int at(int y, int m, int d, [int h = 10]) =>
    DateTime.utc(y, m, d, h).millisecondsSinceEpoch;

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late DateTime now;
  late ProviderContainer container;
  late StreamController<bool> scan;

  Future<void> add(
    String id, {
    int amount = 1000,
    String direction = 'expense',
    String currency = 'EGP',
    String account = 'acc1',
    bool internal = false,
    int? when,
    int updatedAt = 0,
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
          isInternal: Value(internal ? 1 : 0),
          updatedAt: Value(updatedAt),
        ),
      );

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    now = DateTime.utc(2026, 11, 10, 10);
    scan = StreamController<bool>();
    await db.into(db.accounts).insert(account('acc1'));
    await db.into(db.accounts).insert(account('acc2', last4: '5678'));
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        clockProvider.overrideWithValue(() => now),
        localZoneProvider.overrideWithValue(const FixedLocalZone(120)),
        reviewOpenCountProvider.overrideWith((ref) => Stream.value(3)),
        homeScanInProgressProvider.overrideWith((ref) => scan.stream),
      ],
    );
    addTearDown(() async {
      container.dispose();
      unawaited(scan.close());
      await edb.close();
    });
  });

  Future<HomeModel> model() => container.read(homeModelProvider.future);

  group('home model', () {
    test('EGP only: no currency UI (EC-55), hero and KPIs', () async {
      await add('a', amount: 1000);
      await add('i', amount: 5000, direction: 'income');
      final m = await model();
      expect(m.showCurrencyUi, isFalse);
      expect(m.currencies, hasLength(1));
      expect(m.hero!.currency, egp);
      expect(m.hero!.spend.minor, 1000);
      expect(m.hero!.income.minor, 5000);
      expect(m.hero!.net.minor, 4000);
      expect(m.reviewCount, 3);
    });

    test('no activity: no hero, no currency UI', () async {
      final m = await model();
      expect(m.hero, isNull);
      expect(m.showCurrencyUi, isFalse);
    });

    test('two currencies: primary first, never summed', () async {
      await add('a', amount: 1000);
      await add('g', amount: 4000, currency: 'GBP');
      final m = await model();
      expect(m.showCurrencyUi, isTrue);
      expect([for (final c in m.currencies) c.currency], [egp, gbp]);
      expect(m.currencies[0].spend.minor, 1000);
      expect(m.currencies[1].spend.minor, 4000);
    });

    test('orderCurrencies: primary first even when not alphabetical', () {
      expect(orderCurrencies([egp, gbp], gbp), [gbp, egp]);
      expect(orderCurrencies([egp], gbp), [egp]);
    });

    test(
      'feed labels internal transfers as excluded and not counted',
      () async {
        await add('a', amount: 1000, when: at(2026, 11, 4));
        await add(
          't',
          amount: 9000,
          direction: 'transfer_out',
          internal: true,
          when: at(2026, 11, 5),
        );
        final m = await model();
        expect(m.hero!.spend.minor, 1000);
        expect(m.recent.first.record.id, 't');
        expect(m.recent.first.excludedFromTotals, isTrue);
        expect(m.recent.last.excludedFromTotals, isFalse);
      },
    );

    test('feed is capped', () async {
      for (var i = 0; i < homeFeedLimit + 3; i++) {
        await add('x$i', amount: 1);
      }
      expect((await model()).recent, hasLength(homeFeedLimit));
    });

    test('scan in progress follows the scan stream', () async {
      scan.add(true);
      await Future<void>.delayed(Duration.zero);
      container.listen(homeScanInProgressProvider, (_, _) {});
      scan.add(true);
      await Future<void>.delayed(Duration.zero);
      expect((await model()).scanInProgress, isTrue);
    });
  });

  group('card filter (FR-CARD-01)', () {
    test('changes every figure and the feed', () async {
      await add('a', amount: 1000, account: 'acc1');
      await add('b', amount: 300, account: 'acc2');
      await add('g', amount: 700, currency: 'GBP', account: 'acc2');
      container.listen(homeModelProvider, (_, _) {});
      expect((await model()).hero!.spend.minor, 1300);

      container.read(cardFilterProvider.notifier).selectOnly('acc2');
      var m = await model();
      expect(m.hero!.spend.minor, 300);
      expect(m.recent.map((r) => r.record.id).toSet(), {'b', 'g'});
      expect(m.cardFilter, {'acc2'});

      container.read(cardFilterProvider.notifier).selectOnly('acc1');
      m = await model();
      expect(m.hero!.spend.minor, 1000);
      expect(m.showCurrencyUi, isFalse);

      container.read(cardFilterProvider.notifier).toggle('acc2');
      m = await model();
      expect(m.hero!.spend.minor, 1300);
      expect(m.cardFilter, {'acc1', 'acc2'});

      container.read(cardFilterProvider.notifier).clear();
      expect((await model()).cardFilter, isEmpty);
    });

    test('safe-to-spend ignores the filter; spend figures follow it', () async {
      await db
          .into(db.budgets)
          .insert(
            BudgetsCompanion.insert(
              id: 'b1',
              currency: 'EGP',
              limitMinor: 100000,
              period: 'cycle',
              createdAt: 0,
            ),
          );
      await add('a', amount: 1000, account: 'acc1');
      await add('b', amount: 30000, account: 'acc2');
      container.listen(homeModelProvider, (_, _) {});
      final all = (await model()).hero!;
      container.read(cardFilterProvider.notifier).selectOnly('acc1');
      final m = (await model()).hero!;
      expect(m.spend.minor, 1000);
      expect(all.spend.minor, 31000);
      expect(m.safeToSpend, isNotNull);
      expect(m.safeToSpend, all.safeToSpend);
      expect(m.overview.safeToSpend, isNot(all.safeToSpend));
    });

    test('persists while no listener is attached', () async {
      container.read(cardFilterProvider.notifier).selectOnly('acc2');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(cardFilterProvider), {'acc2'});
    });
  });

  group('app-level cycle wiring (FU-110)', () {
    test('an event drops the cached cycle, then readers recompute', () async {
      await container.read(cycleAppWiringProvider.future);
      container.listen(homeModelProvider, (_, _) {});
      await add('a', amount: 1000);
      expect((await model()).hero!.spend.minor, 1000);

      await add('b', amount: 500);
      container
          .read(domainEventBusProvider)
          .publish(
            TransactionsChanged(
              accountIds: {'acc1'},
              cycleKeys: {'2026-10-25'},
            ),
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((await model()).hero!.spend.minor, 1500);
    });

    test('resume re-reads the day and sweeps late writes', () async {
      await container.read(cycleAppWiringProvider.future);
      container.listen(homeModelProvider, (_, _) {});
      expect(container.read(todayProvider), CivilDate(2026, 11, 10));
      await model();
      await container.read(cycleResumeHandlerProvider).onResume();

      now = DateTime.utc(2026, 11, 11, 10);
      // A closed-cycle row written by "the headless engine" after the last
      // foreground: the sweep must drop that cycle's cache.
      final closedKey = (await container.read(paydayScheduleProvider.future))
          .cycleOn(CivilDate(2026, 10, 10))
          .key;
      final repo = await container.read(cycleRepositoryProvider.future);
      final closed = (await container.read(paydayScheduleProvider.future))
          .cycleOn(CivilDate(2026, 10, 10));
      await add('old', amount: 100, when: at(2026, 10, 10));
      expect((await repo.totals(closed))[egp]!.spend.minor, 100);
      await add(
        'late',
        amount: 800,
        when: at(2026, 10, 10),
        updatedAt: now.millisecondsSinceEpoch,
      );
      expect((await repo.totals(closed))[egp]!.spend.minor, 100); // stale
      await container.read(cycleResumeHandlerProvider).onResume();
      expect((await repo.totals(closed))[egp]!.spend.minor, 900);
      expect(closedKey, closed.key);
      expect(container.read(todayProvider), CivilDate(2026, 11, 11));
    });
  });
}
