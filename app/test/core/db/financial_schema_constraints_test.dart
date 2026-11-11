// T-017 AC1: every CHECK / UNIQUE / NOT NULL / FOREIGN KEY of schema v2
// batch A is enforced, on an encrypted database (design note §3, §4, §10).
// Each case changes one column of a row that is otherwise valid; the valid
// row itself is the control (it inserts). Failures come back as code-only
// DbWriteExceptions (guardWrite). All data synthetic.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/db_errors.dart';

import 'financial_fixtures.dart';

const String check = DbWriteException.constraintCheck;
const String unique = DbWriteException.constraintUnique;
const String primaryKey = DbWriteException.constraintPrimaryKey;
const String notNull = DbWriteException.constraintNotNull;
const String foreignKey = DbWriteException.constraintForeignKey;

/// SQL literals of a valid row per table (parents: account `acc1`,
/// transactions `e1` expense 100.00 EGP and `i1` income 100.00 EGP,
/// category `sys:food`).
var _hashSeq = 1000;

Map<String, String> validRow(String table, String id) => switch (table) {
  'categories' => {
    'id': "'$id'",
    'name_ar': "'أكل'",
    'name_en': "'Food'",
    'icon': "'food'",
    'color': "'#0F7A55'",
    'bucket': "'needs'",
    'sort': '1',
  },
  'accounts' => {
    'id': "'$id'",
    'institution_code': "'BNK'",
    'kind': "'debit'",
    'label': "'Synthetic'",
    'last4': 'NULL',
    'default_currency': "'EGP'",
    'created_at': '$t0',
    'updated_at': '$t0',
  },
  'account_balances' => {
    'account_id': "'acc1'",
    'currency': "'${id.substring(0, 3).toUpperCase()}'",
    'balance_minor': '100',
    'available_minor': '200',
    'as_of': '$t0',
  },
  'raw_messages' => {
    'id': "'$id'",
    'channel': "'sms'",
    'body': "'SYNTHETIC'",
    'body_hash': "'${hashOf(_hashSeq++)}'",
    'received_at': '$t0',
    'parse_status': "'parsed'",
    'registry_version': '1',
    'created_at': '$t0',
  },
  'transactions' => {
    'id': "'$id'",
    'account_id': "'acc1'",
    'source': "'manual'",
    'direction': "'expense'",
    'amount_minor': '100',
    'currency': "'EGP'",
    'occurred_at': '$t0',
    'occurred_tz_offset_min': '120',
    'category_source': "'none'",
    'created_at': '$t0',
    'updated_at': '$t0',
  },
  'transfer_pairs' => {
    'id': "'$id'",
    'out_txn_id': "'e1'",
    'in_txn_id': "'i1'",
    'kind': "'manual'",
    'created_at': '$t0',
  },
  'split_participants' => {
    'id': "'$id'",
    'expense_txn_id': "'e1'",
    'name': "'Synthetic friend'",
    'share_minor': '100',
    'created_at': '$t0',
  },
  'offset_links' => {
    'id': "'$id'",
    'kind': "'reimbursement'",
    'expense_txn_id': "'e1'",
    'source_txn_id': "'i1'",
    'amount_minor': '100',
    'created_at': '$t0',
  },
  _ => throw ArgumentError.value(table),
};

String insertSql(String table, Map<String, String> row) =>
    'INSERT INTO $table (${row.keys.join(', ')}) '
    'VALUES (${row.values.join(', ')})';

/// One case: [table] row [id] with [overrides] (null value: column left
/// out) fails with [code] (null: inserts).
typedef Case = ({
  String table,
  String what,
  Map<String, String?> overrides,
  String? code,
});

Case c(
  String table,
  String what,
  Map<String, String?> overrides,
  String? code,
) => (table: table, what: what, overrides: overrides, code: code);

