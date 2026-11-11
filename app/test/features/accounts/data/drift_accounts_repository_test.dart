// T-045: the accounts repository on an encrypted database (FR-ACC-01…06).
// Acceptance criteria are named in the test titles. All data synthetic.

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/db_errors.dart';
import 'package:zaghlol/features/accounts/data/accounts_providers.dart';
import 'package:zaghlol/features/accounts/data/drift_accounts_repository.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

const String sentinel = 'T045SENTINEL';
final Currency egp = Currency.of('EGP');
final Currency usd = Currency.of('USD');
final Currency kwd = Currency.of('KWD');

Money egpMinor(int m) => Money(egp, m);

DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

AccountHint hint({
  String institution = 'BNK',
  String? last4 = '1234',
  Currency? currency,
  String label = 'Synthetic card',
  AccountKind? kind,
}) => AccountHint(
  institutionCode: institution,
  last4: last4,
  currency: currency ?? egp,
  label: label,
  kind: kind,
);

Future<String?> accCode(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on AccountsException catch (e) {
    return e.code;
  }
}

void main() {
  late EncryptedDb edb;
  late AccountsDao dao;
  late DriftAccountsRepository repo;
  var clockMs = t0 + 1000;
  var nextId = 0;

  DriftAccountsRepository makeRepo() => DriftAccountsRepository(
    dao,
    clock: () => at(clockMs),
    newId: () => 'gen${nextId++}',
  );

  Future<int> accountCount() async => (await edb.db
      .customSelect('SELECT COUNT(*) AS c FROM accounts')
      .getSingle()
      .then((r) => r.read<int>('c')));

  setUp(() async {
    clockMs = t0 + 1000;
    nextId = 0;
    edb = await EncryptedDb.open();
    dao = AccountsDao(edb.db);
    repo = makeRepo();
  });

  tearDown(() => edb.close());

  group('resolve (FR-ACC-01)', () {
    test('creates on first sight, then finds the same account', () async {
      final a = await repo.resolve(hint());
      expect(a.created, isTrue);
      expect(a.account.institutionCode, 'BNK');
      expect(a.account.last4, '1234');
      expect(a.account.defaultCurrency, egp);
      expect(a.account.kind, AccountKind.account);
      expect(a.account.createdAt, at(t0 + 1000));
      final b = await repo.resolve(hint(label: 'Other label'));
      expect(b.created, isFalse);
      expect(b.account.id, a.account.id);
      expect(b.account.label, 'Synthetic card');
      expect(await accountCount(), 1);
    });

    test('same inst+last4 never creates two accounts, 20 concurrent callers '
        '(two repositories, ONE connection)', () async {
      final other = makeRepo();
      final results = await Future.wait([
        for (var i = 0; i < 20; i++) (i.isEven ? repo : other).resolve(hint()),
      ]);
      expect(results.where((r) => r.created), hasLength(1));
      expect({for (final r in results) r.account.id}, hasLength(1));
      expect(await accountCount(), 1);
    });

    test('the same last-4 at another institution is another account', () async {
      final a = await repo.resolve(hint());
      final b = await repo.resolve(hint(institution: 'WAL'));
      expect(b.account.id, isNot(a.account.id));
      expect(b.created, isTrue);
    });

    test('Arabic-Indic last-4 matches the Latin-digit account', () async {
      final a = await repo.resolve(hint(last4: '1234'));
      final b = await repo.resolve(hint(last4: '١٢٣٤'));
      final c = await repo.resolve(hint(last4: '۱۲۳۴'));
      expect(b.account.id, a.account.id);
      expect(c.account.id, a.account.id);
      expect(b.created, isFalse);
      final d = await repo.resolve(hint(institution: 'WAL', last4: '٠٠٩٩'));
      expect(d.account.last4, '0099');
    });

    test(
      'a blank last-4 is institution-only; concurrent callers agree',
      () async {
        final other = makeRepo();
        final results = await Future.wait([
          for (var i = 0; i < 10; i++)
            (i.isEven ? repo : other).resolve(
              hint(institution: 'WAL', last4: i.isEven ? null : '  '),
            ),
        ]);
        expect(results.where((r) => r.created), hasLength(1));
        expect({for (final r in results) r.account.id}, {'inst:WAL'});
        expect(results.first.account.last4, isNull);
      },
    );

    test(
      'an institution-only account is found when it was made another way',
      () async {
        await dao.insert(account('manual', institution: 'WAL', last4: null));
        final r = await repo.resolve(hint(institution: 'WAL', last4: null));
        expect(r.created, isFalse);
        expect(r.account.id, 'manual');
      },
    );

    test(
      'explicit kind is stored; label is trimmed and cut to 30 chars',
      () async {
        final r = await repo.resolve(
          hint(kind: AccountKind.credit, label: '  ${'ب' * 40}  '),
        );
        expect(r.account.kind, AccountKind.credit);
        expect(r.account.label, 'ب' * 30);
      },
    );

    test('a merged-away card resolves to its merge target, not a new '
        'account', () async {
      final a = (await repo.resolve(hint(last4: '1111'))).account;
      final b = (await repo.resolve(hint(last4: '2222'))).account;
      await repo.merge(sourceId: a.id, targetId: b.id);
      final r = await repo.resolve(hint(last4: '1111'));
      expect(r.created, isFalse);
      expect(r.account.id, b.id);
      expect(await accountCount(), 2);
    });

    test('invalid input fails before SQL with a code only', () async {
      for (final h in [
        hint(institution: ' '),
        hint(institution: 'X' * 33),
        hint(last4: '1'),
        hint(last4: '12345'),
        hint(last4: '12a4'),
        hint(label: '  '),
      ]) {
        expect(await accCode(repo.resolve(h)), AccountsException.invalid);
      }
      expect(await accountCount(), 0);
    });
  });

  group('default cash (FR-ACC-03)', () {
    test(
      'exactly one default cash, 20 concurrent callers, one connection',
      () async {
        final other = makeRepo();
        final all = await Future.wait([
          for (var i = 0; i < 20; i++)
            (i.isEven ? repo : other).ensureDefaultCash(
              currency: egp,
              label: 'Cash $i',
            ),
        ]);
        expect({for (final a in all) a.id}, hasLength(1));
        final one = all.first;
        expect(one.kind, AccountKind.cash);
        expect(one.isDefaultCash, isTrue);
        expect(one.institutionCode, isNull);
        final rows = await edb.db
            .customSelect(
              'SELECT COUNT(*) AS c FROM accounts '
              'WHERE is_default_cash = 1',
            )
            .getSingle();
        expect(rows.read<int>('c'), 1);
      },
    );

    test('a later call returns the same account unchanged', () async {
      final a = await repo.ensureDefaultCash(currency: egp, label: 'Cash');
      final b = await repo.ensureDefaultCash(currency: usd, label: 'Other');
      expect(b.id, a.id);
      expect(b.defaultCurrency, egp);
      expect(b.label, 'Cash');
    });

    test('cannot be merged away or retyped; can be a merge target', () async {
      final cash = await repo.ensureDefaultCash(currency: egp, label: 'Cash');
      final card = (await repo.resolve(hint())).account;
      expect(
        await accCode(repo.merge(sourceId: cash.id, targetId: card.id)),
        AccountsException.defaultCash,
      );
      expect(
        await accCode(
          repo.update(cash.id, const AccountEdit(kind: AccountKind.wallet)),
        ),
        AccountsException.defaultCash,
      );
      final merged = await repo.merge(sourceId: card.id, targetId: cash.id);
      expect(merged.id, cash.id);
      expect(merged.isDefaultCash, isTrue);
    });
  });

  group('balances (FR-ACC-02, FR-ACC-06)', () {
    late String accId;
    setUp(() async {
      accId = (await repo.resolve(hint())).account.id;
    });

    test(
      'stores balance and available, in the amounts\' own currency',
      () async {
        expect(
          await repo.recordBalance(
            accountId: accId,
            asOf: at(t0),
            balance: egpMinor(150000),
            available: egpMinor(120000),
          ),
          isTrue,
        );
        final b = (await repo.balancesOf(accId)).single;
        expect(b.currency, egp);
        expect(b.balance, egpMinor(150000));
        expect(b.available, egpMinor(120000));
        expect(b.asOf, at(t0));
      },
    );

    test('older message does not overwrite a newer balance', () async {
      await repo.recordBalance(
        accountId: accId,
        asOf: at(t0 + 5000),
        balance: egpMinor(100),
      );
      final applied = await repo.recordBalance(
        accountId: accId,
        asOf: at(t0 + 4999),
        balance: egpMinor(999),
        available: egpMinor(999),
      );
      expect(applied, isFalse);
      final b = (await repo.balancesOf(accId)).single;
      expect(b.balance, egpMinor(100));
      expect(b.available, isNull);
      expect(b.asOf, at(t0 + 5000));
    });

    test('newer and equal-time messages replace', () async {
      await repo.recordBalance(
        accountId: accId,
        asOf: at(t0),
        balance: egpMinor(100),
      );
      expect(
        await repo.recordBalance(
          accountId: accId,
          asOf: at(t0),
          balance: egpMinor(200),
        ),
        isTrue,
      );
      expect(
        await repo.recordBalance(
          accountId: accId,
          asOf: at(t0 + 1),
          available: egpMinor(300),
        ),
        isTrue,
      );
      final b = (await repo.balancesOf(accId)).single;
      expect(b.balance, isNull); // replaced as given
      expect(b.available, egpMinor(300));
    });

    test(
      'concurrent writers (one connection): the newest as_of wins in any order',
      () async {
        final other = makeRepo();
        await Future.wait([
          for (var i = 9; i >= 0; i--)
            (i.isEven ? repo : other).recordBalance(
              accountId: accId,
              asOf: at(t0 + i),
              balance: egpMinor(i),
            ),
        ]);
        final b = (await repo.balancesOf(accId)).single;
        expect(b.asOf, at(t0 + 9));
        expect(b.balance, egpMinor(9));
      },
    );

    test(
      'one row per currency; currencies are never mixed or summed',
      () async {
        final wise = (await repo.resolve(
          hint(
            institution: 'WSE',
            last4: '5555',
            kind: AccountKind.multiCurrency,
          ),
        )).account;
        await repo.recordBalance(
          accountId: wise.id,
          asOf: at(t0),
          balance: Money(usd, 120000),
        );
        await repo.recordBalance(
          accountId: wise.id,
          asOf: at(t0),
          balance: egpMinor(500000),
        );
        await repo.recordBalance(
          accountId: wise.id,
          asOf: at(t0),
          balance: Money(kwd, 1234),
        );
        // An older EGP message must not touch the USD row, nor a newer one.
        await repo.recordBalance(
          accountId: wise.id,
          asOf: at(t0 - 1),
          balance: egpMinor(1),
        );
        final rows = await repo.balancesOf(wise.id);
        expect([for (final r in rows) r.currency.code], ['EGP', 'KWD', 'USD']);
        expect(rows[0].balance, egpMinor(500000));
        expect(rows[1].balance, Money(kwd, 1234));
        expect(rows[2].balance, Money(usd, 120000));
      },
    );

    test(
      'mixed currencies or no amount are invalid; nothing is stored',
      () async {
        expect(
          await accCode(
            repo.recordBalance(
              accountId: accId,
              asOf: at(t0),
              balance: egpMinor(1),
              available: Money(usd, 1),
            ),
          ),
          AccountsException.invalid,
        );
        expect(
          await accCode(repo.recordBalance(accountId: accId, asOf: at(t0))),
          AccountsException.invalid,
        );
        expect(await repo.balancesOf(accId), isEmpty);
      },
    );

    test('missing and merged accounts are refused with a code', () async {
      expect(
        await accCode(
          repo.recordBalance(
            accountId: 'nope',
            asOf: at(t0),
            balance: egpMinor(1),
          ),
        ),
        AccountsException.notFound,
      );
      final other = (await repo.resolve(hint(last4: '9999'))).account;
      await repo.merge(sourceId: other.id, targetId: accId);
      expect(
        await accCode(
          repo.recordBalance(
            accountId: other.id,
            asOf: at(t0),
            balance: egpMinor(1),
          ),
        ),
        AccountsException.merged,
      );
      expect(await repo.balancesOf(other.id), isEmpty);
    });

    test('totalsByCurrency sums per currency over asset accounts only, '
        'hidden included', () async {
      final b = (await repo.resolve(hint(last4: '2222'))).account;
      final card = (await repo.resolve(
        hint(last4: '3333', kind: AccountKind.credit),
      )).account;
      final usdAcc = (await repo.resolve(hint(last4: '4444', currency: usd)))
          .account;
      await repo.recordBalance(
        accountId: accId,
        asOf: at(t0),
        balance: egpMinor(1000),
      );
      await repo.recordBalance(
        accountId: b.id,
        asOf: at(t0),
        balance: egpMinor(-250),
      );
      await repo.recordBalance(
        accountId: card.id,
        asOf: at(t0),
        balance: egpMinor(777),
      );
      await repo.recordBalance(
        accountId: usdAcc.id,
        asOf: at(t0),
        balance: Money(usd, 5),
      );
      await repo.recordBalance(
        accountId: usdAcc.id,
        asOf: at(t0),
        balance: egpMinor(10),
      );
      await repo.setHidden(b.id, hidden: true);
      final totals = await repo.totalsByCurrency();
      expect(totals[egp], egpMinor(1000 - 250 + 10));
      expect(totals[usd], Money(usd, 5));
      expect(totals, hasLength(2));
    });

    test('listWithBalances groups rows by account and skips merged', () async {
      final b = (await repo.resolve(hint(last4: '2222'))).account;
      await repo.recordBalance(
        accountId: b.id,
        asOf: at(t0),
        balance: Money(usd, 5),
      );
      await repo.recordBalance(
        accountId: b.id,
        asOf: at(t0),
        balance: egpMinor(7),
      );
      final list = await repo.listWithBalances();
      expect(list.map((e) => e.account.id), [accId, b.id]);
      expect(list[0].balances, isEmpty);
      expect(list[1].balances, hasLength(2));
      await repo.merge(sourceId: b.id, targetId: accId);
      final after = await repo.listWithBalances();
      expect(after, hasLength(1));
      expect(after.single.balances, hasLength(2));
    });
  });

  group('merge and hide (FR-ACC-04, D-69)', () {
    late Account a;
    late Account b;
    final txns = <TransactionsDao>[];
    setUp(() async {
      a = (await repo.resolve(hint(last4: '1111'))).account;
      b = (await repo.resolve(hint(last4: '2222'))).account;
      txns
        ..clear()
        ..add(TransactionsDao(edb.db));
    });

    Future<List<String>> txnIdsOf(String accountId) async => [
      for (final r
          in await edb.db
              .customSelect(
                'SELECT id FROM transactions WHERE account_id = ? ORDER BY id',
                variables: [Variable.withString(accountId)],
              )
              .get())
        r.read<String>('id'),
    ];

    test('merge moves all transactions, soft-deleted ones too', () async {
      final t = txns.single;
      await t.insert(txn('t1', accountId: a.id));
      await t.insert(txn('t2', accountId: a.id, currency: 'USD'));
      await t.insert(txn('t3', accountId: a.id));
      await t.insert(txn('t4', accountId: b.id));
      await t.softDelete('t3', at: t0);
      clockMs = t0 + 9000;
      final target = await repo.merge(sourceId: a.id, targetId: b.id);
      expect(target.id, b.id);
      expect(await txnIdsOf(a.id), isEmpty);
      expect(await txnIdsOf(b.id), ['t1', 't2', 't3', 't4']);
      final moved = await t.byId('t3');
      expect(moved!.deletedAt, t0); // still restorable
      expect(moved.updatedAt, t0 + 9000);
      final src = await repo.byId(a.id);
      expect(src!.mergedIntoId, b.id);
      expect(src.isMerged, isTrue);
      expect((await repo.list()).map((x) => x.id), [b.id]);
    });

    test('merge re-links recurring items', () async {
      await edb.db.customStatement(
        'INSERT INTO recurring_items (id, kind, status, name, account_id, '
        'amount_minor, currency, cadence, created_at) VALUES '
        "('r1', 'bill', 'active', 'Synthetic bill', ?, 100, 'EGP', "
        "'monthly', $t0)",
        [a.id],
      );
      await repo.merge(sourceId: a.id, targetId: b.id);
      final r = await edb.db
          .customSelect("SELECT account_id FROM recurring_items WHERE id='r1'")
          .getSingle();
      expect(r.read<String>('account_id'), b.id);
    });

    test(
      'balances move per currency; the newer row wins; never summed',
      () async {
        await repo.recordBalance(
          accountId: a.id,
          asOf: at(t0 + 10),
          balance: egpMinor(500),
        );
        await repo.recordBalance(
          accountId: a.id,
          asOf: at(t0 + 10),
          balance: Money(usd, 9),
        );
        await repo.recordBalance(
          accountId: a.id,
          asOf: at(t0 + 10),
          balance: Money(kwd, 3),
        );
        await repo.recordBalance(
          accountId: b.id,
          asOf: at(t0 + 20), // newer than a's EGP
          balance: egpMinor(70),
        );
        await repo.recordBalance(
          accountId: b.id,
          asOf: at(t0 + 5), // older than a's USD
          balance: Money(usd, 1),
        );
        await repo.merge(sourceId: a.id, targetId: b.id);
        final rows = await repo.balancesOf(b.id);
        final by = {for (final r in rows) r.currency.code: r};
        expect(by['EGP']!.balance, egpMinor(70));
        expect(by['USD']!.balance, Money(usd, 9));
        expect(by['KWD']!.balance, Money(kwd, 3));
        expect(await repo.balancesOf(a.id), isEmpty);
      },
    );

    test(
      'accounts already merged into the source follow to the target',
      () async {
        final c = (await repo.resolve(hint(last4: '3333'))).account;
        await repo.merge(sourceId: c.id, targetId: a.id);
        await repo.merge(sourceId: a.id, targetId: b.id);
        expect((await repo.byId(c.id))!.mergedIntoId, b.id);
        expect((await repo.resolve(hint(last4: '3333'))).account.id, b.id);
      },
    );

    test('refusals leave everything untouched', () async {
      final t = txns.single;
      await t.insert(txn('t1', accountId: a.id));
      expect(
        await accCode(repo.merge(sourceId: a.id, targetId: a.id)),
        AccountsException.invalid,
      );
      expect(
        await accCode(repo.merge(sourceId: a.id, targetId: 'nope')),
        AccountsException.notFound,
      );
      expect(
        await accCode(repo.merge(sourceId: 'nope', targetId: a.id)),
        AccountsException.notFound,
      );
      await repo.merge(sourceId: a.id, targetId: b.id);
      expect(
        await accCode(repo.merge(sourceId: a.id, targetId: b.id)),
        AccountsException.merged,
      );
      final c = (await repo.resolve(hint(last4: '3333'))).account;
      expect(
        await accCode(repo.merge(sourceId: c.id, targetId: a.id)),
        AccountsException.merged,
      );
      expect((await repo.byId(c.id))!.isMerged, isFalse);
      expect(await txnIdsOf(b.id), ['t1']);
    });

    test(
      'hidden accounts leave lists but their transactions still count',
      () async {
        final t = txns.single;
        await t.insert(txn('t1', accountId: a.id, amountMinor: 700));
        final hidden = await repo.setHidden(a.id, hidden: true);
        expect(hidden.isHidden, isTrue);
        expect((await repo.list()).map((x) => x.id), [b.id]);
        expect((await repo.list(includeHidden: true)).map((x) => x.id), [
          a.id,
          b.id,
        ]);
        expect((await repo.listWithBalances()).map((x) => x.account.id), [
          b.id,
        ]);
        final sum = await edb.db
            .customSelect('SELECT SUM(amount_minor) AS s FROM transactions')
            .getSingle();
        expect(sum.read<int>('s'), 700);
        expect((await repo.setHidden(a.id, hidden: false)).isHidden, isFalse);
        expect((await repo.list()).map((x) => x.id), [a.id, b.id]);
      },
    );
  });

  group('update (FR-ACC-01, FR-ACC-05)', () {
    late Account a;
    setUp(() async {
      a = (await repo.resolve(hint())).account;
    });

    test('rename, set type, credit limit and due day', () async {
      clockMs = t0 + 5000;
      final u = await repo.update(
        a.id,
        AccountEdit(
          label: '  My card ',
          kind: AccountKind.credit,
          creditLimit: egpMinor(5000000),
          statementDueDay: 31,
        ),
      );
      expect(u.label, 'My card');
      expect(u.kind, AccountKind.credit);
      expect(u.creditLimit, egpMinor(5000000));
      expect(u.statementDueDay, 31);
      expect(u.updatedAt, at(t0 + 5000));
    });

    test('invalid edits are refused with a code and change nothing', () async {
      for (final e in [
        const AccountEdit(label: ' '),
        const AccountEdit(statementDueDay: 0),
        const AccountEdit(statementDueDay: 32),
        AccountEdit(creditLimit: egpMinor(-1)),
        AccountEdit(creditLimit: Money(usd, 5)),
      ]) {
        expect(await accCode(repo.update(a.id, e)), AccountsException.invalid);
      }
      expect(
        await accCode(repo.update('nope', const AccountEdit())),
        AccountsException.notFound,
      );
      final after = (await repo.byId(a.id))!;
      expect(after.label, a.label);
      expect(after.creditLimit, isNull);
    });
  });

  group('errors never carry data', () {
    test('exceptions print a code only', () async {
      Object? caught;
      try {
        await repo.resolve(
          hint(institution: 'BNK', last4: '${sentinel}1', label: sentinel),
        );
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<AccountsException>());
      expect(caught.toString(), isNot(contains(sentinel)));
      expect(caught.toString(), AccountsException.invalid);

      // A database refusal stays code-only too.
      try {
        await repo.recordBalance(
          accountId: 'nope$sentinel',
          asOf: at(t0),
          balance: egpMinor(123456789),
        );
      } on Object catch (e) {
        caught = e;
      }
      expect(caught.toString(), isNot(contains(sentinel)));
      expect(caught.toString(), isNot(contains('123456789')));
    });

    test('a source txn that does not exist is a code-only DB error', () async {
      final a = (await repo.resolve(hint())).account;
      Object? caught;
      try {
        await repo.recordBalance(
          accountId: a.id,
          asOf: at(t0),
          balance: egpMinor(1),
          sourceTxnId: 'missing$sentinel',
        );
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<DbWriteException>());
      expect(caught.toString(), isNot(contains(sentinel)));
    });
  });

  group('providers', () {
    test(
      'accountsRepositoryProvider uses the injected clock and ids',
      () async {
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => edb.db),
            clockProvider.overrideWithValue(() => at(t0 + 42)),
            idGeneratorProvider.overrideWithValue(() => 'fixed-id'),
          ],
        );
        addTearDown(container.dispose);
        final r = await container.read(accountsRepositoryProvider.future);
        final a = await r.resolve(hint());
        expect(a.account.id, 'fixed-id');
        expect(a.account.createdAt, at(t0 + 42));
      },
    );
  });
}
