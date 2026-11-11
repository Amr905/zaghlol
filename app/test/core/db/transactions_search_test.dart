// T-017 AC3: FTS finds a merchant by partial Arabic / English text (FR-TXN-01;
// design note §5), on an encrypted database. Trigram table for 3+
// characters, word-prefix table for 1–2; amounts in both digit systems; the
// triggers keep both indexes in sync on insert, update, delete and soft
// delete (FTS5 integrity-check after each scenario). All data synthetic.

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/db_errors.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'financial_fixtures.dart';

const String _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

/// The expected amount_text, computed in Dart from the ISO table: the
/// amount with the currency's exponent, Latin then Arabic-Indic.
String expectedAmountText(int minor, Currency currency) {
  final e = currency.exponent;
  var unit = 1;
  for (var i = 0; i < e; i++) {
    unit *= 10;
  }
  final latin = e == 0
      ? '$minor'
      : '${minor ~/ unit}.${(minor % unit).toString().padLeft(e, '0')}';
  final arabic = StringBuffer();
  for (final ch in latin.split('')) {
    arabic.write(ch == '.' ? '٫' : _arabicDigits[int.parse(ch)]);
  }
  return '$latin $arabic';
}

Future<void> integrityCheck(AppDatabase db) async {
  for (final t in ['transactions_fts', 'transactions_fts_short']) {
    await db.customStatement("INSERT INTO $t ($t) VALUES ('integrity-check')");
  }
}