final List<Case> cases = [
  // categories (§2.4 DDL, created here as the FK parent).
  c('categories', 'bucket outside the set', {'bucket': "'fun'"}, check),
  c('categories', 'is_custom = 2', {'is_custom': '2'}, check),
  c('categories', 'is_archived = -1', {'is_archived': '-1'}, check),
  c('categories', 'name_en NULL', {'name_en': null}, notNull),
  c('categories', 'id NULL', {'id': 'NULL'}, notNull),
  c('categories', 'unknown parent', {'parent_id': "'nope'"}, foreignKey),

  // accounts.
  c('accounts', 'kind outside the set', {'kind': "'savings'"}, check),
  c('accounts', 'empty label', {'label': "''"}, check),
  c('accounts', '31-char label', {'label': "'${'x' * 31}'"}, check),
  c('accounts', '30-char Arabic label', {'label': "'${'ز' * 30}'"}, null),
  c('accounts', 'last4 of 1 digit', {'last4': "'1'"}, check),
  c('accounts', 'last4 of 5 digits', {'last4': "'12345'"}, check),
  c('accounts', 'last4 with a letter', {'last4': "'12a4'"}, check),
  c('accounts', 'last4 Arabic-Indic (not normalised)', {
    'last4': "'١٢٣٤'",
  }, check),
  c('accounts', 'last4 of 2 digits', {'last4': "'12'"}, null),
  c('accounts', 'last4 NULL (cash)', {'last4': 'NULL'}, null),
  c('accounts', 'currency lowercase', {'default_currency': "'egp'"}, check),
  c('accounts', 'currency of 2 letters', {'default_currency': "'EG'"}, check),
  c('accounts', 'currency of 4 letters', {'default_currency': "'EGPX'"}, check),
  c('accounts', 'currency with a digit', {'default_currency': "'E1P'"}, check),
  c('accounts', 'credit limit −1', {'credit_limit_minor': '-1'}, check),
  c('accounts', 'credit limit REAL', {'credit_limit_minor': '1.5'}, check),
  c('accounts', 'credit limit text', {'credit_limit_minor': "'abc'"}, check),
  c('accounts', 'credit limit 2^53', {
    'credit_limit_minor': '${maxMinor + 1}',
  }, check),
  c('accounts', 'credit limit 2^53 − 1', {
    'credit_limit_minor': '$maxMinor',
  }, null),
  c('accounts', 'due day 0', {'statement_due_day': '0'}, check),
  c('accounts', 'due day 32', {'statement_due_day': '32'}, check),
  c('accounts', 'is_hidden = 2', {'is_hidden': '2'}, check),
  c('accounts', 'merged into itself', {'merged_into_id': '@id'}, check),
  c('accounts', 'merged into an unknown account', {
    'merged_into_id': "'nope'",
  }, foreignKey),
  c('accounts', 'default cash on a debit card', {
    'is_default_cash': '1',
  }, check),
  c('accounts', 'id NULL', {'id': 'NULL'}, notNull),

  // account_balances.
  c('account_balances', 'currency lowercase', {'currency': "'usd'"}, check),
  c('account_balances', 'balance REAL', {'balance_minor': '0.5'}, check),
  c('account_balances', 'balance 2^53', {
    'balance_minor': '${maxMinor + 1}',
  }, check),
  c('account_balances', 'balance −2^53', {
    'balance_minor': '-${maxMinor + 1}',
  }, check),
  c('account_balances', 'balance −(2^53 − 1)', {
    'balance_minor': '-$maxMinor',
  }, null),
  c('account_balances', 'balance −2^63 (abs() would overflow)', {
    'balance_minor': '-9223372036854775808',
  }, check),
  c('account_balances', 'balance unknown (NULL)', {
    'balance_minor': 'NULL',
  }, null),
  // INTEGER affinity stores an exact-integer REAL as an integer.
  c('account_balances', 'available 2.0 (stored as integer 2)', {
    'available_minor': '2.0e0',
  }, null),
  c('account_balances', 'available text', {'available_minor': "'x'"}, check),
  c('account_balances', 'unknown account', {
    'account_id': "'nope'",
  }, foreignKey),
  c('account_balances', 'unknown source transaction', {
    'source_txn_id': "'nope'",
  }, foreignKey),

  // raw_messages.
  c('raw_messages', 'channel outside the set', {'channel': "'email'"}, check),
  c('raw_messages', 'short body_hash', {'body_hash': "'abc'"}, check),
  c('raw_messages', 'uppercase body_hash', {
    'body_hash': "'${'A' * 64}'",
  }, check),
  c('raw_messages', 'non-hex body_hash', {'body_hash': "'${'g' * 64}'"}, check),
  c('raw_messages', 'parse_status outside the set', {
    'parse_status': "'done'",
  }, check),
  c('raw_messages', 'body NULL', {'body': null}, notNull),

  // transactions.
  c('transactions', 'source outside the set', {'source': "'fax'"}, check),
  c('transactions', 'direction outside the set', {
    'direction': "'gift'",
  }, check),
  c('transactions', 'status outside the set', {'status': "'held'"}, check),
  c('transactions', 'amount −1', {'amount_minor': '-1'}, check),
  c('transactions', 'amount REAL', {'amount_minor': '10.25'}, check),
  c('transactions', 'amount 2^53', {'amount_minor': '${maxMinor + 1}'}, check),
  c('transactions', 'amount 2^53 − 1', {'amount_minor': '$maxMinor'}, null),
  c('transactions', 'amount 0', {'amount_minor': '0'}, null),
  c('transactions', 'amount NULL', {'amount_minor': null}, notNull),
  c('transactions', 'currency lowercase', {'currency': "'egp'"}, check),
  c('transactions', 'currency NULL', {'currency': null}, notNull),
  c('transactions', 'original amount without currency', {
    'original_amount_minor': '2000',
  }, check),
  c('transactions', 'original currency without amount', {
    'original_currency': "'USD'",
  }, check),
  c('transactions', 'original pair set', {
    'original_amount_minor': '2000',
    'original_currency': "'USD'",
  }, null),
  c('transactions', 'original amount −1', {
    'original_amount_minor': '-1',
    'original_currency': "'USD'",
  }, check),
  c('transactions', 'original amount REAL', {
    'original_amount_minor': '20.5',
    'original_currency': "'USD'",
  }, check),
  c('transactions', 'original currency lowercase', {
    'original_amount_minor': '2000',
    'original_currency': "'usd'",
  }, check),
  c('transactions', 'tz offset +18:01', {
    'occurred_tz_offset_min': '1081',
  }, check),
  c('transactions', 'tz offset −18:00', {
    'occurred_tz_offset_min': '-1080',
  }, null),
  c('transactions', 'counterparty_kind outside the set', {
    'counterparty_kind': "'pet'",
  }, check),
  c('transactions', 'category_source outside the set', {
    'category_source': "'guess'",
  }, check),
  c('transactions', 'is_user_verified = 2', {'is_user_verified': '2'}, check),
  c('transactions', 'is_internal = 2', {'is_internal': '2'}, check),
  c('transactions', 'balance after REAL', {
    'balance_after_minor': '1.5',
  }, check),
  c('transactions', 'balance after −2^53', {
    'balance_after_minor': '-${maxMinor + 1}',
  }, check),
  c('transactions', 'balance after negative', {
    'balance_after_minor': '-500',
  }, null),
  c('transactions', 'parse_confidence 1.5', {'parse_confidence': '1.5'}, check),
  c('transactions', 'unknown account', {'account_id': "'nope'"}, foreignKey),
  c('transactions', 'unknown category', {'category_id': "'nope'"}, foreignKey),
  c('transactions', 'known category', {'category_id': "'sys:food'"}, null),
  c('transactions', 'unknown raw message', {
    'raw_message_id': "'nope'",
  }, foreignKey),
  c('transactions', 'unknown transfer pair', {
    'transfer_pair_id': "'nope'",
  }, foreignKey),

  // transfer_pairs.
  c('transfer_pairs', 'in = out', {'in_txn_id': "'e1'"}, check),
  c('transfer_pairs', 'kind outside the set', {'kind': "'magic'"}, check),
  c('transfer_pairs', 'one-sided (in NULL, EC-15)', {
    'in_txn_id': 'NULL',
  }, null),
  c('transfer_pairs', 'unknown out', {'out_txn_id': "'nope'"}, foreignKey),

  // split_participants.
  c('split_participants', 'share −1', {'share_minor': '-1'}, check),
  c('split_participants', 'share REAL', {'share_minor': '3.5'}, check),
  c('split_participants', 'share 2^53', {
    'share_minor': '${maxMinor + 1}',
  }, check),
  c('split_participants', 'unknown expense', {
    'expense_txn_id': "'nope'",
  }, foreignKey),

  // offset_links.
  c('offset_links', 'amount 0', {'amount_minor': '0'}, check),
  c('offset_links', 'amount REAL', {'amount_minor': '1.5'}, check),
  c('offset_links', 'expense = source', {'source_txn_id': "'e1'"}, check),
  c('offset_links', 'kind outside the set', {'kind': "'gift'"}, check),
];

