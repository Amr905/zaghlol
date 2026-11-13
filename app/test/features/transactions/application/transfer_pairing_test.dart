// T-089: self-transfer pairing, FX conversions, card settlements. Acceptance
// criteria are named in the test titles. All data synthetic.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/daos/prices_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/daos/transfers_dao.dart';
import 'package:zaghlol/features/transactions/application/bulk_edit.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

const int min = 60 * 1000;

Future<String?> codeOf(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on TransferPairingException catch (e) {
    return e.code;
  } on BulkEditException catch (e) {
    return e.code;
  }
}

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late TransferPairingUseCase uc;
  late DomainEventBus bus;
  late List<DomainEvent> seen;
  var nextId = 0;

  TransferPairingUseCase make() => TransferPairingUseCase(
    db,
    loadSchedule: () async => PaydaySchedule.single(1),
    clock: () =>
        DateTime.fromMillisecondsSinceEpoch(t0 + 60 * min, isUtc: true),
    newId: () => 'p${nextId++}',
    events: bus,
  );

  Future<void> add(
    String id,
    String account, {
    required bool out,
    int minor = 100000,
    String currency = 'EGP',
    int at = 0,
    String status = 'posted',
    String? counterpartyKind,
    String? counterpartyValue,
  }) => TransactionsDao(db).insert(
    txn(
      id,
      accountId: account,
      direction: out ? 'transfer_out' : 'transfer_in',
      amountMinor: minor,
      currency: currency,
      occurredAt: t0 + at,
    ).copyWith(
      status: Value(status),
      counterpartyKind: Value(counterpartyKind),
      counterpartyValue: Value(counterpartyValue),
    ),
  );

  Future<List<Map<String, Object?>>> rows(String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];

  Future<int> spendAndIncome() async {
    final r = await db
        .customSelect(
          'SELECT coalesce(sum(amount_minor), 0) AS s FROM transactions '
          'WHERE deleted_at IS NULL AND is_internal = 0',
        )
        .getSingle();
    return r.read<int>('s');
  }

  Future<int> pairCount() async =>
      (await rows('SELECT id FROM transfer_pairs')).length;

  Future<Map<String, int>> internal() async => {
    for (final r in await rows('SELECT id, is_internal AS i FROM transactions'))
      r['id']! as String: r['i']! as int,
  };

  setUp(() async {
    nextId = 0;
    seen = [];
    bus = DomainEventBus();
    bus.events.listen(seen.add);
    edb = await EncryptedDb.open();
    db = edb.db;
    final accounts = AccountsDao(db);
    await accounts.insert(account('nbe', institution: 'NBE', last4: '1111'));
    await accounts.insert(account('cib', institution: 'CIB', last4: '2222'));
    await accounts.insert(account('cib2', institution: 'CIB', last4: '3333'));
    await accounts.insert(
      account('card', kind: 'credit', institution: 'CIB', last4: '9999'),
    );
    await accounts.insert(
      account(
        'multi',
        kind: 'multi_currency',
        institution: 'WAL',
        last4: '4444',
      ),
    );
    await accounts.insert(
      account('usd', institution: 'USB', last4: '5555', currency: 'USD'),
    );
    uc = make();
  });

  tearDown(() async {
    await bus.dispose();
    await edb.close();
  });

  group('AC1 spec example: -1,000 NBE / +1,000 CIB within 2 min', () {
    test('pairs, both internal, 0 spend, detective trigger, event', () async {
      await add('o', 'nbe', out: true);
      expect((await uc.onPersisted('o')).status, PairingStatus.none);
      expect(await spendAndIncome(), 100000);
      await add('i', 'cib', out: false, at: 2 * min);
      final r = await uc.onPersisted('i');
      expect(r.status, PairingStatus.paired);
      expect(r.pairKind, TransferPairKind.auto);
      expect(await internal(), {'o': 1, 'i': 1});
      expect(await spendAndIncome(), 0);
      final pair = (await rows('SELECT * FROM transfer_pairs')).single;
      expect(pair['out_txn_id'], 'o');
      expect(pair['in_txn_id'], 'i');
      expect(pair['kind'], 'auto');
      expect(
        await rows('SELECT transfer_pair_id AS p FROM transactions'),
        everyElement(containsPair('p', pair['id'])),
      );
      await pumpEventQueue();
      final changed = seen.whereType<TransactionsChanged>().single;
      expect(changed.accountIds, {'nbe', 'cib'});
      expect(changed.cycleKeys, {'2026-11-01'});
      final mascot = seen.whereType<MascotTrigger>().single;
      expect((mascot.pose, mascot.reason), ('detective', 'self_transfer'));
    });

    test('re-running is a no-op (idempotent)', () async {
      await add('o', 'nbe', out: true);
      await add('i', 'cib', out: false);
      await uc.onPersisted('i');
      expect((await uc.onPersisted('i')).status, PairingStatus.skipped);
      expect((await uc.onPersisted('o')).status, PairingStatus.skipped);
      expect(await pairCount(), 1);
    });
  });

  group('AC2 two candidates: no auto-pair', () {
    test('opens one transfer_ambiguous item, nothing internal', () async {
      await add('o1', 'nbe', out: true);
      await add('o2', 'cib2', out: true, at: min);
      await add('i', 'cib', out: false, at: 2 * min);
      expect((await uc.onPersisted('i')).status, PairingStatus.ambiguous);
      expect((await uc.onPersisted('i')).status, PairingStatus.ambiguous);
      expect(await pairCount(), 0);
      expect(await internal(), {'o1': 0, 'o2': 0, 'i': 0});
      final items = await rows('SELECT * FROM review_items');
      expect(items, hasLength(1));
      expect(items.single['kind'], 'transfer_ambiguous');
      expect(items.single['payload'], '{"candidates":["o1","o2"]}');
      expect(await spendAndIncome(), 300000);
    });

    test(
      'a candidate with another candidate of its own is ambiguous',
      () async {
        await add('o', 'nbe', out: true);
        await add('i1', 'cib', out: false);
        await add('i2', 'cib2', out: false, at: min);
        // i2 arrives and sees o, but o could also be i1's: no pairing.
        expect((await uc.onPersisted('i2')).status, PairingStatus.ambiguous);
        expect(await pairCount(), 0);
      },
    );
  });

  group('late arrival and window', () {
    test('income first, transfer later: pairs when the second lands', () async {
      await add('i', 'cib', out: false, at: 4 * min);
      expect((await uc.onPersisted('i')).status, PairingStatus.none);
      await add('o', 'nbe', out: true);
      expect((await uc.onPersisted('o')).status, PairingStatus.paired);
    });

    test('6 minutes apart, other amount, same account: no pair', () async {
      await add('o', 'nbe', out: true);
      await add('i', 'cib', out: false, at: 6 * min);
      await add('i2', 'cib', out: false, minor: 100001);
      await add('i3', 'nbe', out: false);
      for (final id in ['i', 'i2', 'i3']) {
        expect((await uc.onPersisted(id)).status, PairingStatus.none);
      }
      expect(await pairCount(), 0);
    });

    test('declined and soft-deleted legs never pair', () async {
      await add('o', 'nbe', out: true, status: 'declined');
      await add('i', 'cib', out: false);
      expect((await uc.onPersisted('o')).status, PairingStatus.skipped);
      expect((await uc.onPersisted('i')).status, PairingStatus.none);
      await add('o2', 'nbe', out: true);
      await TransactionsDao(db).softDelete('o2', at: t0);
      expect((await uc.onPersisted('i')).status, PairingStatus.none);
      expect(await pairCount(), 0);
    });

    test('an expense is not a transfer leg', () async {
      await TransactionsDao(db).insert(txn('e', accountId: 'nbe'));
      expect((await uc.onPersisted('e')).status, PairingStatus.skipped);
    });
  });

  group('one-sided internal (EC-15) and card settlement', () {
    test(
      'own-account out leg alone is internal; late match completes it',
      () async {
        await add('o', 'nbe', out: true, counterpartyKind: 'own_account');
        final r = await uc.onPersisted('o');
        expect(r.status, PairingStatus.oneSidedInternal);
        expect(await spendAndIncome(), 0);
        expect(
          (await rows('SELECT in_txn_id AS i FROM transfer_pairs')).single['i'],
          isNull,
        );
        await add('i', 'cib', out: false, at: min);
        final r2 = await uc.onPersisted('i');
        expect(r2.status, PairingStatus.paired);
        expect(r2.pairId, r.pairId);
        expect(await pairCount(), 1);
        expect(await internal(), {'o': 1, 'i': 1});
        expect(await spendAndIncome(), 0);
      },
    );

    test(
      'own-account in leg alone is flagged internal without a pair',
      () async {
        await add('i', 'cib', out: false, counterpartyKind: 'own_account');
        expect(
          (await uc.onPersisted('i')).status,
          PairingStatus.oneSidedInternal,
        );
        expect(await pairCount(), 0);
        expect(await internal(), {'i': 1});
      },
    );

    test(
      'cc payment to own card, card-side credit pairs as card_settlement',
      () async {
        await add('pay', 'nbe', out: true, minor: 250000);
        final i = await uc.onPersisted('pay');
        expect(i.status, PairingStatus.none);
        await add('credit', 'card', out: false, minor: 250000, at: 3 * min);
        final r = await uc.onPersisted('credit');
        expect(r.pairKind, TransferPairKind.cardSettlement);
        expect(await spendAndIncome(), 0);
        // No mascot for a card settlement (only the auto kind).
        await pumpEventQueue();
        expect(seen.whereType<MascotTrigger>(), isEmpty);
      },
    );

    test(
      'cc payment alone to a known card last4 is a one-sided settlement',
      () async {
        await add(
          'pay',
          'nbe',
          out: true,
          counterpartyKind: 'own_account',
          counterpartyValue: '9999',
        );
        final r = await uc.onPersisted('pay');
        expect(r.pairKind, TransferPairKind.cardSettlement);
        expect(await spendAndIncome(), 0);
      },
    );
  });

  group('FX conversion and cross-currency', () {
    test('two legs in one multi-currency account: fx_conversion', () async {
      await add('o', 'multi', out: true, currency: 'USD', minor: 10000);
      await add('i', 'multi', out: false, minor: 485000, at: min);
      final r = await uc.onPersisted('i');
      expect(r.pairKind, TransferPairKind.fxConversion);
      expect(await internal(), {'o': 1, 'i': 1});
      // Amounts and currencies untouched.
      final amounts = await rows(
        'SELECT amount_minor AS a, currency AS c FROM transactions ORDER BY id',
      );
      expect(amounts.map((e) => (e['a'], e['c'])), [
        (485000, 'EGP'),
        (10000, 'USD'),
      ]);
    });

    test(
      'known rate that contradicts the conversion: suggestion only',
      () async {
        await PricesDao(db).upsertRate((
          base: Currency.of('USD'),
          quote: Currency.of('EGP'),
          rateE9: 48500000000,
          asOf: t0,
        ));
        await add('o', 'multi', out: true, currency: 'USD', minor: 10000);
        await add('i', 'multi', out: false, minor: 300000, at: min);
        expect((await uc.onPersisted('i')).status, PairingStatus.suggested);
        expect(await pairCount(), 0);
      },
    );

    test(
      'different accounts, within 3 days and 3%: suggestion, never a pair',
      () async {
        await PricesDao(db).upsertRate((
          base: Currency.of('USD'),
          quote: Currency.of('EGP'),
          rateE9: 48500000000,
          asOf: t0,
        ));
        await add('o', 'usd', out: true, currency: 'USD', minor: 10000);
        await add('i', 'cib', out: false, minor: 472000, at: 2 * 24 * 60 * min);
        expect((await uc.onPersisted('i')).status, PairingStatus.suggested);
        expect((await uc.onPersisted('i')).status, PairingStatus.suggested);
        expect((await uc.onPersisted('o')).status, PairingStatus.suggested);
        expect(await pairCount(), 0);
        expect(await internal(), {'o': 0, 'i': 0});
        final items = await rows('SELECT kind FROM review_items');
        expect(items.map((e) => e['kind']), ['fx_pair_suggestion']);
      },
    );

    test(
      'inverse rate is used; outside 3% or 3 days or no rate: nothing',
      () async {
        await PricesDao(db).upsertRate((
          base: Currency.of('EGP'),
          quote: Currency.of('USD'),
          rateE9: 20618557, // 1 / 48.5
          asOf: t0,
        ));
        await add('o', 'usd', out: true, currency: 'USD', minor: 10000);
        await add('i', 'cib', out: false, minor: 485000, at: min);
        expect((await uc.onPersisted('i')).status, PairingStatus.suggested);

        await add(
          'o2',
          'usd',
          out: true,
          currency: 'USD',
          minor: 10000,
          at: 9 * 24 * 60 * min,
        );
        await add(
          'i2',
          'cib',
          out: false,
          minor: 400000,
          at: 9 * 24 * 60 * min,
        );
        expect((await uc.onPersisted('i2')).status, PairingStatus.none);
      },
    );
  });

  group('manual link and unlink', () {
    test(
      'link pairs unequal amounts, resolves review, unlink clears both',
      () async {
        await add('o1', 'nbe', out: true);
        await add('o2', 'cib2', out: true, at: min);
        await add('i', 'cib', out: false, minor: 99000, at: 2 * min);
        await add('i2', 'cib', out: false, at: 2 * min);
        await uc.onPersisted('i2');
        expect(await rows('SELECT id FROM review_items'), hasLength(1));
        final r = await uc.link('o1', 'i2');
        expect(r.pairKind, TransferPairKind.manual);
        expect(
          (await rows('SELECT resolution AS r FROM review_items')).single['r'],
          'linked',
        );
        expect(await internal(), {'o1': 1, 'o2': 0, 'i': 0, 'i2': 1});
        final ev = await uc.unlink('i2');
        expect(ev, isNotNull);
        expect(await internal(), {'o1': 0, 'o2': 0, 'i': 0, 'i2': 0});
        expect(await pairCount(), 0);
        expect(
          await rows('SELECT transfer_pair_id AS p FROM transactions'),
          everyElement(containsPair('p', null)),
        );
        // Second unlink (another actor) is a no-op.
        expect(await uc.unlink('o1'), isNull);
      },
    );

    test(
      'cross-currency link is kind cross_currency, amounts untouched',
      () async {
        await add('o', 'usd', out: true, currency: 'USD', minor: 10000);
        await add('i', 'cib', out: false, minor: 480000);
        final r = await uc.link('o', 'i');
        expect(r.pairKind, TransferPairKind.crossCurrency);
        expect(await spendAndIncome(), 0);
      },
    );

    test('link refuses bad input and already paired legs', () async {
      await add('o', 'nbe', out: true);
      await add('i', 'cib', out: false);
      await add('i2', 'cib2', out: false);
      await add('o2', 'cib2', out: true);
      expect(await codeOf(uc.link('o', 'o')), 'XFR_INVALID');
      expect(await codeOf(uc.link('i', 'o')), 'XFR_INVALID');
      expect(await codeOf(uc.link('o', 'missing')), 'XFR_NOT_FOUND');
      await uc.link('o', 'i');
      expect(await codeOf(uc.link('o', 'i2')), 'XFR_ALREADY_PAIRED');
      expect(await codeOf(uc.link('o2', 'i')), 'XFR_ALREADY_PAIRED');
      expect(await pairCount(), 1);
      expect(await internal(), containsPair('i2', 0));
    });
  });

  group('two engines at once', () {
    test('both legs evaluated concurrently by two engines: one pair', () async {
      await add('o', 'nbe', out: true);
      await add('i', 'cib', out: false, at: min);
      final other = make();
      final results = await Future.wait([
        uc.onPersisted('o'),
        other.onPersisted('i'),
        uc.onPersisted('i'),
        other.onPersisted('o'),
      ]);
      expect(await pairCount(), 1);
      expect(
        results.where((r) => r.status == PairingStatus.paired),
        hasLength(1),
      );
      expect(await internal(), {'o': 1, 'i': 1});
      expect(await spendAndIncome(), 0);
    });

    test('concurrent link and auto pair never double-book a leg', () async {
      await add('o', 'nbe', out: true);
      await add('i', 'cib', out: false);
      await add('i2', 'cib2', out: false, minor: 99000);
      final other = make();
      final futures = <Future<Object?>>[
        uc.onPersisted('o'),
        codeOf(other.link('o', 'i2')),
      ];
      await Future.wait(futures);
      expect(await pairCount(), 1);
      final pair = (await rows('SELECT * FROM transfer_pairs')).single;
      final internalIds = {
        for (final e in (await internal()).entries)
          if (e.value == 1) e.key,
      };
      expect(internalIds, {pair['out_txn_id'], pair['in_txn_id']});
    });
  });

  group('FU-110 linked expenses and FU-114 77-3', () {
    test(
      'event includes the cycle of an expense the leg is linked to',
      () async {
        await TransactionsDao(db).insert(
          txn(
            'e',
            accountId: 'nbe',
            amountMinor: 50000,
            occurredAt: t0 - 20 * 24 * 60 * min,
          ),
        );
        await add('o', 'nbe', out: true);
        await add('i', 'cib', out: false, at: min);
        await OffsetLinksDao(db)
            .insert(link('l', expense: 'e', source: 'i', amountMinor: 50000));
        await uc.onPersisted('i');
        await pumpEventQueue();
        final changed = seen.whereType<TransactionsChanged>().single;
        expect(changed.cycleKeys, {'2026-11-01', '2026-10-01'});
      },
    );

    test(
      'moving a paired leg to another account is refused, nothing changes',
      () async {
        await add('o', 'nbe', out: true);
        await add('i', 'cib', out: false);
        await add('free', 'nbe', out: true, minor: 5);
        await uc.onPersisted('i');
        final bulk = BulkEditUseCase(db);
        expect(
          await codeOf(bulk.apply({'o', 'free'}, const SetAccount('cib2'))),
          'BULK_PAIRED',
        );
        final accs = await rows('SELECT id, account_id AS a FROM transactions');
        expect(
          {for (final r in accs) r['id']: r['a']},
          {'o': 'nbe', 'i': 'cib', 'free': 'nbe'},
        );
        // A free leg still moves.
        await bulk.apply({'free'}, const SetAccount('cib2'));
      },
    );
  });
}
