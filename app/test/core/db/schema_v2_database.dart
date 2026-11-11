// T-018: a real, populated schema-v2 file (T-017's schema: the v1 dump plus
// the frozen v1 → v2 statements, which a host test checks against the v2
// dump), to test the v2 → v3 step on an encrypted file. Usable on devices
// too. All rows synthetic.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart' show DbKeyMaterial;
import 'package:zaghlol/core/db/migrations/v2_financial_a.dart';

import '../../support/synthetic_key.dart';
import 'schema_v1_database.dart';

/// A fixed epoch-ms time (2026-11-01T10:00Z).
const int _t0 = 1793527200000;

/// Synthetic v2 rows: a category, an account, an expense with a merchant
/// and note (indexed by the v2 FTS triggers), an income, a split
/// participant and an offset link naming it, a raw message.
const List<String> v2SampleRows = [
  "INSERT INTO db_meta (key, value) VALUES ('marker', 'v2')",
  'INSERT INTO categories (id, system_code, name_ar, name_en, icon, color, '
      "bucket, sort) VALUES ('sys:food', 'food', 'أكل', 'Food', 'food', "
      "'#0F7A55', 'needs', 1)",
  'INSERT INTO accounts (id, institution_code, kind, label, last4, '
      "default_currency, created_at, updated_at) VALUES ('acc1', 'BNK', "
      "'debit', 'Synthetic', '1234', 'EGP', $_t0, $_t0)",
  'INSERT INTO raw_messages (id, channel, body, body_hash, received_at, '
      "parse_status, registry_version, created_at) VALUES ('m1', 'sms', "
      "'SYNTHETIC body m1', '0000000000000000000000000000000000000000000000000000000000000001', $_t0, 'parsed', 1, $_t0)",
  'INSERT INTO transactions (id, account_id, raw_message_id, source, '
      'direction, amount_minor, currency, occurred_at, occurred_tz_offset_min, '
      'merchant_raw, merchant_norm, category_id, category_source, note, '
      "created_at, updated_at) VALUES ('e1', 'acc1', 'm1', 'sms', 'expense', "
      "125050, 'EGP', $_t0, 120, 'صيدلية العزبي', 'ezaby', 'sys:food', "
      "'catalog', 'synthetic note', $_t0, $_t0)",
  'INSERT INTO transactions (id, account_id, source, direction, '
      'amount_minor, currency, occurred_at, occurred_tz_offset_min, '
      "category_source, created_at, updated_at) VALUES ('i1', 'acc1', "
      "'manual', 'income', 50000, 'EGP', $_t0, 120, 'none', $_t0, $_t0)",
  'INSERT INTO transactions (id, account_id, source, direction, '
      'amount_minor, currency, occurred_at, occurred_tz_offset_min, '
      "category_source, created_at, updated_at) VALUES ('e2', 'acc1', "
      "'manual', 'expense', 100000, 'EGP', $_t0, 120, 'none', $_t0, $_t0)",
  'INSERT INTO split_participants (id, expense_txn_id, name, share_minor, '
      "created_at) VALUES ('p1', 'e1', 'Synthetic friend', 25000, $_t0)",
  'INSERT INTO offset_links (id, kind, expense_txn_id, source_txn_id, '
      "amount_minor, participant_id, created_at) VALUES ('l1', "
      "'reimbursement', 'e1', 'i1', 25000, 'p1', $_t0)",
];

/// A drift database at version 2 whose create runs the v1 statements, the
/// frozen v2 step, [v2SampleRows] when [populated], and [extra].
class V2Database extends GeneratedDatabase {
  V2Database(super.executor, {this.populated = true, this.extra = const []});

  final bool populated;
  final List<String> extra;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      for (final sql in [
        ...v1Sql,
        for (final (_, s) in v2AddedObjects) s,
        if (populated) ...v2SampleRows,
        ...extra,
      ]) {
        await customStatement(sql);
      }
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

/// Creates an encrypted v2 file at [file] (key seed [seed]), then closes it.
Future<void> makeV2File(
  File file, {
  int seed = 61,
  bool populated = true,
  List<String> extra = const [],
}) async {
  await file.parent.create(recursive: true);
  final db = V2Database(
    openEncryptedExecutor(
      file,
      DbKeyMaterial.copyOf(syntheticKeyBytes(seed)),
      inBackground: false,
    ),
    populated: populated,
    extra: extra,
  );
  // Opening runs onCreate.
  await db.customSelect('SELECT 1').get();
  await db.close();
}
