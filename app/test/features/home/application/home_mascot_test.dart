// FU-224: Home mascot message picker and provider.
// Synthetic data only.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/budget/application/cycle_overview.dart';
import 'package:zaghlol/features/home/application/home_mascot.dart';
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

CurrencyOverview _ov(Currency c, {bool? under}) => CurrencyOverview(
  currency: c,
  totals: CycleTotals(
    currency: c,
    income: Money.zero(c),
    spend: Money.zero(c),
    pendingSpend: Money.zero(c),
    byCategoryMinor: const {},
  ),
  budget: null,
  safeToSpend: null,
  underIdealLine: under,
);

HomeCurrencyFigures _fig(Currency c, int net, {bool? under}) =>
    HomeCurrencyFigures(
      overview: _ov(c, under: under),
      net: Money(c, net),
    );

CycleTotals _prev(Currency c, int income, int spend) => CycleTotals(
  currency: c,
  income: Money(c, income),
  spend: Money(c, spend),
  pendingSpend: Money.zero(c),
  byCategoryMinor: const {},
);

void main() {
  group('pickHomeMascot', () {
    test('saved more than last cycle quotes the difference', () {
      final m = pickHomeMascot(
        figures: _fig(egp, 4000),
        previous: _prev(egp, 5000, 4000),
      );
      expect((m! as MascotSavedMore).amount, Money(egp, 3000));
    });

    test('not more saved: falls back to on track, else null', () {
      final f = _fig(egp, 500, under: true);
      expect(
        pickHomeMascot(figures: f, previous: _prev(egp, 5000, 4000)),
        isA<MascotOnTrack>(),
      );
      expect(
        pickHomeMascot(
          figures: _fig(egp, 500),
          previous: _prev(egp, 5000, 4000),
        ),
        isNull,
      );
    });

    test('empty or other-currency previous cycle is not a comparison', () {
      expect(
        pickHomeMascot(figures: _fig(egp, 4000), previous: _prev(egp, 0, 0)),
        isNull,
      );
      expect(
        pickHomeMascot(figures: _fig(egp, 4000), previous: _prev(gbp, 1, 0)),
        isNull,
      );
      expect(pickHomeMascot(figures: _fig(egp, 4000)), isNull);
    });

    test('nothing saved this cycle is never praised as saving', () {
      expect(
        pickHomeMascot(figures: _fig(egp, -100), previous: _prev(egp, 0, 5000)),
        isNull,
      );
    });
  });

  group('homeMascotMessageProvider', () {
    late EncryptedDb edb;
    late AppDatabase db;
    late ProviderContainer container;

    Future<void> add(
      String id, {
      required int amount,
      required String direction,
      required int when,
      String currency = 'EGP',
    }) => db
        .into(db.transactions)
        .insert(
          txn(
            id,
            accountId: 'acc1',
            direction: direction,
            amountMinor: amount,
            currency: currency,
            occurredAt: when,
          ).copyWith(occurredTzOffsetMin: const Value(120)),
        );

    setUp(() async {
      edb = await EncryptedDb.open(background: false);
      db = edb.db;
      await db.into(db.accounts).insert(account('acc1'));
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 10, 10)),
          localZoneProvider.overrideWithValue(const FixedLocalZone(120)),
          reviewOpenCountProvider.overrideWith((ref) => Stream.value(0)),
          homeScanInProgressProvider.overrideWith((ref) => Stream.value(false)),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await edb.close();
      });
    });

    Future<HomeMascotMessage?> read() {
      container.listen(homeModelProvider, (_, _) {});
      container.listen(homeMascotMessageProvider, (_, _) {});
      return container.read(homeMascotMessageProvider.future);
    }

    test('compares against the previous cycle, per currency', () async {
      await add('o1', amount: 5000, direction: 'income', when: at(2026, 10, 5));
      await add(
        'o2',
        amount: 4000,
        direction: 'expense',
        when: at(2026, 10, 6),
      );
      await add('n1', amount: 5000, direction: 'income', when: at(2026, 11, 3));
      await add(
        'n2',
        amount: 1000,
        direction: 'expense',
        when: at(2026, 11, 4),
      );
      final m = await read();
      expect((m! as MascotSavedMore).amount, Money(egp, 3000));
    });

    test('other currencies are never mixed into the comparison', () async {
      await add('o1', amount: 5000, direction: 'income', when: at(2026, 10, 5));
      await add(
        'g1',
        amount: 90000,
        direction: 'income',
        currency: 'GBP',
        when: at(2026, 11, 3),
      );
      expect(await read(), isNull);
    });

    test('no data: no message', () async {
      expect(await read(), isNull);
    });
  });
}
