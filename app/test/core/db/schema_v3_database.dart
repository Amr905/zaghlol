// T-019: a real, populated schema-v3 file (T-018's schema: the v1 dump plus
// the frozen v1 → v2 and v2 → v3 statements, which host tests check against
// the v2 and v3 dumps), to test the v3 → v4 step on an encrypted file. Rows
// in every v3 table, including the four v4 rebuilds. All rows synthetic.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart' show DbKeyMaterial;
import 'package:zaghlol/core/db/migrations/v2_financial_a.dart';
import 'package:zaghlol/core/db/migrations/v3_financial_b.dart';

import '../../support/synthetic_key.dart';
import 'schema_v1_database.dart';
import 'schema_v2_database.dart' show v2SampleRows;

/// A fixed epoch-ms time (2026-11-01T10:00Z).
const int _t0 = 1793527200000;

/// The v3 statements after the v2 ones: the frozen v2 → v3 step.
List<String> get v3StepSql => [
  for (final name in v3DroppedTriggers) 'DROP TRIGGER $name',
  for (final (_, s) in v3AddedObjects) s,
  ...v3FtsOptions,
];

/// Synthetic v3 rows (on top of [v2SampleRows]): catalog merchants with
/// aliases (indexed by the alias FTS triggers), keywords and meta, merchant
/// rules of every kind, a budget, a fired alert, a cycle summary, recurring
/// items (one with every optional column, a REAL 5.0 stored as 5) and their
/// occurrences.
const List<String> v3SampleRows = [
  "UPDATE db_meta SET value = 'v3' WHERE key = 'marker'",
  'INSERT INTO catalog_merchants (id, canonical, name_ar, name_en, '
      "category_code, logo_key, version) VALUES (812, 'Koshary Synthetic', "
      "'كشري تجريبي', 'Koshary Synthetic', 'dining', 'logo_812', 3)",
  'INSERT INTO catalog_merchants (id, canonical, category_code, version) '
      "VALUES (77, 'Pharmacy Synthetic', 'health', 1)",
  'INSERT INTO catalog_aliases (merchant_id, alias_norm, "match") '
      "VALUES (812, 'koshary synthetic', 'exact')",
  'INSERT INTO catalog_aliases (merchant_id, alias_norm, "match") '
      "VALUES (77, 'ezaby', 'prefix')",
  'INSERT INTO catalog_aliases (merchant_id, alias_norm, "match") '
      "VALUES (77, 'pharmacy synthetic', 'token')",
  'INSERT INTO catalog_keywords (keyword_norm, lang, category_code, weight) '
      "VALUES ('صيدليه', 'ar', 'health', 60)",
  'INSERT INTO catalog_keywords (keyword_norm, lang, category_code, weight) '
      "VALUES ('pharmacy', 'en', 'health', 55)",
  'INSERT INTO catalog_meta (id, version, applied_at, signature_kid) '
      "VALUES (1, 42, $_t0, 'kid-synthetic')",
  'INSERT INTO merchant_rules (id, match_kind, match_value, category_id, '
      "created_at, last_applied_at) VALUES ('r1', 'merchant_norm', 'ezaby', "
      "'sys:food', $_t0, $_t0)",
  'INSERT INTO merchant_rules (id, match_kind, match_value, category_id, '
      "created_at) VALUES ('r2', 'catalog_merchant', '812', 'sys:food', $_t0)",
  'INSERT INTO merchant_rules (id, match_kind, match_value, category_id, '
      "created_at) VALUES ('r3', 'counterparty', 'شخص تجريبي', 'sys:food', "
      '$_t0)',
  'INSERT INTO budgets (id, category_id, currency, limit_minor, period, '
      "created_at) VALUES ('b1', 'sys:food', 'EGP', 500000, 'cycle', $_t0)",
  'INSERT INTO fired_alerts (kind, subject_id, period_key, threshold, '
      "fired_at) VALUES ('budget_threshold', 'b1', '2026-11-25', 80, $_t0)",
  'INSERT INTO cycle_summaries (cycle_start, currency, income_minor, '
      "spend_minor, by_category, computed_at) VALUES ('2026-11-25', 'EGP', "
      "50000, 125050, '{\"sys:food\":125050}', $_t0)",
  'INSERT INTO recurring_items (id, kind, status, name, merchant_norm, '
      'account_id, amount_minor, currency, cadence, due_day, next_due_date, '
      'total_count, paid_count, reminder_days, created_at) VALUES (\'ri1\', '
      "'installment', 'active', 'Synthetic installment', 'ezaby', 'acc1', "
      "9900, 'EGP', 'monthly', 5.0, '2026-12-05', 12, 2, 3, $_t0)",
  'INSERT INTO recurring_items (id, kind, status, name, amount_minor, '
      'currency, cadence, cadence_days, created_at) VALUES (\'ri2\', '
      "'gameya', 'suggested', 'Synthetic gameya', 100000, 'EGP', "
      "'custom_days', 14, $_t0)",
  'INSERT INTO recurring_occurrences (item_id, due_date, txn_id, paid_at) '
      "VALUES ('ri1', '2026-11-05', 'e1', $_t0)",
  'INSERT INTO recurring_occurrences (item_id, due_date) '
      "VALUES ('ri1', '2026-12-05')",
];

/// A drift database at version 3 whose create runs the v1 statements, the
/// frozen v2 and v3 steps, the sample rows when [populated], and [extra].
class V3Database extends GeneratedDatabase {
  V3Database(super.executor, {this.populated = true, this.extra = const []});

  final bool populated;
  final List<String> extra;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      for (final sql in [
        ...v1Sql,
        for (final (_, s) in v2AddedObjects) s,
        ...v3StepSql,
        if (populated) ...[...v2SampleRows, ...v3SampleRows],
        ...extra,
      ]) {
        await customStatement(sql);
      }
    },
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}

/// Creates an encrypted v3 file at [file] (key seed [seed]), then closes it.
Future<void> makeV3File(
  File file, {
  int seed = 61,
  bool populated = true,
  List<String> extra = const [],
}) async {
  await file.parent.create(recursive: true);
  final db = V3Database(
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
