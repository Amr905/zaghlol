// T-266: a debit card linked to its bank account (US-P05). The ledger
// (linked card purchase lowers the account once; an SMS balance on the card
// lands on the account; unlink keeps history and the account's figure), the
// repository guards, merge and retype rules, and transfer pairing (a card and
// its own account are never a transfer). In-memory database, synthetic data.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart' as keys;
import 'package:zaghlol/features/accounts/data/drift_accounts_repository.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol/features/wealth/data/net_worth_repository.dart';
import 'package:zaghlol/features/wealth/data/prices_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

final egp = Currency.of('EGP');
const int hour = 3600 * 1000;

Future<String?> codeOf(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on AccountsException catch (e) {
    return e.code;
  } on TransferPairingException catch (e) {
    return e.code;
  }
}

void main() {
  late AppDatabase db;
  late AccountsDao dao;
  late DriftAccountsRepository repo;
  late NetWorthRepository worth;
  var clock = DateTime.fromMillisecondsSinceEpoch(t0 + 100 * hour, isUtc: true);
  var ids = 0;

  setUp(() async {
    ids = 0;
    clock = DateTime.fromMillisecondsSinceEpoch(t0 + 100 * hour, isUtc: true);
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    dao = AccountsDao(db);
    repo = DriftAccountsRepository(
      dao,
      settings: SettingsDao(db),
      clock: () => clock,
      newId: () => 'id${ids++}',
    );
    worth = NetWorthRepository(
      db: db,
      prices: PricesRepository(db: db, clock: () => clock),
      clock: () => clock,
      newId: () => 'n${ids++}',
    );
    // A bank account and its debit card at BNK, a credit card, a wallet and
    // a second bank account elsewhere.
    await dao.insert(account('acc', kind: 'account', last4: null));
    await dao.insert(account('deb', last4: '1234'));
    await dao.insert(account('cc', kind: 'credit', last4: '9999'));
    await dao.insert(
      account('wal', kind: 'wallet', institution: 'WAL', last4: null),
    );
    await dao.insert(
      account('other', kind: 'account', institution: 'OTH', last4: null),
    );
  });
  tearDown(() => db.close());

  var n = 0;
  Future<void> spend(
    String accountId,
    int minor,
    int atHour, {
    String direction = 'expense',
  }) => TransactionsDao(db).insert(
    txn(
      'x${n++}',
      accountId: accountId,
      direction: direction,
      amountMinor: minor,
      occurredAt: t0 + atHour * hour,
    ),
  );

  Future<void> report(String id, int minor, int atHour) => repo.recordBalance(
    accountId: id,
    asOf: DateTime.fromMillisecondsSinceEpoch(t0 + atHour * hour, isUtc: true),
    balance: Money(egp, minor),
  );

  Future<NetWorthBreakdown> breakdown() =>
      worth.breakdown(goldCurrency: egp, includeAssets: false);

  Future<List<BreakdownLine>> linesOf(String id) async => [
    for (final l in (await breakdown()).lines)
      if (l.refId == id) l,
  ];

  Future<int?> amountOf(String id) async {
    final ls = await linesOf(id);
    return ls.isEmpty ? null : ls.single.amount?.minor;
  }

  Future<int> egpAssets() async =>
      (await breakdown()).units.firstWhere((u) => u.unit == 'EGP').assetsMinor;

  Future<OpeningBalances> opening() async {
    final k = keys.Settings.openingBalances;
    return k.parse(await SettingsDao(db).read(k.name));
  }

  group('ledger while linked', () {
    test('a linked card purchase lowers the account balance once; the card '
        'has no line of its own; the total counts it once', () async {
      await report('acc', 1000000, 1);
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      await spend('deb', 25000, 2);
      await spend('acc', 5000, 3);

      expect(await amountOf('acc'), 1000000 - 25000 - 5000);
      expect(await linesOf('deb'), isEmpty);
      expect(await egpAssets(), 1000000 - 25000 - 5000);
      final line = (await linesOf('acc')).single;
      expect(line.source, BalanceSource.computed);
      expect(line.sinceCount, 2);
    });

    test(
      'without the link the same purchase stays on the card (control)',
      () async {
        await report('acc', 1000000, 1);
        await spend('deb', 25000, 2);
        expect(await amountOf('acc'), 1000000);
      },
    );

    test('an SMS balance on the card message lands on the account; the card '
        'gets no row', () async {
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      await spend('deb', 25000, 2);
      expect(
        await repo.recordBalance(
          accountId: 'deb',
          asOf: DateTime.fromMillisecondsSinceEpoch(t0 + 2 * hour, isUtc: true),
          balance: Money(egp, 975000),
        ),
        isTrue,
      );
      expect(await dao.balancesOf('deb'), isEmpty);
      final row = (await dao.balancesOf('acc')).single;
      expect(row.balanceMinor, 975000);
      // The purchase at the message's instant is inside the figure.
      expect(await amountOf('acc'), 975000);
      // An older card message changes nothing.
      expect(
        await repo.recordBalance(
          accountId: 'deb',
          asOf: DateTime.fromMillisecondsSinceEpoch(t0 + hour, isUtc: true),
          balance: Money(egp, 1),
        ),
        isFalse,
      );
      expect((await dao.balancesOf('acc')).single.balanceMinor, 975000);
    });

    test('resolve by (bank, last-4) still finds the card', () async {
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      final r = await repo.resolve(
        AccountHint(
          institutionCode: 'BNK',
          last4: '١٢٣٤',
          currency: egp,
          label: 'x',
        ),
      );
      expect(r.created, isFalse);
      expect(r.account.id, 'deb');
      expect(r.account.linkedAccountId, 'acc');
    });

    test('totalsByCurrency never counts a linked card', () async {
      // A row on the card written before linking moves to the account.
      await report('deb', 700000, 1);
      await report('acc', 1000000, 2);
      expect((await repo.totalsByCurrency())[egp]!.minor, 1700000);
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      expect((await repo.totalsByCurrency())[egp]!.minor, 1000000);
    });
  });

  group('link', () {
    test('moves the card balances to the account, newer wins', () async {
      await report('acc', 1000000, 1);
      await report('deb', 900000, 3); // newer: the account's figure now
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      expect(await dao.balancesOf('deb'), isEmpty);
      expect((await dao.balancesOf('acc')).single.balanceMinor, 900000);
    });

    test(
      'an older card balance is dropped, the account keeps its own',
      () async {
        await report('deb', 900000, 1);
        await report('acc', 1000000, 3);
        await repo.linkCard(cardId: 'deb', accountId: 'acc');
        expect(await dao.balancesOf('deb'), isEmpty);
        expect((await dao.balancesOf('acc')).single.balanceMinor, 1000000);
      },
    );

    test('typed balances of the card move with the merge rule', () async {
      final k = keys.Settings.openingBalances;
      await SettingsDao(db).write(
        k.name,
        k.format(
          OpeningBalances.empty.withEntry(
            'deb',
            Money(egp, 4200),
            DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true),
          ),
        ),
        at: 1,
      );
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      final o = await opening();
      expect(o.forAccount('deb'), isEmpty);
      expect(o.of('acc', 'EGP')!.amount.minor, 4200);
    });

    test('guards: only a debit card, only to an account / wallet / '
        'multi-currency, never itself; nothing changes on refusal', () async {
      expect(
        await codeOf(repo.linkCard(cardId: 'cc', accountId: 'acc')),
        AccountsException.notLinkable,
      );
      expect(
        await codeOf(repo.linkCard(cardId: 'deb', accountId: 'cc')),
        AccountsException.notLinkable,
      );
      expect(
        await codeOf(repo.linkCard(cardId: 'deb', accountId: 'deb')),
        AccountsException.notLinkable,
      );
      expect(
        await codeOf(repo.linkCard(cardId: 'acc', accountId: 'wal')),
        AccountsException.notLinkable,
      );
      expect(
        await codeOf(repo.linkCard(cardId: 'deb', accountId: 'nope')),
        AccountsException.notFound,
      );
      expect((await dao.byId('deb'))!.linkedAccountId, isNull);
      // A wallet can hold a card.
      await repo.linkCard(cardId: 'deb', accountId: 'wal');
      expect((await dao.byId('deb'))!.linkedAccountId, 'wal');
    });

    test('a merged account is refused as a target', () async {
      await repo.merge(sourceId: 'other', targetId: 'acc');
      expect(
        await codeOf(repo.linkCard(cardId: 'deb', accountId: 'other')),
        AccountsException.merged,
      );
    });

    test('linking to another account unlinks first (re-anchoring the old '
        'one) and links again', () async {
      await report('acc', 1000000, 1);
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      await spend('deb', 25000, 2);
      await repo.linkCard(cardId: 'deb', accountId: 'other');
      expect((await dao.byId('deb'))!.linkedAccountId, 'other');
      expect(await amountOf('acc'), 975000);
    });
  });

  group('unlink', () {
    test('keeps history and the account figure; the card counts on its own '
        'again from that moment, its balance unknown', () async {
      await report('acc', 1000000, 1);
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      await spend('deb', 25000, 2);
      expect(await amountOf('acc'), 975000);

      clock = DateTime.fromMillisecondsSinceEpoch(t0 + 10 * hour, isUtc: true);
      final card = await repo.unlinkCard('deb');
      expect(card.linkedAccountId, isNull);
      // Same figure right after unlink; now a typed balance as of now.
      expect(await amountOf('acc'), 975000);
      final o = (await opening()).of('acc', 'EGP')!;
      expect(o.amount.minor, 975000);
      expect(o.asOf, clock);
      // History stays on the card.
      final rows = await db
          .customSelect("SELECT id FROM transactions WHERE account_id = 'deb'")
          .get();
      expect(rows, hasLength(1));
      // The card is listed again, balance unknown.
      final line = (await linesOf('deb')).single;
      expect(line.source, BalanceSource.unknown);

      // A later card purchase no longer touches the account.
      await spend('deb', 1000, 11);
      expect(await amountOf('acc'), 975000);
      // A later card message is the card's own.
      await report('deb', 500000, 12);
      expect(await amountOf('deb'), 500000);
      expect(await amountOf('acc'), 975000);
    });

    test('nothing counted from the card since the anchor: no typed balance '
        'is written', () async {
      await report('acc', 1000000, 5);
      await spend('deb', 25000, 2); // before the anchor
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      await repo.unlinkCard('deb');
      expect((await opening()).of('acc', 'EGP'), isNull);
      expect(await amountOf('acc'), 1000000);
    });

    test('an unlinked card is returned unchanged', () async {
      final a = await repo.unlinkCard('deb');
      expect(a.linkedAccountId, isNull);
      expect((await opening()).length, 0);
    });
  });

  group('retype and merge', () {
    test('a linked card can not be retyped to credit, nor its account to a '
        'card kind: ACC_LINKED, nothing changes', () async {
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      expect(
        await codeOf(
          repo.update('deb', const AccountEdit(kind: AccountKind.credit)),
        ),
        AccountsException.linked,
      );
      expect(
        await codeOf(
          repo.update('acc', const AccountEdit(kind: AccountKind.credit)),
        ),
        AccountsException.linked,
      );
      expect((await dao.byId('deb'))!.kind, 'debit');
      expect((await dao.byId('acc'))!.kind, 'account');
      // A rename is fine.
      await repo.update('deb', const AccountEdit(label: 'Mine'));
      expect((await dao.byId('deb'))!.linkedAccountId, 'acc');
    });

    test('merging the account into another account moves its cards', () async {
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      await repo.merge(sourceId: 'acc', targetId: 'other');
      expect((await dao.byId('deb'))!.linkedAccountId, 'other');
    });

    test('merging the account into a card unlinks its cards', () async {
      await dao.insert(account('deb2', last4: '5678'));
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      await repo.merge(sourceId: 'acc', targetId: 'deb2');
      expect((await dao.byId('deb'))!.linkedAccountId, isNull);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });

    test(
      'a linked card merged into another card leaves no link behind',
      () async {
        await dao.insert(account('deb2', last4: '5678'));
        await repo.linkCard(cardId: 'deb', accountId: 'acc');
        await repo.merge(sourceId: 'deb', targetId: 'deb2');
        expect((await dao.byId('deb'))!.linkedAccountId, isNull);
        expect(await repo.cardsLinkedTo('acc'), isEmpty);
      },
    );
  });

  group('merge that ends a link keeps the figures (M1)', () {
    test('(a) a linked card merged into another card: the account keeps its '
        'figure, the card spend moves with the card', () async {
      await dao.insert(account('deb2', last4: '5678'));
      await report('acc', 1000000, 1);
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      await spend('deb', 50000, 2);
      expect(await amountOf('acc'), 950000);

      clock = DateTime.fromMillisecondsSinceEpoch(t0 + 10 * hour, isUtc: true);
      await repo.merge(sourceId: 'deb', targetId: 'deb2');
      expect(await amountOf('acc'), 950000);
      expect((await opening()).of('acc', 'EGP')!.asOf, clock);
      expect((await dao.byId('deb'))!.linkedAccountId, isNull);
      // A later purchase on the merged card no longer touches the account.
      await spend('deb2', 1000, 11);
      expect(await amountOf('acc'), 950000);
    });

    test('(a) control: a linked card merged into its own account keeps the '
        'figure without a new anchor', () async {
      await report('acc', 1000000, 1);
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      await spend('deb', 50000, 2);
      await repo.merge(sourceId: 'deb', targetId: 'acc');
      expect(await amountOf('acc'), 950000);
      expect((await opening()).of('acc', 'EGP'), isNull);
    });

    test('(b) an account with a linked card merged into a card: the target '
        'shows the account figure, the card counts on its own', () async {
      await dao.insert(account('deb2', last4: '5678'));
      await report('acc', 1000000, 1);
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      await spend('deb', 50000, 2);
      await spend('acc', 10000, 3);
      expect(await amountOf('acc'), 940000);

      clock = DateTime.fromMillisecondsSinceEpoch(t0 + 10 * hour, isUtc: true);
      await repo.merge(sourceId: 'acc', targetId: 'deb2');
      expect(await amountOf('deb2'), 940000);
      expect((await dao.byId('deb'))!.linkedAccountId, isNull);
      expect(await egpAssets(), 940000);
      await spend('deb', 1000, 11);
      expect(await amountOf('deb2'), 940000);
    });

    test('(c) merging into a linked card is refused: ACC_LINKED, nothing '
        'moves', () async {
      await report('other', 300000, 1);
      await report('acc', 1000000, 1);
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      await spend('other', 5000, 2);
      expect(
        await codeOf(repo.merge(sourceId: 'other', targetId: 'deb')),
        AccountsException.linked,
      );
      expect((await dao.byId('other'))!.mergedIntoId, isNull);
      expect(await amountOf('other'), 295000);
      expect(await amountOf('acc'), 1000000);
      expect(await linesOf('deb'), isEmpty);
    });
  });

  test('cardsLinkedTo and linkTargets', () async {
    await dao.insert(account('acc2', kind: 'account', last4: null));
    await report('acc2', 300000, 1);
    await report('deb', 300000, 2);
    final targets = await repo.linkTargets('deb');
    // Same bank and same balance first, then same bank, then the rest.
    expect(
      [for (final t in targets) t.account.id],
      ['acc2', 'acc', 'other', 'wal'],
    );
    expect(targets.first.sameBalance, isTrue);
    expect(targets[1].isSuggestion, isTrue);
    expect(targets[2].isSuggestion, isFalse);
    expect(await repo.linkTargets('cc'), isEmpty);

    await repo.linkCard(cardId: 'deb', accountId: 'acc');
    expect([for (final c in await repo.cardsLinkedTo('acc')) c.id], ['deb']);
  });

  group('transfers', () {
    late TransferPairingUseCase uc;
    var p = 0;
    setUp(() {
      uc = TransferPairingUseCase(
        db,
        loadSchedule: () async => PaydaySchedule.single(1),
        clock: () => clock,
        newId: () => 'p${p++}',
      );
    });

    Future<void> leg(String id, String accountId, {required bool out}) =>
        TransactionsDao(db).insert(
          txn(
            id,
            accountId: accountId,
            direction: out ? 'transfer_out' : 'transfer_in',
            amountMinor: 50000,
            occurredAt: t0 + hour,
          ),
        );

    test('a card leg and its own account leg never auto-pair', () async {
      await repo.linkCard(cardId: 'deb', accountId: 'acc');
      await leg('o', 'deb', out: true);
      await leg('i', 'acc', out: false);
      final r = await uc.onPersisted('i');
      expect(r.status, isNot(PairingStatus.paired));
      expect(
        await db.customSelect('SELECT id FROM transfer_pairs').get(),
        isEmpty,
      );
      // ... and the user can't link them by hand either.
      expect(await codeOf(uc.link('o', 'i')), TransferPairingException.invalid);
    });

    test('control: unlinked, the same legs pair', () async {
      await leg('o', 'deb', out: true);
      await leg('i', 'acc', out: false);
      final r = await uc.onPersisted('i');
      expect(r.status, PairingStatus.paired);
    });
  });
}
