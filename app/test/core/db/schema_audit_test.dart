// T-019: whole-schema audits of the v4 ("v1 final") schema.
// * Money (task follow-up from the T-012 design note): every `*_minor`
//   column is CHECKed to be an SQLite integer within ±(2^53 − 1), has a
//   registered currency partner, and where that partner is nullable a CHECK
//   ties the pair (both NULL or both set, or "amount set ⇒ currency set"
//   for asset values sharing `assets.currency`).
// * Every INTEGER column of a table T-019 created or rebuilt is
//   `typeof = 'integer'`-checked (the constraint sweep proves it refuses 1.5).
// * AC2: every table (incl. FTS tables, not their shadow tables) has a DAO
//   that touches it.
// * FU-071 m-4: tools/drift_codegen pins the same drift and sqlite3 as the
//   app's lock, so generated code matches the runtime.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/schema_shape.dart';

import 'financial_c_constraints_test.dart' show v4NewTables, v4RebuiltTables;

/// `table.minor_column` → its currency column. A new money column must be
/// added here (and get the CHECKs), or the audit fails.
const Map<String, String> moneyPartners = {
  'accounts.credit_limit_minor': 'default_currency',
  'account_balances.balance_minor': 'currency',
  'account_balances.available_minor': 'currency',
  'transactions.amount_minor': 'currency',
  'transactions.original_amount_minor': 'original_currency',
  'transactions.balance_after_minor': 'currency',
  // In the expense's currency (offset triggers enforce it).
  'offset_links.amount_minor': '-> transactions.currency',
  'split_participants.share_minor': '-> transactions.currency',
  'budgets.limit_minor': 'currency',
  'cycle_summaries.income_minor': 'currency',
  'cycle_summaries.spend_minor': 'currency',
  'recurring_items.amount_minor': 'currency',
  'assets.principal_minor': 'currency',
  'assets.manual_value_minor': 'currency',
  'assets.purchase_price_minor': 'purchase_currency',
  'price_quotes.price_minor': 'currency',
  // A currency code or a gold symbol (then milligrams).
  'networth_snapshots.assets_minor': 'unit',
  'networth_snapshots.liabilities_minor': 'unit',
  'zakah_ledger.amount_minor': 'unit',
  'zakah_ledger.paid_minor': 'unit',
};

/// Table → the DAO file (lib/core/db/…) that reads or writes it.
const Map<String, String> daoOf = {
  'db_meta': 'app_database.dart',
  'categories': 'daos/categories_dao.dart',
  'accounts': 'daos/accounts_dao.dart',
  'account_balances': 'daos/accounts_dao.dart',
  'raw_messages': 'daos/raw_messages_dao.dart',
  'transactions': 'daos/transactions_dao.dart',
  'transactions_fts_src': 'daos/transactions_dao.dart',
  'transactions_fts': 'daos/transactions_dao.dart',
  'transactions_fts_short': 'daos/transactions_dao.dart',
  'transfer_pairs': 'daos/transfers_dao.dart',
  'split_participants': 'daos/transfers_dao.dart',
  'offset_links': 'daos/offset_links_dao.dart',
  'catalog_merchants': 'daos/catalog_dao.dart',
  'catalog_aliases': 'daos/catalog_dao.dart',
  'catalog_alias_fts': 'daos/catalog_dao.dart',
  'catalog_keywords': 'daos/catalog_dao.dart',
  'catalog_meta': 'daos/catalog_dao.dart',
  'merchant_rules': 'daos/merchant_rules_dao.dart',
  'budgets': 'daos/budgets_dao.dart',
  'fired_alerts': 'daos/fired_alerts_dao.dart',
  'cycle_summaries': 'daos/cycle_summaries_dao.dart',
  'recurring_items': 'daos/recurring_dao.dart',
  'recurring_occurrences': 'daos/recurring_dao.dart',
  'assets': 'daos/assets_dao.dart',
  'zakah_ledger': 'daos/assets_dao.dart',
  'price_quotes': 'daos/prices_dao.dart',
  'fx_rates': 'daos/prices_dao.dart',
  'networth_snapshots': 'daos/prices_dao.dart',
  'ignore_rules': 'daos/capture_controls_dao.dart',
  'capture_senders': 'daos/capture_controls_dao.dart',
  'custom_templates': 'daos/capture_controls_dao.dart',
  'review_items': 'daos/review_items_dao.dart',
  'settings': 'daos/settings_dao.dart',
  'secure_state': 'daos/settings_dao.dart',
  'outbox': 'daos/outbox_dao.dart',
  'voice_usage': 'daos/misc_daos.dart',
  'undo_batches': 'daos/misc_daos.dart',
  'diag_log': 'daos/misc_daos.dart',
};

