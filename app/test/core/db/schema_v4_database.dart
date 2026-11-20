// T-196: a real, populated schema-v4 file, to test the v4 → v5 step on an
// encrypted file. The schema is the committed v4 dump (host tests check the
// helper against it); the rows are the v2 and v3 sample rows plus recurring
// items with every cadence v4 knows. All rows synthetic.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart' show DbKeyMaterial;

import '../../support/synthetic_key.dart';
import 'app_database_test.dart' show dumpSql;
import 'schema_v2_database.dart' show v2SampleRows;
import 'schema_v3_database.dart' show v3SampleRows;

/// A fixed epoch-ms time (2026-11-01T10:00Z).
const int _t0 = 1793527200000;

/// Rows on top of the v2 and v3 samples: one active item per old cadence,
/// each with an occurrence, a completed counted item and a hand-typed bill
/// without an account.
const List<String> v4SampleRows = [
  'INSERT INTO recurring_items (id, kind, status, name, merchant_norm, '
      'account_id, amount_minor, currency, cadence, due_day, next_due_date, '
      'reminder_days, created_at) VALUES '
      "('rm', 'subscription', 'active', 'Monthly', 'streamco', 'acc1', "
      "19900, 'EGP', 'monthly', 5, '2026-12-05', 3, $_t0)",
  'INSERT INTO recurring_items (id, kind, status, name, merchant_norm, '
      'account_id, amount_minor, currency, cadence, due_day, next_due_date, '
      'reminder_days, created_at) VALUES '
      "('ry', 'subscription', 'active', 'Yearly', 'domainco', 'acc1', "
      "250000, 'EGP', 'yearly', 3, '2027-03-03', 3, $_t0)",
  'INSERT INTO recurring_items (id, kind, status, name, merchant_norm, '
      'amount_minor, currency, cadence, next_due_date, reminder_days, '
      "created_at) VALUES ('rw', 'bill', 'active', 'Weekly', 'cleaner', "
      "5000, 'USD', 'weekly', '2026-11-08', 1, $_t0)",
  'INSERT INTO recurring_items (id, kind, status, name, account_id, '
      'amount_minor, currency, cadence, total_count, paid_count, '
      "created_at) VALUES ('rc', 'installment', 'completed', 'Done', 'acc1', "
      "100, 'KWD', 'monthly', 2, 2, $_t0)",
  'INSERT INTO recurring_occurrences (item_id, due_date, paid_at) '
      "VALUES ('rm', '2026-11-05', $_t0)",
  'INSERT INTO recurring_occurrences (item_id, due_date, paid_at) '
      "VALUES ('ry', '2026-03-03', $_t0)",
];

/// A drift database at version 4: the committed v4 dump, then the sample
/// rows when [populated], then [extra].
class V4Database extends GeneratedDatabase {
  V4Database(super.executor, {this.populated = true, this.extra = const []});

  final bool populated;
  final List<String> extra;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      for (final sql in [
        ...dumpSql(4),
        if (populated) ...[...v2SampleRows, ...v3SampleRows, ...v4SampleRows],
        ...extra,
      ]) {
        await customStatement(sql);
      }
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

/// Creates an encrypted v4 file at [file] (key seed [seed]), then closes it.
Future<void> makeV4File(
  File file, {
  int seed = 61,
  bool populated = true,
  List<String> extra = const [],
}) async {
  await file.parent.create(recursive: true);
  final db = V4Database(
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
