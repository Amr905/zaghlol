// T-018 (T-017 review S-2): FTS5 `secure-delete` is on for both transaction
// search tables on a fresh database (design note §6), so the tokens of a
// hard-deleted transaction leave the FTS index segments at once. Checked on
// the raw `_data` blobs, with a positive control: the same delete with the
// option off leaves the token bytes behind (the test can see them). The
// migrated case is in migration_v3_test.dart. All data synthetic.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/fts_options.dart';

import 'financial_fixtures.dart';
import 'fts_probe.dart';

/// A synthetic merchant whose letters appear nowhere else in the rows.
const String marker = 'qzxvjwk';

/// Inserts and hard-deletes one transaction whose merchant is [marker];
/// returns whether the marker's bytes are left in (trigram, short) data.
Future<(bool, bool)> leftAfterDelete(AppDatabase db) async {
  await AccountsDao(db).insert(account('acc1'));
  final txns = TransactionsDao(db);
  await txns.insert(txn('keep', merchant: 'Synthetic Keep'));
  await txns.insert(txn('gone', merchant: marker, note: marker));
  expect([for (final r in await txns.search('zxvj')) r.id], ['gone']);
  expect(await dataHolds(db, 'transactions_fts', 'zxv'), isTrue);
  expect(await dataHolds(db, 'transactions_fts_short', marker), isTrue);
  await db.customStatement("DELETE FROM transactions WHERE id = 'gone'");
  expect(await txns.search('zxvj'), isEmpty);
  return (
    await dataHolds(db, 'transactions_fts', 'zxv'),
    await dataHolds(db, 'transactions_fts_short', marker),
  );
}

void main() {
  late EncryptedDb edb;

  setUp(() async => edb = await EncryptedDb.open());
  tearDown(() => edb.close());

  test('a fresh database has secure-delete on both transaction FTS tables, '
      'and only there', () async {
    expect(await secureDeleteOf(edb.db, 'transactions_fts'), 1);
    expect(await secureDeleteOf(edb.db, 'transactions_fts_short'), 1);
    expect(await secureDeleteOf(edb.db, 'catalog_alias_fts'), isNull);
    expect(ftsOptionStatements, hasLength(2));
  });

  test(
    'a hard delete leaves none of the tokens in the index segments',
    () async {
      expect(await leftAfterDelete(edb.db), (false, false));
    },
  );

  test('positive control: with secure-delete off, the same delete leaves '
      'the token bytes (so the check above can see them)', () async {
    for (final t in ['transactions_fts', 'transactions_fts_short']) {
      await edb.db.customStatement(
        "INSERT INTO $t ($t, rank) VALUES ('secure-delete', 0)",
      );
    }
    final (trigram, short) = await leftAfterDelete(edb.db);
    expect(trigram || short, isTrue);
  });
}
