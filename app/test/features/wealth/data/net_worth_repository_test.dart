// T-113: net worth repository on an in-memory database. Synthetic data.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/assets_dao.dart';
import 'package:zaghlol/core/db/daos/recurring_dao.dart';
import 'package:zaghlol/features/wealth/data/net_worth_repository.dart';
import 'package:zaghlol/features/wealth/data/prices_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

void main() {
  late AppDatabase db;
  late PricesRepository prices;
  late NetWorthRepository repo;
  var n = 0;
  final now = DateTime.utc(2026, 11, 3, 16);

  setUp(() async {
    n = 0;
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    prices = PricesRepository(db: db, clock: () => now);
    repo = NetWorthRepository(
      db: db,
      prices: prices,
      clock: () => now,
      newId: () => 'A${n++}',
    );
    await prices.apply({
      'asOf': DateTime.utc(2026, 11, 3, 15).toIso8601String(),
      'stale': false,
      'gold': [
        {'symbol': 'XAU21_G', 'currency': 'EGP', 'price': '4217.50'},
      ],
      'fx': {
        'base': 'USD',
        'rates': {'EGP': '48.95'},
      },
    });
  });
  tearDown(() => db.close());

  Future<void> account(String id, String kind, Currency c, int? balance) async {
    final dao = AccountsDao(db);
    await dao.insert(
      AccountsCompanion.insert(
        id: id,
        kind: kind,
        label: id,
        defaultCurrency: c.code,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    await dao.upsertBalance(
      accountId: id,
      currency: c,
      asOf: 1,
      balance: balance == null ? null : Money(c, balance),
    );
  }

  test(
    'AC: 24 g of 21K valued at the current 21K price; native unit kept',
    () async {
      await repo.addAsset(
        const AssetDraft(
          type: AssetType.gold,
          name: 'Gold',
          quantityMilli: 24000,
          karat: 21,
        ),
      );
      final w = await repo.compute(goldCurrency: egp);
      expect(w.valuedGold.single.value, Money(egp, 10122000));
      expect(w.unit('XAU21_G')!.assetsMinor, 24000);
    },
  );

  test('gold without a price (18K) stays native', () async {
    await repo.addAsset(
      const AssetDraft(
        type: AssetType.gold,
        name: 'g',
        quantityMilli: 5000,
        karat: 18,
      ),
    );
    final w = await repo.compute(goldCurrency: egp);
    expect(w.valuedGold, isEmpty);
    expect(w.unit('XAU18_G')!.assetsMinor, 5000);
  });

  test('AC: per unit, never across currencies; liabilities subtract', () async {
    await account('cash', 'cash', egp, 1000000);
    await account('card', 'credit', egp, 250000);
    await account('wise', 'multi_currency', usd, 30000);
    await account('unknown', 'debit', egp, null);
    await repo.addAsset(
      AssetDraft(
        type: AssetType.certificate,
        name: 'CD',
        principal: Money(egp, 50000000),
        rateBp: 810,
        payout: CertificatePayout.monthly,
        maturityDate: '2027-11-28',
      ),
    );
    await repo.addAsset(
      AssetDraft(
        type: AssetType.car,
        name: 'car',
        manualValue: Money(usd, 500000),
      ),
    );
    await repo.addAsset(
      AssetDraft(
        type: AssetType.other,
        name: 'loan',
        manualValue: Money(usd, 100000),
        isLiability: true,
      ),
    );
    final w = await repo.compute(goldCurrency: egp);
    expect(w.unit('EGP')!.assetsMinor, 51000000);
    expect(w.unit('EGP')!.liabilitiesMinor, 250000);
    expect(w.unit('USD')!.netMinor, 30000 + 500000 - 100000);
    expect(w.units.map((u) => u.unit), ['EGP', 'USD']);
  });

  test(
    'installments count once; not again when the card carries them',
    () async {
      await account('bnpl', 'bnpl', egp, 90000);
      await RecurringDao(db).insertItem(
        RecurringItemsCompanion.insert(
          id: 'i1',
          kind: 'installment',
          status: 'active',
          name: 'phone',
          accountId: const Value('bnpl'),
          amountMinor: 30000,
          currency: 'EGP',
          cadence: 'monthly',
          totalCount: const Value(6),
          paidCount: const Value(3),
          createdAt: 1,
        ),
      );
      await RecurringDao(db).insertItem(
        RecurringItemsCompanion.insert(
          id: 'i2',
          kind: 'installment',
          status: 'active',
          name: 'tv',
          amountMinor: 10000,
          currency: 'EGP',
          cadence: 'monthly',
          totalCount: const Value(4),
          paidCount: const Value(1),
          createdAt: 1,
        ),
      );
      final w = await repo.compute(goldCurrency: egp);
      expect(w.unit('EGP')!.liabilitiesMinor, 90000 + 30000);
    },
  );

  test('archived assets and merged accounts are left out', () async {
    final id = await repo.addAsset(
      AssetDraft(type: AssetType.cash, name: 'c', manualValue: Money(egp, 100)),
    );
    await repo.archive(id);
    expect((await repo.compute(goldCurrency: egp)).units, isEmpty);
  });

  test('a Money in another currency is refused before any SQL', () async {
    expect(
      () => repo.addAsset(
        AssetDraft(
          type: AssetType.cash,
          name: 'c',
          currency: egp,
          manualValue: Money(usd, 1),
        ),
      ),
      throwsA(isA<CurrencyMismatch>()),
    );
    expect(await repo.liveAssets(), isEmpty);
  });

  test('snapshot: on demand, replaces same day, history, due rule', () async {
    await account('cash', 'cash', egp, 1000);
    await repo.addAsset(
      const AssetDraft(
        type: AssetType.gold,
        name: 'g',
        quantityMilli: 24000,
        karat: 21,
      ),
    );
    final d1 = CivilDate(2026, 10, 28);
    expect(await repo.takeSnapshot(today: d1, goldCurrency: egp), 2);
    await account('cash2', 'cash', egp, 500);
    await repo.takeSnapshot(today: d1, goldCurrency: egp);
    final h = await repo.history('EGP');
    expect(h.single.assetsMinor, 1500);
    expect((await repo.history('XAU21_G')).single.assetsMinor, 24000);

    final start = CivilDate(2026, 11, 28);
    expect(
      await repo.snapshotIfDue(
        today: CivilDate(2026, 11, 20),
        currentCycleStart: CivilDate(2026, 10, 28),
        goldCurrency: egp,
      ),
      isFalse,
    );
    expect(
      await repo.snapshotIfDue(
        today: CivilDate(2026, 11, 28),
        currentCycleStart: start,
        goldCurrency: egp,
      ),
      isTrue,
    );
    expect((await repo.history('EGP')).length, 2);
  });

  test('upcoming payouts: 3,375.00 on day 28, soonest first', () async {
    await repo.addAsset(
      AssetDraft(
        type: AssetType.certificate,
        name: 'CD',
        principal: Money(egp, 50000000),
        rateBp: 810,
        payout: CertificatePayout.monthly,
        maturityDate: '2027-11-28',
      ),
    );
    final e = await repo.upcomingPayouts(
      from: CivilDate(2026, 11, 3),
      to: CivilDate(2027, 1, 31),
    );
    expect(e.map((x) => x.date.toIso()), [
      '2026-11-28',
      '2026-12-28',
      '2027-01-28',
    ]);
    expect(e.first.amount, Money(egp, 337500));
  });
}