void main() {
  late EncryptedDb edb;

  setUpAll(() async {
    edb = await EncryptedDb.open();
    final db = edb.db;
    await db.customStatement(
      insertSql('categories', validRow('categories', 'sys:food')),
    );
    await db.customStatement(
      insertSql('accounts', validRow('accounts', 'acc1')),
    );
    await db.customStatement(
      insertSql('transactions', validRow('transactions', 'e1')),
    );
    await db.customStatement(
      insertSql('transactions', {
        ...validRow('transactions', 'i1'),
        'direction': "'income'",
      }),
    );
  });

  tearDownAll(() => edb.close());

  var n = 0;
  for (final k in cases) {
    test('${k.table}: ${k.what} → ${k.code ?? 'inserts'}', () async {
      n++;
      // A fresh id per case (balances are keyed by currency: use
      // three-letter ids there).
      final id = k.table == 'account_balances'
          ? String.fromCharCodes([
              65 + n ~/ 676 % 26,
              65 + n ~/ 26 % 26,
              65 + n % 26,
            ])
          : '${k.table}_$n';
      final row = <String, String>{...validRow(k.table, id)};
      // The control: the unchanged row inserts.
      if (k.table != 'transfer_pairs' &&
          k.table != 'offset_links' &&
          k.table != 'account_balances') {
        final controlId = '${id}_ok';
        expect(
          await failureOf(
            edb.db,
            insertSql(k.table, validRow(k.table, controlId)),
          ),
          isNull,
        );
      }
      for (final e in k.overrides.entries) {
        if (e.value == null) {
          row.remove(e.key);
        } else {
          row[e.key] = e.value == '@id' ? "'$id'" : e.value!;
        }
      }
      expect(await failureOf(edb.db, insertSql(k.table, row)), k.code);
      // Keep pair/link tables empty for the next case.
      await edb.db.customStatement('DELETE FROM transfer_pairs');
      await edb.db.customStatement('DELETE FROM offset_links');
    });
  }

  group('unique and partial unique indexes', () {
    test(
      'ux_accounts_default_cash: exactly one default cash account',
      () async {
        final db = edb.db;
        final cash = {
          ...validRow('accounts', 'cash1'),
          'kind': "'cash'",
          'last4': 'NULL',
          'institution_code': 'NULL',
          'is_default_cash': '1',
        };
        expect(await failureOf(db, insertSql('accounts', cash)), isNull);
        expect(
          await failureOf(
            db,
            insertSql('accounts', {...cash, 'id': "'cash2'"}),
          ),
          unique,
        );
        // Not default: any number of cash accounts.
        expect(
          await failureOf(
            db,
            insertSql('accounts', {
              ...cash,
              'id': "'cash3'",
              'is_default_cash': '0',
            }),
          ),
          isNull,
        );
        expect(
          await failureOf(
            db,
            insertSql('accounts', {
              ...cash,
              'id': "'cash4'",
              'is_default_cash': '0',
            }),
          ),
          isNull,
        );
      },
    );

    test('ux_accounts_inst_last4: same institution + last4 twice is refused, '
        'unless one is merged; NULL last4 never collides', () async {
      final db = edb.db;
      Map<String, String> card(String id, {String? merged}) => {
        ...validRow('accounts', id),
        'institution_code': "'UXB'",
        'last4': "'4321'",
        if (merged != null) 'merged_into_id': "'$merged'",
      };
      expect(await failureOf(db, insertSql('accounts', card('u1'))), isNull);
      expect(await failureOf(db, insertSql('accounts', card('u2'))), unique);
      expect(
        await failureOf(db, insertSql('accounts', card('u3', merged: 'u1'))),
        isNull,
      );
      // Another institution, same last4.
      expect(
        await failureOf(
          db,
          insertSql('accounts', {...card('u4'), 'institution_code': "'OTH'"}),
        ),
        isNull,
      );
      for (final id in ['n1', 'n2']) {
        expect(
          await failureOf(
            db,
            insertSql('accounts', {...card(id), 'last4': 'NULL'}),
          ),
          isNull,
        );
      }
    });

    test(
      'ux_raw_body_hash: a second message with the same hash is refused',
      () async {
        final row = validRow('raw_messages', 'r1');
        expect(await failureOf(edb.db, insertSql('raw_messages', row)), isNull);
        expect(
          await failureOf(
            edb.db,
            insertSql('raw_messages', {...row, 'id': "'r2'"}),
          ),
          unique,
        );
      },
    );

    test('account_balances: one row per account and currency', () async {
      final row = {...validRow('account_balances', 'GBP')};
      expect(
        await failureOf(edb.db, insertSql('account_balances', row)),
        isNull,
      );
      expect(
        await failureOf(edb.db, insertSql('account_balances', row)),
        primaryKey,
      );
    });

    test(
      'transfer_pairs: a transaction is in at most one pair per side',
      () async {
        final db = edb.db;
        for (final id in ['x1', 'x2', 'x3']) {
          await db.customStatement(
            insertSql('transactions', validRow('transactions', id)),
          );
        }
        final pair = validRow('transfer_pairs', 'p1')
          ..['out_txn_id'] = "'x1'"
          ..['in_txn_id'] = "'x2'";
        expect(await failureOf(db, insertSql('transfer_pairs', pair)), isNull);
        expect(
          await failureOf(
            db,
            insertSql('transfer_pairs', {
              ...pair,
              'id': "'p2'",
              'in_txn_id': "'x3'",
            }),
          ),
          unique,
        );
        expect(
          await failureOf(
            db,
            insertSql('transfer_pairs', {
              ...pair,
              'id': "'p3'",
              'out_txn_id': "'x3'",
            }),
          ),
          unique,
        );
        await db.customStatement('DELETE FROM transfer_pairs');
      },
    );

    test('offset_links: one link per (expense, source)', () async {
      final row = validRow('offset_links', 'l1')..['amount_minor'] = '10';
      expect(await failureOf(edb.db, insertSql('offset_links', row)), isNull);
      expect(
        await failureOf(
          edb.db,
          insertSql('offset_links', {...row, 'id': "'l2'"}),
        ),
        unique,
      );
      await edb.db.customStatement('DELETE FROM offset_links');
    });
  });

  test('every *_minor column is declared INTEGER', () async {
    final rows = await edb.db
        .customSelect(
          'SELECT m.name AS t, p.name AS c, p.type AS ty FROM sqlite_schema m '
          "JOIN pragma_table_info(m.name) p WHERE m.type = 'table' "
          "AND p.name LIKE '%\\_minor' ESCAPE '\\'",
        )
        .get();
    // 8 in v2 (T-017) + budgets.limit_minor, cycle_summaries.income_minor /
    // spend_minor, recurring_items.amount_minor (T-018).
    expect(rows.length, 12);
    for (final r in rows) {
      expect(r.read<String>('ty'), 'INTEGER', reason: r.read<String>('c'));
    }
  });
}
