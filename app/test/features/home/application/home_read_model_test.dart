// T-052: Home read model, card filter and the app-level cycle wiring.
// Synthetic data only.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/budget/application/cycle_app_wiring.dart';
import 'package:zaghlol/features/home/application/card_filter.dart';
import 'package:zaghlol/features/home/application/home_read_model.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/ingestion/data/review_repository.dart'
    show reviewOpenCountProvider;
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
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

    test('T-272 PO story: USD salary, USD 600 exchanged to EGP 29,700: EGP '
        'money in 29,700, USD left 400, spending/income unchanged', () async {
      await db
          .into(db.accounts)
          .insert(account('usd', last4: '9945', currency: 'USD'));
      await add(
        'salary',
        amount: 100000,
        direction: 'income',
        currency: 'USD',
        account: 'usd',
      );
      await add('food', amount: 50000);
      final uc = TransferPairingUseCase(
        db,
        loadSchedule: () async => PaydaySchedule.single(1),
        clock: () => now,
      );
      await uc.recordExchange(
        fromAccountId: 'usd',
        sent: Money(Currency.of('USD'), 60000),
        toAccountId: 'acc1',
        received: Money(egp, 2970000),
        occurredAt: DateTime.utc(2026, 11, 5, 10),
        tzOffsetMin: 120,
      );
      container.invalidate(homeModelProvider);
      final m = await model();
      final e = m.currencies.firstWhere((f) => f.currency == egp);
      final u = m.currencies.firstWhere((f) => f.currency.code == 'USD');
      expect(e.income.minor, 0);
      expect(e.exchangedIn.minor, 2970000);
      expect(e.moneyIn.minor, 2970000);
      expect(e.spend.minor, 50000);
      expect(e.net.minor, 2920000);
      expect(u.income.minor, 100000);
      expect(u.spend.minor, 0);
      expect(u.exchangedOut.minor, 60000);
      expect(u.net.minor, 40000);
    });

    test('T-278 PO story: the USD card says left 400; no EGP card', () async {
      await db
          .into(db.accounts)
          .insert(account('usd', last4: '9945', currency: 'USD'));
      await add(
        'salary',
        amount: 100000,
        direction: 'income',
        currency: 'USD',
        account: 'usd',
      );
      final uc = TransferPairingUseCase(
        db,
        loadSchedule: () async => PaydaySchedule.single(1),
        clock: () => now,
      );
      await uc.recordExchange(
        fromAccountId: 'usd',
        sent: Money(Currency.of('USD'), 60000),
        toAccountId: 'acc1',
        received: Money(egp, 2970000),
        occurredAt: DateTime.utc(2026, 11, 5, 10),
        tzOffsetMin: 120,
      );
      container.invalidate(homeModelProvider);
      final m = await model();
      expect(m.hero!.currency, egp);
      expect(m.hero!.moneyIn.minor, 2970000);
      expect([for (final c in m.currencyCards) c.currency.code], ['USD']);
      final usd = m.currencyCards.single;
      expect(usd.left.minor, 40000);
      expect(usd.moneyIn.minor, 100000);
      expect(usd.out.minor, 60000);
    });

    test('T-278 card rule: activity-only and balance-only currencies get a '
        'card, a currency with neither does not; ordered by last activity; '
        'EGP never', () async {
      await db
          .into(db.accounts)
          .insert(account('usd', last4: '9945', currency: 'USD'));
      await db
          .into(db.accounts)
          .insert(account('eur', last4: '1111', currency: 'EUR'));
      await db
          .into(db.accounts)
          .insert(account('chf', last4: '2222', currency: 'CHF'));
      await add('e', amount: 100);
      // GBP: activity only (no balance row).
      await add('g', amount: 4000, currency: 'GBP', when: at(2026, 11, 8));
      // USD: activity, older than GBP.
      await add(
        'u',
        amount: 500,
        currency: 'USD',
        account: 'usd',
        when: at(2026, 11, 2),
      );
      // EUR: balance only (no activity this month).
      await db.customStatement(
        'INSERT INTO account_balances (account_id, currency, balance_minor, '
        'as_of) VALUES (?, ?, ?, ?)',
        ['eur', 'EUR', 25000, 0],
      );
      // CHF: a zero balance and nothing else: no card.
      await db.customStatement(
        'INSERT INTO account_balances (account_id, currency, balance_minor, '
        'as_of) VALUES (?, ?, ?, ?)',
        ['chf', 'CHF', 0, 0],
      );
      container.invalidate(homeModelProvider);
      final m = await model();
      expect(
        [for (final c in m.currencyCards) c.currency.code],
        ['GBP', 'USD', 'EUR'],
      );
      expect(m.currencyCards.last.lastActivity, isNull);
      expect(m.currencyCards.last.left.minor, 0);
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

    test(
      'FU-126: the first resume sweeps from the persisted foreground time',
      () async {
        await container.read(cycleAppWiringProvider.future);
        final settings = await container.read(
          settingsRepositoryProvider.future,
        );
        final closed = (await container.read(paydayScheduleProvider.future))
            .cycleOn(CivilDate(2026, 10, 10));
        final repo = await container.read(cycleRepositoryProvider.future);
        await add('old', amount: 100, when: at(2026, 10, 10), updatedAt: 1000);
        expect((await repo.totals(closed))[egp]!.spend.minor, 100);
        await add('mid', amount: 800, when: at(2026, 10, 10), updatedAt: 2000);
        // The previous process was in the foreground after 'mid' was written.
        await settings.set(Settings.lastForegroundMs, 3000);
        await container.read(cycleResumeHandlerProvider).onResume();
        expect((await repo.totals(closed))[egp]!.spend.minor, 100); // not swept
        expect(
          await settings.get(Settings.lastForegroundMs),
          now.millisecondsSinceEpoch,
        );
      },
    );
  });
}
