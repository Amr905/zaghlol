// T-149 design note §2: every table of the schema is either carried by the
// backup (FR-BAK-06) or kept on the device (FR-BAK-07), never both, never
// neither. A new table fails here until it is classified.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/features/backup/application/snapshot_tables.dart';

void main() {
  test('every schema table is classified exactly once', () async {
    final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    addTearDown(db.close);
    final rows = await db
        .customSelect(
          "SELECT name, sql FROM sqlite_schema WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    final virtual = {
      for (final r in rows)
        if ((r.read<String>('sql')).startsWith('CREATE VIRTUAL'))
          r.read<String>('name'),
    };
    final shadows = {
      for (final f in ftsTables)
        for (final s in ftsShadowSuffixes) '$f$s',
    };
    final ordinary = {for (final r in rows) r.read<String>('name')}
        .difference(virtual)
        .difference(shadows);

    expect(virtual, ftsTables.toSet());
    expect(deviceTables.toSet().intersection(backedUpTables.toSet()), isEmpty);
    expect(ordinary, {...deviceTables, ...backedUpTables});
  });

  test('FR-BAK-07 exclusions are device tables', () {
    for (final t in [
      'secure_state', // keys, entitlement, flags
      'catalog_merchants', // the downloaded catalog
      'catalog_aliases',
      'catalog_keywords',
      'catalog_meta',
    ]) {
      expect(deviceTables, contains(t));
    }
    // FR-BAK-06 items are carried.
    for (final t in [
      'transactions',
      'raw_messages',
      'accounts',
      'budgets',
      'recurring_items',
      'split_participants',
      'offset_links',
      'assets',
      'price_quotes',
      'zakah_ledger',
      'settings',
      'categories',
      'merchant_rules',
      'custom_templates',
      'review_items',
      'ignore_rules',
      'voice_usage',
    ]) {
      expect(backedUpTables, contains(t));
    }
  });
}