void main() {
  late EncryptedDb edb;
  late TransactionsDao dao;

  Future<List<String>> ids(String q) async => [
    for (final r in await dao.search(q)) r.id,
  ];

  setUp(() async {
    edb = await EncryptedDb.open();
    dao = TransactionsDao(edb.db);
    await AccountsDao(edb.db).insert(account('acc1'));
    await dao.insert(
      txn(
        'carrefour',
        merchant: 'كارفور المعادي',
        amountMinor: 125050,
        occurredAt: t0 + 3,
      ),
    );
    await dao.insert(
      txn(
        'cafe',
        merchant: 'Café Zamalek',
        merchantNorm: 'cafe zamalek',
        amountMinor: 4500,
        occurredAt: t0 + 2,
      ),
    );
    await dao.insert(
      txn(
        'ipa',
        direction: 'transfer_out',
        counterparty: 'أحمد محمود',
        note: 'groceries for home',
        amountMinor: 1500,
        currency: 'KWD',
        occurredAt: t0 + 1,
      ),
    );
    await dao.insert(
      txn('yen', merchant: 'Kiosk Giza', amountMinor: 1200, currency: 'JPY'),
    );
  });

  tearDown(() => edb.close());

  group('AC3: partial Arabic text (trigram, 3+ characters)', () {
    for (final (q, expected) in [
      ('كارف', ['carrefour']),
      ('معادي', ['carrefour']),
      ('ور الم', ['carrefour']), // across the word boundary
      ('محمود', ['ipa']), // counterparty
      ('حمد', ['ipa']),
    ]) {
      test('"$q" → $expected', () async {
        expect(await ids(q), expected);
      });
    }
  });

  group('AC3: partial English text (trigram: case and Latin diacritics '
      'ignored)', () {
    for (final (q, expected) in [
      ('cafe', ['cafe']),
      ('CAFÉ', ['cafe']),
      ('zamal', ['cafe']),
      ('mal', ['cafe']),
      ('grocer', ['ipa']), // note
      ('Kiosk', ['yen']),
      ('nothing here', <String>[]),
    ]) {
      test('"$q" → $expected', () async {
        expect(await ids(q), expected);
      });
    }
  });

  group('AC3: 1–2 characters use the word-prefix table', () {
    for (final (q, expected) in [
      ('Ca', ['cafe']),
      ('ca', ['cafe']),
      ('كا', ['carrefour']),
      ('ال', ['carrefour']), // prefix of المعادي
      ('Z', ['cafe']),
      ('أح', ['ipa']),
      ('af', <String>[]), // not a word prefix
      ('١٢', <String>[]), // no amounts in the short table
    ]) {
      test('"$q" → $expected', () async {
        expect(await ids(q), expected);
      });
    }
  });

  group('amounts in both digit systems, with the currency exponent', () {
    for (final (q, expected) in [
      ('1250.50', ['carrefour']),
      ('١٢٥٠٫٥٠', ['carrefour']),
      ('١٢٥٠', ['carrefour']),
      ('1.500', ['ipa']), // KWD: 3 decimals
      ('١٫٥٠٠', ['ipa']),
      ('1200', ['yen']), // JPY: no decimals
      ('45.00', ['cafe']),
    ]) {
      test('"$q" → $expected', () async {
        expect(await ids(q), expected);
      });
    }
  });

  test('amount_text matches the ISO table for every currency (a table '
      'refresh that changes an exponent fails here until a migration '
      'updates transactions_fts_row)', () async {
    var i = 0;
    for (final currency in Currency.all) {
      for (final minor in [0, 5, 1234567, maxMinor]) {
        await dao.insert(
          txn('iso$i', amountMinor: minor, currency: currency.code),
        );
        final row = await edb.db
            .customSelect(
              'SELECT amount_text FROM transactions_fts_src WHERE txn_id = ?',
              variables: [Variable.withString('iso$i')],
            )
            .getSingle();
        expect(
          row.read<String>('amount_text'),
          expectedAmountText(minor, currency),
          reason: '${currency.code} $minor',
        );
        i++;
      }
    }
    await integrityCheck(edb.db);
  });

  test('merchant text indexes the raw name and the normalised key', () async {
    final row = await edb.db
        .customSelect(
          "SELECT merchant FROM transactions_fts_src WHERE txn_id = 'cafe'",
        )
        .getSingle();
    expect(row.read<String>('merchant'), 'Café Zamalek cafe zamalek');
  });

  test(
    'update, soft delete, undo and delete keep both indexes in sync',
    () async {
      await dao.updateById(
        'cafe',
        const TransactionsCompanion(
          merchantRaw: Value('Bakery Dokki'),
          merchantNorm: Value(null),
        ),
      );
      expect(await ids('zamal'), isEmpty);
      expect(await ids('Za'), isEmpty);
      expect(await ids('dokki'), ['cafe']);
      expect(await ids('Ba'), ['cafe']);

      await dao.updateById(
        'cafe',
        const TransactionsCompanion(amountMinor: Value(9900)),
      );
      expect(await ids('45.00'), isEmpty);
      expect(await ids('99.00'), ['cafe']);

      await dao.softDelete('cafe', at: t0 + 10);
      expect(await ids('dokki'), isEmpty);
      await dao.updateById(
        'cafe',
        const TransactionsCompanion(deletedAt: Value(null)),
      );
      expect(await ids('dokki'), ['cafe']);

      await (edb.db.delete(
        edb.db.transactions,
      )..where((t) => t.id.equals('cafe'))).go();
      expect(await ids('dokki'), isEmpty);
      expect(
        await edb.db
            .customSelect(
              "SELECT count(*) AS n FROM transactions_fts_src WHERE txn_id = 'cafe'",
            )
            .getSingle()
            .then((r) => r.read<int>('n')),
        0,
      );
      await integrityCheck(edb.db);
    },
  );

  test('changing a transaction id moves its index row', () async {
    await edb.db.customStatement(
      "UPDATE transactions SET id = 'cafe2' WHERE id = 'cafe'",
    );
    expect(await ids('zamal'), ['cafe2']);
    await integrityCheck(edb.db);
  });

  test('results are newest first and capped by limit', () async {
    for (var i = 0; i < 5; i++) {
      await dao.insert(
        txn('m$i', merchant: 'Market Nile $i', occurredAt: t0 + 100 + i),
      );
    }
    expect(await ids('market nile'), ['m4', 'm3', 'm2', 'm1', 'm0']);
    expect(
      [for (final r in await dao.search('market', limit: 2)) r.id],
      ['m4', 'm3'],
    );
    expect(await dao.search('market', limit: 0), isEmpty);
  });

  test('FTS5 syntax in the query is matched literally, never parsed', () async {
    for (final q in [
      '"',
      '""',
      'a" OR "caf',
      'caf*',
      'NEAR(كارفور المعادي)',
      'merchant:cafe',
      '-cafe',
      'cafe AND kiosk',
      '^caf',
      '(',
      '*',
      '\u0000',
      'a\u0000b',
      '"\u0000',
      'x\u0001\u001F\u007F\u0085y',
      '\uD800zz',
      'zz\uDC00',
    ]) {
      expect(await dao.search(q), isEmpty, reason: 'query #${q.length}');
    }
    // A double quote inside real text still matches literally.
    await dao.insert(txn('quoted', merchant: 'The "Best" Shop'));
    expect(await ids('"Best"'), ['quoted']);
  });

  test('control characters (incl. NUL) act as spaces (F-1)', () async {
    expect(await ids('\u0000كارف\u0000'), ['carrefour']);
    expect(await ids('\u0000Ca'), ['cafe']);
    expect(await ids('Café\u0000Zam'), ['cafe']); // NUL became a space
    expect(await ids('Caf\u0000é'), isEmpty); // not glued into 'Café'
    expect(await ids('Café\tZam'), ['cafe']);
    expect(await dao.search('\u0000\u0000'), isEmpty);
  });

  for (final background in [true, false]) {
    test('a failed search is a code-only DbReadException that never holds '
        'the query (F-1, background: $background)', () async {
      final other = await EncryptedDb.open(background: background);
      addTearDown(other.close);
      final otherDao = TransactionsDao(other.db);
      await other.db.customStatement('DROP TABLE transactions_fts');
      await other.db.customStatement('DROP TABLE transactions_fts_short');
      for (final q in ['SENTINEL-query-7f3a', 'ZQ']) {
        Object? caught;
        try {
          await otherDao.search(q);
        } on Object catch (e) {
          caught = e;
        }
        expect(caught, isA<DbReadException>());
        expect(caught.toString(), DbReadException.readFailed);
        expect(caught.toString(), isNot(contains(q)));
        expect(caught.toString(), isNot(contains('transactions')));
      }
    });
  }

  test('empty, blank and over-long queries', () async {
    expect(await dao.search(''), isEmpty);
    expect(await dao.search('   '), isEmpty);
    // Cut to maxSearchQueryRunes code points: still runs, still matches the
    // prefix it keeps.
    final long = 'كارفور المعادي${' x' * 200}';
    expect(long.runes.length, greaterThan(maxSearchQueryRunes));
    expect(await dao.search(long), isEmpty);
    expect(await ids('  كارفور  '), ['carrefour']);
  });

  test('rebuildSearchIndexes leaves search working and consistent', () async {
    await dao.rebuildSearchIndexes();
    await integrityCheck(edb.db);
    expect(await ids('كارف'), ['carrefour']);
    expect(await ids('Ca'), ['cafe']);
  });
}