String camel(String snake) {
  final parts = snake.split('_');
  return parts.first +
      parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

/// The `version:` of [package] in a pubspec.lock text.
String? lockedVersion(String lock, String package) => RegExp(
  '^  $package:\\n(?:    .*\\n|      .*\\n)*?    version: "([^"]+)"',
  multiLine: true,
).firstMatch(lock)?.group(1);

void main() {
  late AppDatabase db;
  late Map<String, String> sqlOf;
  late Map<String, List<Map<String, Object?>>> columnsOf;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    final tables = await db
        .customSelect(
          "SELECT name, sql FROM sqlite_schema WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    sqlOf = {
      for (final t in tables) t.read<String>('name'): t.read<String>('sql'),
    };
    columnsOf = {
      for (final name in sqlOf.keys)
        name: [
          for (final r
              in await db.customSelect('PRAGMA table_xinfo("$name")').get())
            r.data,
        ],
    };
  });

  tearDownAll(() => db.close());

  test('every *_minor column: integer CHECK within ±(2^53 − 1), a '
      'registered currency partner, and a pair CHECK when the partner is '
      'nullable', () {
    final found = <String>{};
    for (final MapEntry(key: table, value: cols) in columnsOf.entries) {
      final checks = checkClausesOf(sqlOf[table]!);
      for (final col in cols) {
        final name = col['name']! as String;
        if (!name.endsWith('_minor')) continue;
        final id = '$table.$name';
        found.add(id);
        expect(
          checks.any(
            (c) =>
                c.contains("typeof($name) = 'integer'") &&
                c.contains('9007199254740991'),
          ),
          isTrue,
          reason: '$id has no integer/range CHECK',
        );
        final partner = moneyPartners[id];
        expect(partner, isNotNull, reason: '$id has no registered currency');
        if (partner!.startsWith('->')) continue;
        final p = cols.firstWhere((c) => c['name'] == partner);
        if (p['notnull'] == 1) continue;
        expect(
          checks.any(
            (c) =>
                c.contains('$name is null') &&
                c.contains(partner) &&
                !c.contains('typeof'),
          ),
          isTrue,
          reason: '$id: nullable partner $partner without a pair CHECK',
        );
      }
    }
    expect(found, moneyPartners.keys.toSet());
  });

  test('every INTEGER column of a table T-019 created or rebuilt has a '
      'typeof CHECK (rowid aliases are integers by construction)', () {
    for (final table in [...v4NewTables, ...v4RebuiltTables]) {
      final checks = checkClausesOf(sqlOf[table]!);
      final cols = columnsOf[table]!;
      final pks = cols.where((c) => c['pk'] != 0).length;
      for (final col in cols) {
        if (col['type'] != 'INTEGER') continue;
        if (col['pk'] == 1 && pks == 1) continue;
        final name = col['name']! as String;
        final typed = checks.any(
          (c) => c.contains("typeof($name) = 'integer'"),
        );
        final enumerated = checks.any(
          (c) => c.contains('$name in(0,1)') || c.contains('$name in (0,1)'),
        );
        expect(typed || enumerated, isTrue, reason: '$table.$name');
      }
    }
  });

  test('every table has a DAO that touches it (FTS shadow tables are '
      "SQLite's own)", () {
    final virtuals = {
      for (final MapEntry(:key, :value) in sqlOf.entries)
        if (value.toUpperCase().startsWith('CREATE VIRTUAL TABLE')) key,
    };
    const shadow = ['_data', '_idx', '_docsize', '_config', '_content'];
    final tables = {
      for (final t in sqlOf.keys)
        if (!virtuals.any((v) => shadow.any((s) => t == '$v$s'))) t,
    };
    expect(tables, daoOf.keys.toSet());
    for (final MapEntry(key: table, value: file) in daoOf.entries) {
      final src = File('lib/core/db/$file').readAsStringSync();
      final touches =
          src.contains('_db.${camel(table)}') ||
          src.contains('dbMeta') && table == 'db_meta' ||
          RegExp('\\b$table\\b').hasMatch(src);
      expect(touches, isTrue, reason: '$table in $file');
    }
  });

  test('FU-071 m-4: tools/drift_codegen locks the same drift and sqlite3 '
      'as the app', () {
    final root = File('../pubspec.lock').readAsStringSync();
    final codegen = File('../tools/drift_codegen/pubspec.lock')
        .readAsStringSync();
    for (final package in ['drift', 'sqlite3']) {
      final a = lockedVersion(root, package);
      final b = lockedVersion(codegen, package);
      expect(a, isNotNull, reason: package);
      expect(b, a, reason: package);
    }
    expect(lockedVersion('  drift:\n    version: "1.2.3"\n', 'drift'), '1.2.3');
  });
}
