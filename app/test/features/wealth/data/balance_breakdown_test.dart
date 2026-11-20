// T-199: balance per account, computed from transactions, and the net worth
// breakdown (design note T-199). In-memory database, synthetic data.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/assets_dao.dart';
import 'package:zaghlol/core/db/daos/recurring_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart' as keys;
import 'package:zaghlol/features/accounts/data/drift_accounts_repository.dart';
import 'package:zaghlol/features/wealth/data/net_worth_repository.dart';
import 'package:zaghlol/features/wealth/data/prices_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final t0 = DateTime.utc(2026, 11, 1, 10);
final now = DateTime.utc(2026, 11, 20, 10);

int at(int day, [int hour = 12]) =>
    DateTime.utc(2026, 11, day, hour).millisecondsSinceEpoch;

void main() {
  late AppDatabase db;
  late NetWorthRepository repo;
  var txn = 0;

  setUp(() {
    txn = 0;
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    repo = NetWorthRepository(
      db: db,
      prices: PricesRepository(db: db, clock: () => now),
      clock: () => now,
      newId: () => 'N${txn++}',
    );
  });
  tearDown(() => db.close());

  Future<void> account(
    String id,
    String kind, {
    Currency? cur,
    String? inst,
    bool hidden = false,
    int? limit,
  }) => AccountsDao(db).insert(
    AccountsCompanion.insert(
      id: id,
      kind: kind,
      label: id,
      institutionCode: Value(inst),
      defaultCurrency: (cur ?? egp).code,
      creditLimitMinor: Value(limit),
      isHidden: Value(hidden ? 1 : 0),
      createdAt: 1,
      updatedAt: 1,
    ),
  );

  Future<void> reported(
    String id,
    Currency c,
    int? balance,
    int asOf, {
    int? available,
  }) => AccountsDao(db).upsertBalance(
    accountId: id,
    currency: c,
    asOf: asOf,
    balance: balance == null ? null : Money(c, balance),
    available: available == null ? null : Money(c, available),
  );

  Future<void> tx(
    String account,
    String direction,
    int amount,
    int occurredAt, {
    Currency? cur,
    String status = 'posted',
    bool deleted = false,
    bool internal = false,
  }) => db.customStatement(
    'INSERT INTO transactions (id, account_id, source, direction, status, '
    'amount_minor, currency, occurred_at, occurred_tz_offset_min, '
    'category_source, is_internal, deleted_at, created_at, updated_at) '
    "VALUES (?, ?, 'manual', ?, ?, ?, ?, ?, 0, 'none', ?, ?, 1, 1)",
    [
      't${txn++}',
      account,
      direction,
      status,
      amount,
      (cur ?? egp).code,
      occurredAt,
      internal ? 1 : 0,
      deleted ? 1 : null,
    ],
  );

  Future<BreakdownLine> line(String id, [Currency? c]) async {
    final b = await repo.breakdown(goldCurrency: egp);
    return b.lines.firstWhere(
      (l) => l.refId == id && l.unit == (c ?? egp).code,
    );
  }

  Future<void> setOpening(String id, Money m, DateTime asOf) async {
    final dao = SettingsDao(db);
    final k = keys.Settings.openingBalances;
    final cur = k.parse(await dao.read(k.name));
    await dao.write(k.name, k.format(cur.withEntry(id, m, asOf)), at: 1);
  }

  group('computed balance', () {
    test(
      'reported alone is reported; later transactions make it computed',
      () async {
        await account('a', 'debit');
        await reported('a', egp, 100000, at(5));
        var l = await line('a');
        expect(l.source, BalanceSource.reported);
        expect(l.amount!.minor, 100000);

        await tx('a', 'expense', 2500, at(6));
        await tx('a', 'income', 10000, at(7));
        l = await line('a');
        expect(l.source, BalanceSource.computed);
        expect(l.amount!.minor, 107500);
        expect(l.sinceCount, 2);
        expect(l.asOf!.millisecondsSinceEpoch, at(5));
      },
    );

    test(
      'a transaction at or before the anchor instant is already inside it',
      () async {
        await account('a', 'debit');
        await reported('a', egp, 100000, at(5));
        await tx('a', 'expense', 999, at(5)); // same instant
        await tx('a', 'expense', 999, at(4)); // earlier (late message)
        final l = await line('a');
        expect(l.source, BalanceSource.reported);
        expect(l.amount!.minor, 100000);
      },
    );

    test(
      'a newer reported balance re-anchors; older rows are not re-added',
      () async {
        await account('a', 'debit');
        await reported('a', egp, 100000, at(5));
        await tx('a', 'expense', 2000, at(6));
        await tx('a', 'expense', 3000, at(8));
        await reported('a', egp, 94000, at(8)); // bank figure after both
        final l = await line('a');
        expect(l.source, BalanceSource.reported);
        expect(l.amount!.minor, 94000);
        await tx('a', 'fee', 500, at(9));
        expect((await line('a')).amount!.minor, 93500);
      },
    );

    test('refund adds, fee subtracts, income adds', () async {
      await account('a', 'debit');
      await reported('a', egp, 10000, at(1));
      await tx('a', 'refund', 1500, at(2));
      await tx('a', 'fee', 100, at(3));
      await tx('a', 'income', 5000, at(4));
      await tx('a', 'expense', 400, at(5));
      expect((await line('a')).amount!.minor, 10000 + 1500 - 100 + 5000 - 400);
    });

    test('pending, declined, reversed and deleted never count', () async {
      await account('a', 'debit');
      await reported('a', egp, 10000, at(1));
      await tx('a', 'expense', 100, at(2), status: 'pending');
      await tx('a', 'expense', 200, at(2), status: 'declined');
      await tx('a', 'expense', 300, at(2), status: 'reversed');
      await tx('a', 'expense', 400, at(2), deleted: true);
      final l = await line('a');
      expect(l.amount!.minor, 10000);
      expect(l.source, BalanceSource.reported);
    });

    test('own transfers move both sides, internal flag or not', () async {
      await account('a', 'debit');
      await account('b', 'debit');
      await reported('a', egp, 50000, at(1));
      await reported('b', egp, 20000, at(1));
      await tx('a', 'transfer_out', 8000, at(2), internal: true);
      await tx('b', 'transfer_in', 8000, at(2), internal: true);
      expect((await line('a')).amount!.minor, 42000);
      expect((await line('b')).amount!.minor, 28000);
      final b = await repo.breakdown(goldCurrency: egp);
      expect(b.unit('EGP')!.netMinor, 70000); // unchanged by the transfer
    });

    test('a one-sided own transfer moves only its account', () async {
      await account('a', 'debit');
      await reported('a', egp, 50000, at(1));
      await tx('a', 'transfer_out', 8000, at(2), internal: true);
      expect((await line('a')).amount!.minor, 42000);
    });

    test('card payment: bank down, card owed down', () async {
      await account('bank', 'debit');
      await account('card', 'credit', limit: 5000000);
      await reported('bank', egp, 100000, at(1));
      await reported(
        'card',
        egp,
        null,
        at(1),
        available: 4940000,
      ); // owed 60000
      await tx('card', 'expense', 10000, at(2));
      await tx('bank', 'transfer_out', 30000, at(3), internal: true);
      await tx('card', 'transfer_in', 30000, at(3), internal: true);
      expect((await line('bank')).amount!.minor, 70000);
      final card = await line('card');
      expect(card.amount!.minor, 60000 + 10000 - 30000);
      expect(card.isLiability, isTrue);
      final u = (await repo.breakdown(goldCurrency: egp)).unit('EGP')!;
      expect(u.netMinor, 70000 - 40000);
    });

    test('a card refund lowers what is owed', () async {
      await account('card', 'credit', limit: 5000000);
      await reported('card', egp, null, at(1), available: 4940000);
      await tx('card', 'refund', 2000, at(2));
      expect((await line('card')).amount!.minor, 58000);
    });

    test(
      'multi-currency account: each currency on its own, no conversion',
      () async {
        await account('w', 'multi_currency', inst: 'wise');
        await reported('w', usd, 120000, at(1));
        await reported('w', egp, 100000, at(1));
        await tx('w', 'transfer_out', 50000, at(2), cur: usd);
        await tx('w', 'transfer_in', 2400000, at(2));
        await tx('w', 'fee', 100, at(3), cur: usd);
        expect((await line('w', usd)).amount!.minor, 69900);
        expect((await line('w', egp)).amount!.minor, 2500000);
        final b = await repo.breakdown(goldCurrency: egp);
        expect(b.unit('USD')!.netMinor, 69900);
        expect(b.unit('EGP')!.netMinor, 2500000);
      },
    );

    test('hidden counts, merged is gone', () async {
      await account('h', 'debit', hidden: true);
      await reported('h', egp, 777, at(1));
      await account('m', 'debit');
      await reported('m', egp, 5, at(1));
      await db.customStatement(
        "UPDATE accounts SET merged_into_id = 'h' WHERE id = 'm'",
      );
      final b = await repo.breakdown(goldCurrency: egp);
      expect(b.lines.where((l) => l.refId == 'm'), isEmpty);
      expect(b.unit('EGP')!.netMinor, 777);
      expect(b.lines.single.isHidden, isTrue);
    });
  });

  group('anchors', () {
    test('no figure: unknown, excluded, never computed from zero', () async {
      await account('a', 'debit');
      await tx('a', 'income', 9999, at(2));
      final b = await repo.breakdown(goldCurrency: egp);
      final l = b.lines.single;
      expect(l.source, BalanceSource.unknown);
      expect(b.unit('EGP')!.excluded.single.refId, 'a');
      expect(b.unit('EGP')!.netMinor, 0);
      expect(b.worth.units, isEmpty);
    });

    test('user-entered balance anchors; transactions after it count', () async {
      await account('a', 'cash');
      await setOpening('a', Money(egp, 30000), t0);
      await tx('a', 'expense', 1000, t0.millisecondsSinceEpoch + 1000);
      await tx('a', 'expense', 7777, t0.millisecondsSinceEpoch - 1000);
      final l = await line('a');
      expect(l.source, BalanceSource.computed);
      expect(l.basis, AnchorBasis.userEntered);
      expect(l.amount!.minor, 29000);
    });

    test('newer reported beats older user entry and vice versa', () async {
      await account('a', 'debit');
      await setOpening('a', Money(egp, 30000), t0);
      await reported('a', egp, 40000, at(5));
      var l = await line('a');
      expect(l.amount!.minor, 40000);
      expect(l.source, BalanceSource.reported);
      await setOpening('a', Money(egp, 1234), DateTime.utc(2026, 11, 10));
      l = await line('a');
      expect(l.amount!.minor, 1234);
      expect(l.source, BalanceSource.userEntered);
    });

    test('available-only asset account anchors on available', () async {
      await account('a', 'debit');
      await reported('a', egp, null, at(5), available: 8000);
      final l = await line('a');
      expect(l.amount!.minor, 8000);
      expect(l.basis, AnchorBasis.reportedAvailable);
    });

    test(
      'card: stored balance is never owed; owed = limit - available',
      () async {
        // "Avl bal 85,000" stored as balance on a 100,000 limit: owed 15,000.
        await account('c1', 'credit', limit: 10000000);
        await reported('c1', egp, 8500000, at(5));
        await account('c2', 'credit', limit: 10000000);
        await reported('c2', egp, null, at(5), available: 7000000);
        await account('c3', 'credit'); // no limit
        await reported('c3', egp, 7000000, at(5));
        expect((await line('c1')).amount!.minor, 1500000);
        expect((await line('c1')).basis, AnchorBasis.limitMinusAvailable);
        expect((await line('c2')).amount!.minor, 3000000);
        expect((await line('c3')).source, BalanceSource.unknown);
        // Spending raises what is owed.
        await tx('c1', 'expense', 200000, at(6));
        expect((await line('c1')).amount!.minor, 1700000);
        // A typed owed amount rescues the card without a limit.
        await setOpening('c3', Money(egp, 400000), DateTime.utc(2026, 11, 6));
        expect((await line('c3')).amount!.minor, 400000);
      },
    );

    test('a typed balance dated in the future counts as dated now', () async {
      await account('a', 'debit');
      await setOpening(
        'a',
        Money(egp, 500),
        now.add(const Duration(days: 365)),
      );
      await tx('a', 'expense', 100, now.millisecondsSinceEpoch - 1000);
      var l = await line('a');
      expect(l.asOf, now);
      expect(l.amount!.minor, 500);
      // A bank message at "now" is not beaten by it.
      await reported('a', egp, 900, now.millisecondsSinceEpoch);
      l = await line('a');
      expect(l.source, BalanceSource.reported);
      expect(l.amount!.minor, 900);
    });

    test('staleness flagged after 30 days, still counted', () async {
      await account('a', 'debit');
      await reported(
        'a',
        egp,
        500,
        DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
      );
      final l = await line('a');
      expect(l.stale, isTrue);
      expect(l.amount!.minor, 500);
    });

    test('merge moves the user-entered balance to the target', () async {
      await account('s', 'debit');
      await account('t', 'debit');
      await setOpening('s', Money(egp, 4200), t0);
      final repoA = DriftAccountsRepository(
        AccountsDao(db),
        settings: SettingsDao(db),
      );
      await repoA.merge(sourceId: 's', targetId: 't');
      final b = await repo.breakdown(goldCurrency: egp);
      expect(b.lines.single.refId, 't');
      expect(b.lines.single.amount!.minor, 4200);
    });

    test('garbage in the setting reads as no user balances', () async {
      await account('a', 'debit');
      await SettingsDao(db).write('balance.opening', 'T199SENTINEL', at: 1);
      expect((await line('a')).source, BalanceSource.unknown);
    });
  });

  group('breakdown sums', () {
    test('every unit sums to computeNetWorth; unknown listed; tiers', () async {
      await account('a', 'debit', inst: 'cib');
      await account('b', 'debit', inst: 'cib');
      await account('c', 'credit', inst: 'cib', limit: 9000000);
      await account('u', 'wallet'); // unknown
      await account('w', 'multi_currency');
      await reported('a', egp, 100000, at(1));
      await reported('b', egp, 50000, at(1));
      await reported('c', egp, null, at(1), available: 8970000);
      await reported('w', usd, 1000, at(1));
      await tx('a', 'expense', 1000, at(2));
      await AssetsDao(db).insert(
        id: 'as1',
        type: AssetType.cash,
        name: 'Cash USD',
        currency: usd,
        manualValue: Money(usd, 500),
        createdAt: 1,
      );
      final full = await repo.breakdown(goldCurrency: egp);
      for (final u in full.units) {
        final w = full.worth.unit(u.unit);
        if (w == null) {
          expect(u.assetsMinor - u.liabilitiesMinor, 0);
          continue;
        }
        expect(u.netMinor, w.netMinor, reason: u.unit);
        final lineSum =
            u.accounts
                .followedBy(u.assets)
                .fold<int>(0, (s, l) => s + l.amount!.minor) -
            u.liabilities.fold<int>(0, (s, l) => s + l.amount!.minor);
        expect(lineSum, u.netMinor, reason: u.unit);
      }
      final egpU = full.unit('EGP')!;
      expect(egpU.netMinor, 99000 + 50000 - 30000);
      expect(egpU.excluded.map((l) => l.refId), ['u']);
      expect(full.unit('USD')!.netMinor, 1000 + 500);

      final free = await repo.breakdown(
        goldCurrency: egp,
        includeAssets: false,
      );
      expect(free.unit('USD')!.netMinor, 1000);
      expect(free.unit('EGP')!.netMinor, egpU.netMinor);
    });

    test('compute() equals breakdown().worth', () async {
      await account('a', 'debit');
      await reported('a', egp, 100, at(1));
      final w = await repo.compute(goldCurrency: egp);
      expect(w.unit('EGP')!.netMinor, 100);
    });

    test(
      'installment of a card with a counted owed is not counted twice',
      () async {
        await account('c', 'bnpl');
        await reported('c', egp, 90000, at(1));
        await RecurringDao(db).insertItem(
          RecurringItemsCompanion.insert(
            id: 'r1',
            kind: 'installment',
            status: 'active',
            name: 'Plan',
            accountId: const Value('c'),
            amountMinor: 30000,
            currency: 'EGP',
            cadence: 'monthly',
            totalCount: const Value(3),
            paidCount: const Value(0),
            createdAt: 1,
          ),
        );
        final b = await repo.breakdown(goldCurrency: egp);
        expect(b.unit('EGP')!.liabilitiesMinor, 90000);
      },
    );
  });
}
