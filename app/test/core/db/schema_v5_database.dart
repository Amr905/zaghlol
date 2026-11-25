// T-266: a real, populated schema-v5 file, to test the v5 → v6 step on an
// encrypted file. The schema is the committed v5 dump (a test checks the
// helper against it); the rows are the v2, v3 and v4 sample rows plus a
// second debit card, a bank account, a wallet and a recurring dismissal. All
// rows synthetic.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart' show DbKeyMaterial;

import '../../support/synthetic_key.dart';
import 'app_database_test.dart' show dumpSql;
import 'schema_v2_database.dart' show v2SampleRows;
import 'schema_v3_database.dart' show v3SampleRows;
import 'schema_v4_database.dart' show v4SampleRows;

/// A fixed epoch-ms time (2026-11-01T10:00Z).
const int _t0 = 1793527200000;

/// Rows on top of the v2–v4 samples.
const List<String> v5SampleRows = [
  'INSERT INTO accounts (id, institution_code, kind, label, last4, '
      "default_currency, created_at, updated_at) VALUES ('acc5', 'BNK', "
      "'account', 'Current', NULL, 'EGP', $_t0, $_t0)",
  'INSERT INTO accounts (id, institution_code, kind, label, last4, '
      "default_currency, created_at, updated_at) VALUES ('card5', 'BNK', "
      "'debit', 'Debit', '9876', 'EGP', $_t0, $_t0)",
  'INSERT INTO accounts (id, institution_code, kind, label, last4, '
      "default_currency, created_at, updated_at) VALUES ('wal5', 'WLT', "
      "'wallet', 'Wallet', NULL, 'EGP', $_t0, $_t0)",
  'INSERT INTO account_balances (account_id, currency, balance_minor, '
      "as_of) VALUES ('acc5', 'EGP', 1234500, $_t0)",
  'INSERT INTO recurring_dismissals (dismissal_key, dismissed_at) '
      "VALUES ('streamco|acc1|EGP', $_t0)",
];

/// A drift database at version 5: the committed v5 dump, then the sample
/// rows when [populated], then [extra].
class V5Database extends GeneratedDatabase {
  V5Database(super.executor, {this.populated = true, this.extra = const []});

  final bool populated;
  final List<String> extra;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      for (final sql in [
        ...dumpSql(5),
        if (populated) ...[
          ...v2SampleRows,
          ...v3SampleRows,
          ...v4SampleRows,
          ...v5SampleRows,
        ],
        ...extra,
      ]) {
        await customStatement(sql);
      }
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

/// Creates an encrypted v5 file at [file] (key seed [seed]), then closes it.
Future<void> makeV5File(
  File file, {
  int seed = 61,
  bool populated = true,
  List<String> extra = const [],
}) async {
  await file.parent.create(recursive: true);
  final db = V5Database(
    openEncryptedExecutor(
      file,
      DbKeyMaterial.copyOf(syntheticKeyBytes(seed)),
      inBackground: false,
    ),
    populated: populated,
    extra: extra,
  );
  await db.customSelect('SELECT 1').get();
  await db.close();
}
