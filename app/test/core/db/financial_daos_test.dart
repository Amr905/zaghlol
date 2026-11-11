// T-017: AccountsDao, RawMessagesDao, the Money mapping and the error
// hygiene of every DAO write (design note §4, §7), on an encrypted
// database. A refused write never carries the message body, merchant or
// amount: only a code (with a positive control showing the raw drift error
// would). All data synthetic.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/raw_messages_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/daos/write_errors.dart';
import 'package:zaghlol/core/db/db_errors.dart';
import 'package:zaghlol/core/db/money_columns.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'financial_fixtures.dart';

const String sentinel = 'T017SENTINEL_زغلول_٤٢';

void main() {
  for (final background in [true, false]) {
    group(background ? 'background' : 'foreground', () {
      late EncryptedDb edb;

      setUp(() async => edb = await EncryptedDb.open(background: background));
      tearDown(() => edb.close());

      test('raw messages: insertIfNew stores once per body_hash (BR-ING-02 '
          'rule 1) and keeps the body', () async {
        final dao = RawMessagesDao(edb.db);
        expect(await dao.insertIfNew(rawMessage('m1', hash: 1)), isTrue);
        expect(await dao.insertIfNew(rawMessage('m2', hash: 1)), isFalse);
        expect(await dao.byId('m2'), isNull);
        expect((await dao.byId('m1'))!.body, 'SYNTHETIC body m1');
        expect(await dao.hashExists(hashOf(1)), isTrue);
        expect(await dao.hashExists(hashOf(2)), isFalse);
        // A duplicate id (not a duplicate hash) is an error, not "dup".
        await expectLater(
          dao.insertIfNew(rawMessage('m1', hash: 3)),
          throwsA(
            isA<DbWriteException>().having(
              (e) => e.code,
              'code',
              DbWriteException.constraintPrimaryKey,
            ),
          ),
        );
      });

      test('a refused raw message write carries no body text', () async {
        final dao = RawMessagesDao(edb.db);
        final bad = rawMessage(
          'm1',
          hash: 1,
        ).copyWith(body: const Value(sentinel), channel: const Value('fax'));
        Object? caught;
        try {
          await dao.insertIfNew(bad);
        } on Object catch (e) {
          caught = e;
        }
        expect(caught, isA<DbWriteException>());
        expect(
          (caught! as DbWriteException).code,
          DbWriteException.constraintCheck,
        );
        expect(caught.toString(), DbWriteException.constraintCheck);
        expect(caught.toString().contains('T017SENTINEL'), isFalse);

        // Positive control: the unguarded drift error does carry it, which
        // is why every DAO write goes through guardWrite.
        Object? raw;
        try {
          await edb.db.into(edb.db.rawMessages).insert(bad);
        } on Object catch (e) {
          raw = e;
        }
        expect(raw, isNotNull);
        expect(raw, isNot(isA<DbWriteException>()));
        expect(raw.toString().contains('T017SENTINEL'), isTrue);
      });

      test(
        'a refused transaction write carries no merchant or amount',
        () async {
          await AccountsDao(edb.db).insert(account('acc1'));
          Object? caught;
          try {
            await TransactionsDao(edb.db)
                .insert(txn('t1', merchant: sentinel, amountMinor: -987654321));
          } on Object catch (e) {
            caught = e;
          }
          expect(caught, isA<DbWriteException>());
          expect(caught.toString().contains('T017SENTINEL'), isFalse);
          expect(caught.toString().contains('987654321'), isFalse);
        },
      );

      test('accounts: insert, byId, default cash', () async {
        final dao = AccountsDao(edb.db);
        await dao.insert(account('acc1'));
        await dao.insert(
          account(
            'cash',
            kind: 'cash',
            institution: null,
            last4: null,
            defaultCash: true,
          ),
        );
        expect((await dao.byId('acc1'))!.kind, 'debit');
        expect((await dao.defaultCash())!.id, 'cash');
      });

      test('balances: one row per currency, upsert replaces, Money round '
          'trip, currency mismatch refused before any write', () async {
        final dao = AccountsDao(edb.db);
        await dao.insert(account('acc1', kind: 'multi_currency'));
        final egp = Currency.of('EGP');
        final kwd = Currency.of('KWD');
        await dao.upsertBalance(
          accountId: 'acc1',
          currency: egp,
          asOf: t0,
          balance: Money(egp, -12345),
        );
        await dao.upsertBalance(
          accountId: 'acc1',
          currency: kwd,
          asOf: t0,
          balance: Money(kwd, 1500),
          available: Money(kwd, 2500),
        );
        await dao.upsertBalance(
          accountId: 'acc1',
          currency: egp,
          asOf: t0 + 1,
          balance: Money(egp, 500),
        );
        final rows = await dao.balancesOf('acc1');
        expect([for (final r in rows) r.currency], ['EGP', 'KWD']);
        expect(rows[0].balance, Money(egp, 500));
        expect(rows[0].available, isNull);
        expect(rows[0].asOf, t0 + 1);
        expect(rows[1].balance, Money(kwd, 1500));
        expect(rows[1].available, Money(kwd, 2500));
        expect(
          () => dao.upsertBalance(
            accountId: 'acc1',
            currency: egp,
            asOf: t0,
            balance: Money(kwd, 1),
          ),
          throwsA(isA<CurrencyMismatch>()),
        );
        expect((await dao.balancesOf('acc1'))[0].balance, Money(egp, 500));
      });

      test(
        'transactions: Money in and out (withAmount / '
        'withOriginalAmount / amount / originalAmount / balanceAfter)',
        () async {
          await AccountsDao(edb.db).insert(account('acc1'));
          final dao = TransactionsDao(edb.db);
          final usd = Currency.of('USD');
          final egp = Currency.of('EGP');
          await dao.insert(
            txn('t1')
                .withAmount(Money(egp, 98765))
                .withOriginalAmount(Money(usd, 2000))
                .copyWith(balanceAfterMinor: const Value(-100)),
          );
          final row = (await dao.byId('t1'))!;
          expect(row.amount, Money(egp, 98765));
          expect(row.originalAmount, Money(usd, 2000));
          expect(row.balanceAfter, Money(egp, -100));
          await dao.updateById(
            't1',
            const TransactionsCompanion().withOriginalAmount(null),
          );
          expect((await dao.byId('t1'))!.originalAmount, isNull);
        },
      );

      test('a stored code that is ISO-shaped but unknown reads as '
          'CorruptMoney, not a guess', () async {
        await AccountsDao(edb.db).insert(account('acc1'));
        await TransactionsDao(edb.db)
            .insert(txn('t1', currency: 'QQQ', amountMinor: 1));
        final row = (await TransactionsDao(edb.db).byId('t1'))!;
        expect(() => row.amount, throwsA(isA<CorruptMoney>()));
      });
    });
  }

  group('money_columns', () {
    test('optionalMoneyOf: both NULL → null; half NULL → CorruptMoney', () {
      expect(optionalMoneyOf(null, null), isNull);
      expect(
        () => optionalMoneyOf(5, null),
        throwsA(
          isA<CorruptMoney>().having(
            (e) => e.reason,
            'reason',
            CorruptMoneyReason.missingCurrency,
          ),
        ),
      );
      expect(() => optionalMoneyOf(null, 'EGP'), throwsA(isA<CorruptMoney>()));
      expect(optionalMoneyOf(7, 'JPY'), Money(Currency.of('JPY'), 7));
    });

    test('moneyOf: out of range or lowercase code → CorruptMoney', () {
      expect(() => moneyOf(maxMinor + 1, 'EGP'), throwsA(isA<CorruptMoney>()));
      expect(() => moneyOf(1, 'egp'), throwsA(isA<CorruptMoney>()));
      expect(moneyOf(-maxMinor, 'EGP').minor, -maxMinor);
    });
  });

  group('writeExceptionOf', () {
    test('non-database errors pass through guardWrite unchanged', () async {
      await expectLater(
        guardWrite<void>(() async => throw StateError('x')),
        throwsA(isA<StateError>()),
      );
      expect(writeExceptionOf(Exception('x')), isNull);
    });
  });
}
