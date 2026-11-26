// T-356: a real, populated schema-v6 file, to test the v6 → v7 step on an
// encrypted file. The schema is the committed v6 dump (a test checks the
// helper against it); the rows are the v2–v5 sample rows plus transactions
// with every v6 category source and every nullable column filled, an
// internal transfer pair, a custom category, a user merchant rule, one
// outbox row of each v6 kind and a rowid gap. All rows synthetic.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart' show DbKeyMaterial;

import '../../support/synthetic_key.dart';
import 'app_database_test.dart' show dumpSql;
import 'schema_v2_database.dart' show v2SampleRows;
import 'schema_v3_database.dart' show v3SampleRows;
import 'schema_v4_database.dart' show v4SampleRows;
import 'schema_v5_database.dart' show v5SampleRows;

/// A fixed epoch-ms time (2026-11-01T10:00Z).
const int _t0 = 1793527200000;

const String _txnCols =
    'INSERT INTO transactions (id, account_id, source, direction, '
    'amount_minor, currency, occurred_at, occurred_tz_offset_min, '
    'merchant_raw, merchant_norm, category_id, category_source, '
    'is_user_verified, created_at, updated_at';

/// Rows on top of the v2–v5 samples.
const List<String> v6SampleRows = [
  'INSERT INTO categories (id, system_code, name_ar, name_en, icon, color, '
      "bucket, sort) VALUES ('sys:dining', 'dining', 'مطاعم', 'Dining', "
      "'dining', '#0F7A55', 'wants', 2)",
  'INSERT INTO categories (id, name_ar, name_en, icon, color, bucket, '
      "is_custom, sort) VALUES ('cus:1', 'قهوة', 'Coffee', 'coffee', "
      "'#FFB86B', 'wants', 1, 3)",
  // Every column of a transaction filled (user-set, verified).
  'INSERT INTO transactions (id, account_id, raw_message_id, source, '
      'direction, status, amount_minor, currency, original_amount_minor, '
      'original_currency, occurred_at, occurred_tz_offset_min, merchant_raw, '
      'merchant_norm, catalog_merchant_id, counterparty_kind, '
      'counterparty_value, category_id, category_source, is_user_verified, '
      'is_internal, reference_no, balance_after_minor, template_id, '
      'parse_confidence, dedupe_key, note, deleted_at, created_at, '
      "updated_at) VALUES ('u6', 'acc1', 'm1', 'sms', 'expense', 'pending', "
      "18500, 'EGP', 375, 'USD', $_t0, 180, 'زاوية كافيه', 'zawya coffee', "
      "7, 'merchant', 'Zawya', 'cus:1', 'user', 1, 0, 'REF-6', -9007199254740991, "
      "'tpl6', 0.875, 'dk6', 'ملاحظة', NULL, $_t0, $_t0 + 1)",
  // A row hard-deleted after a later insert leaves a rowid gap, so a rebuild that did not copy
  // the rowid would renumber every later transaction (AC2 sees it).
  "$_txnCols) VALUES ('gone6', 'acc1', 'manual', 'expense', 100, 'EGP', "
      "$_t0, 0, NULL, NULL, NULL, 'none', 0, $_t0, $_t0)",
  "$_txnCols, deleted_at) VALUES ('r6', 'acc1', 'manual', 'expense', 990, "
      "'KWD', $_t0, 180, 'Rule Shop', 'rule shop', 'sys:food', 'user_rule', "
      '0, $_t0, $_t0, $_t0 + 5)',
  "DELETE FROM transactions WHERE id = 'gone6'",
  "$_txnCols) VALUES ('h6', 'acc5', 'notification', 'expense', 1500, 'JPY', "
      "$_t0 - 86400000, -300, 'Keyword Cafe', 'keyword cafe', 'sys:dining', "
      "'heuristic', 0, $_t0, $_t0)",
  "$_txnCols) VALUES ('n6', 'acc5', 'share', 'refund', 0, 'EGP', $_t0, 0, "
      "NULL, NULL, NULL, 'none', 0, $_t0, $_t0)",
  // An internal transfer pair (the pair row needs both legs first).
  "$_txnCols, is_internal) VALUES ('to6', 'acc1', 'sms', 'transfer_out', "
      "200000, 'EGP', $_t0, 120, NULL, NULL, NULL, 'none', 0, $_t0, $_t0, 1)",
  "$_txnCols, is_internal) VALUES ('ti6', 'acc5', 'sms', 'transfer_in', "
      "200000, 'EGP', $_t0, 120, NULL, NULL, NULL, 'none', 0, $_t0, $_t0, 1)",
  'INSERT INTO transfer_pairs (id, out_txn_id, in_txn_id, kind, created_at) '
      "VALUES ('tp6', 'to6', 'ti6', 'manual', $_t0)",
  "UPDATE transactions SET transfer_pair_id = 'tp6' WHERE id IN ('to6', 'ti6')",
  'INSERT INTO merchant_rules (id, match_kind, match_value, category_id, '
      "created_at, last_applied_at) VALUES ('rule6', 'merchant_norm', "
      "'zawya coffee', 'cus:1', $_t0, $_t0)",
  'INSERT INTO outbox (id, kind, payload, created_at, attempts, '
      "next_attempt_at) VALUES ('o1', 'contribution', "
      '\'{"merchant":"zawya coffee","category":"dining"}\', $_t0, 2, '
      '$_t0 + 3600000)',
  'INSERT INTO outbox (id, kind, payload, created_at) VALUES '
      "('o2', 'bank_request', '{\"name\":\"Synthetic Bank\"}', $_t0)",
  'INSERT INTO outbox (id, kind, payload, created_at) VALUES '
      "('o3', 'purchase_verify', '{}', $_t0 + 1)",
];

/// A drift database at version 6: the committed v6 dump, then the sample
/// rows when [populated], then [extra].
class V6Database extends GeneratedDatabase {
  V6Database(super.executor, {this.populated = true, this.extra = const []});

  final bool populated;
  final List<String> extra;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      for (final sql in [
        ...dumpSql(6),
        if (populated) ...[
          ...v2SampleRows,
          ...v3SampleRows,
          ...v4SampleRows,
          ...v5SampleRows,
          ...v6SampleRows,
        ],
        ...extra,
      ]) {
        await customStatement(sql);
      }
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

/// Creates an encrypted v6 file at [file] (key seed [seed]), then closes it.
Future<void> makeV6File(
  File file, {
  int seed = 61,
  bool populated = true,
  List<String> extra = const [],
}) async {
  await file.parent.create(recursive: true);
  final db = V6Database(
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
