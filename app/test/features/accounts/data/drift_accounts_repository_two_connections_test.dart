// T-045 F-1: the accounts repository on TWO real connections to the same
// encrypted file (UI engine + background SMS engine). Pattern from
// test/core/db/financial_b_daos_test.dart. All data synthetic.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/features/accounts/data/drift_accounts_repository.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/db_open_harness.dart' show keyOf;
import '../../../core/db/financial_fixtures.dart';

final Currency egp = Currency.of('EGP');
Money egpMinor(int m) => Money(egp, m);
DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

void main() {
  for (final background in [true, false]) {
    group(background ? 'background' : 'foreground', () {
      late EncryptedDb edb;
      late AppDatabase other;
      late DriftAccountsRepository repoA;
      late DriftAccountsRepository repoB;
      var nextId = 0;

      DriftAccountsRepository makeRepo(AppDatabase db, String tag) =>
          DriftAccountsRepository(
            AccountsDao(db),
            clock: () => at(t0 + 1000),
            newId: () => '$tag${nextId++}',
          );

      Future<int> count(String where) async => (await edb.db
          .customSelect('SELECT COUNT(*) AS c FROM accounts WHERE $where')
          .getSingle()
          .then((r) => r.read<int>('c')));

      setUp(() async {
        nextId = 0;
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        edb = await EncryptedDb.open(background: background);
        other = AppDatabase(
          openEncryptedExecutor(
            edb.world.mainFile,
            keyOf(61),
            inBackground: !background,
          ),
          validateSchema: false,
        );
        repoA = makeRepo(edb.db, 'a');
        repoB = makeRepo(other, 'b');
      });

      tearDown(() async {
        await other.close();
        await edb.close();
      });

      DriftAccountsRepository pick(int i) => i.isEven ? repoA : repoB;

      test('two connections: resolve with last4 creates exactly one '
          'account', () async {
        final hint = AccountHint(
          institutionCode: 'BNK',
          last4: '1234',
          currency: egp,
          label: 'Synthetic card',
        );
        final results = await Future.wait([
          for (var i = 0; i < 12; i++) pick(i).resolve(hint),
        ]);
        expect(results.where((r) => r.created), hasLength(1));
        expect({for (final r in results) r.account.id}, hasLength(1));
        expect(await count('1 = 1'), 1);
      });

      test('two connections: institution-only resolve creates exactly one '
          'account', () async {
        final hint = AccountHint(
          institutionCode: 'WAL',
          last4: null,
          currency: egp,
          label: 'Synthetic wallet',
        );
        final results = await Future.wait([
          for (var i = 0; i < 12; i++) pick(i).resolve(hint),
        ]);
        expect(results.where((r) => r.created), hasLength(1));
        expect({for (final r in results) r.account.id}, hasLength(1));
        expect(await count('1 = 1'), 1);
      });

      test('two connections: ensureDefaultCash leaves one default '
          'cash', () async {
        final all = await Future.wait([
          for (var i = 0; i < 12; i++)
            pick(i).ensureDefaultCash(currency: egp, label: 'Cash $i'),
        ]);
        expect({for (final a in all) a.id}, hasLength(1));
        expect(await count('is_default_cash = 1'), 1);
        expect(await count('1 = 1'), 1);
      });

      for (final newestFirst in [true, false]) {
        test('two connections: recordBalance newest wins, '
            '${newestFirst ? "newest" : "oldest"} write first', () async {
          final id = (await repoA.resolve(
            AccountHint(
              institutionCode: 'BNK',
              last4: '1234',
              currency: egp,
              label: 'Synthetic card',
            ),
          )).account.id;
          final writes = <Future<bool>>[];
          // Newest on connection A, older ones on B (and the reverse
          // issue order), so both orders of the cross-connection race run.
          final order = newestFirst ? [9, 8, 7, 6] : [6, 7, 8, 9];
          for (final i in order) {
            writes.add(
              pick(i).recordBalance(
                accountId: id,
                asOf: at(t0 + i),
                balance: egpMinor(i),
              ),
            );
          }
          await Future.wait(writes);
          for (final repo in [repoA, repoB]) {
            final b = (await repo.balancesOf(id)).single;
            expect(b.asOf, at(t0 + 9));
            expect(b.balance, egpMinor(9));
          }
        });
      }
    });
  }
}
