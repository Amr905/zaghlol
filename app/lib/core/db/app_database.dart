// T-016: the app's encrypted drift database (database-schema §0/§4, ADR-002;
// design note §1, §5, §6). The schema lives in schema/app_schema.dart; this
// class adds the migration strategy and `db_meta` access.
//
// It is opened only through openAppDatabase (app_database_opener.dart), with
// an executor from openEncryptedExecutor: nothing else issues `PRAGMA key`.
// Nothing here logs.

import 'package:drift/drift.dart';
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/foundation.dart' show kDebugMode, protected;

import 'db_errors.dart';
import 'fts_options.dart';
import 'migrations/v2_financial_a.dart';
import 'migrations/v3_financial_b.dart';
import 'migrations/v4_financial_c.dart';
import 'migrations/v5_recurring_cadence.dart';
import 'migrations/v6_linked_account.dart';
import 'migrations/v7_llm_categorise.dart';
import 'schema/app_schema.dart';
import 'schema/app_schema.steps.dart';
import 'schema_shape.dart';

export 'schema/app_schema.dart';

/// `db_meta` key of the one-time "your data was reset" line (PO 2026-11-10,
/// Q2; D-70). Written with the very first create after an orphan wipe.
const String restoreNoticeDueKey = 'restore_notice_due';

/// Runs the version steps (the generated `migrationSteps`,
/// schema/app_schema.steps.dart).
typedef UpgradeSteps = Future<void> Function(Migrator m, int from, int to);

class AppDatabase extends AppSchema {
  /// [restoreNoticeDue]: record `restore_notice_due = 1` in the same
  /// transaction that creates the schema (only takes effect on create).
  /// [validateSchema]: after every open, compare the live schema with a
  /// freshly created one (default: debug builds and tests).
  AppDatabase(
    super.e, {
    bool restoreNoticeDue = false,
    this.validateSchema = kDebugMode,
  }) : _markRestoreNotice = restoreNoticeDue;

  final bool _markRestoreNotice;

  /// Compare the live schema with a fresh one after every open.
  final bool validateSchema;

  int? _upgradeFrom;

  /// The version this open tried to upgrade from (null: no upgrade ran).
  /// Diag fields only (FU-050).
  int? get attemptedUpgradeFrom => _upgradeFrom;

  /// The version steps, `from` → `to` (T-017: v1 → v2; T-018: v2 → v3;
  /// T-019: v3 → v4; T-196: v4 → v5; T-266: v5 → v6; T-356: v6 → v7).
  /// Any other pair is refused before anything runs. Runs inside the upgrade
  /// transaction set up by [migration]; tests override this
  /// (FakeNextDatabase).
  @protected
  Future<void> upgradeSteps(Migrator m, int from, int to) async {
    if (from < 1 || from >= to || to != appSchemaVersion) {
      throw DbMigrationException(DbMigrationException.noMigrationPath);
    }
    await m.runMigrationSteps(
      from: from,
      to: to,
      steps: migrationSteps(
        from1To2: (m, _) => _from1To2(),
        from2To3: (m, _) => _from2To3(),
        from3To4: (m, _) => _from3To4(),
        from4To5: (m, _) => _from4To5(),
        from5To6: (m, _) => _from5To6(),
        from6To7: (m, _) => _from6To7(),
      ),
    );
  }

  /// v1 → v2 (T-017): the frozen statements of the v2 dump
  /// (migrations/v2_financial_a.dart), not drift_dev's `Schema2`, which
  /// misses three of the objects.
  Future<void> _from1To2() async {
    for (final (_, sql) in v2AddedObjects) {
      await customStatement(sql);
    }
  }

  /// v2 → v3 (T-018): the frozen statements of
  /// migrations/v3_financial_b.dart (drop the changed triggers, create the
  /// new and changed objects, set the FTS5 options).
  Future<void> _from2To3() async {
    for (final name in v3DroppedTriggers) {
      await customStatement('DROP TRIGGER $name');
    }
    for (final (_, sql) in v3AddedObjects) {
      await customStatement(sql);
    }
    for (final sql in v3FtsOptions) {
      await customStatement(sql);
    }
  }

  /// v3 → v4 (T-019): the frozen statements of
  /// migrations/v4_financial_c.dart. Each rebuilt table is copied by column
  /// name into its v4 form; the copy must hold exactly the old row count
  /// before the old table is dropped (else the step fails and the opener
  /// restores the pre-migration copy). Foreign keys are off here (set by
  /// [migration]); the opener's `foreign_key_check` runs before commit.
  Future<void> _from3To4() async {
    for (final r in v4Rebuilds) {
      final cols = r.columns.map((c) => '"$c"').join(', ');
      await customStatement(r.createTemp);
      await customStatement(
        'INSERT INTO "${r.temp}" ($cols) SELECT $cols FROM "${r.table}"',
      );
      final counts = await customSelect(
        'SELECT (SELECT count(*) FROM "${r.table}") AS a, '
        '(SELECT count(*) FROM "${r.temp}") AS b',
      ).getSingle();
      if (counts.read<int>('a') != counts.read<int>('b')) {
        throw DbMigrationException(DbMigrationException.rowCountMismatch);
      }
      await customStatement('DROP TABLE "${r.table}"');
      await customStatement('ALTER TABLE "${r.temp}" RENAME TO "${r.table}"');
      for (final sql in r.indexes) {
        await customStatement(sql);
      }
    }
    for (final (_, sql) in v4AddedObjects) {
      await customStatement(sql);
    }
  }

  /// v4 → v5 (T-196): the frozen statements of
  /// migrations/v5_recurring_cadence.dart. `recurring_items` is rebuilt (wider
  /// cadence CHECK, new `auto_added_at`) with the same row-count check as
  /// [_from3To4]; then the new table is created.
  Future<void> _from4To5() async {
    const r = v5RecurringRebuild;
    final cols = r.columns.map((c) => '"$c"').join(', ');
    await customStatement(r.createTemp);
    await customStatement(
      'INSERT INTO "${r.temp}" ($cols) SELECT $cols FROM "${r.table}"',
    );
    final counts = await customSelect(
      'SELECT (SELECT count(*) FROM "${r.table}") AS a, '
      '(SELECT count(*) FROM "${r.temp}") AS b',
    ).getSingle();
    if (counts.read<int>('a') != counts.read<int>('b')) {
      throw DbMigrationException(DbMigrationException.rowCountMismatch);
    }
    await customStatement('DROP TABLE "${r.table}"');
    await customStatement('ALTER TABLE "${r.temp}" RENAME TO "${r.table}"');
    for (final sql in r.indexes) {
      await customStatement(sql);
    }
    for (final (_, sql) in v5AddedObjects) {
      await customStatement(sql);
    }
  }

  /// v5 → v6 (T-266): the frozen statements of
  /// migrations/v6_linked_account.dart: `accounts.linked_account_id` (added,
  /// NULL for every row) and its partial index.
  Future<void> _from5To6() async {
    await customStatement(v6AddLinkedAccountColumn);
    for (final (_, sql) in v6AddedObjects) {
      await customStatement(sql);
    }
  }

  /// v6 → v7 (T-356): the frozen statements of
  /// migrations/v7_llm_categorise.dart. The view and the two triggers that
  /// read `transactions` are dropped first (a rename refuses to run while
  /// they name a missing table); `transactions` and `outbox` are rebuilt
  /// (wider CHECKs) with the rowid and every column copied by name and the
  /// same row-count check as [_from3To4]; the dropped view and triggers come
  /// back unchanged; then the two new tables are created.
  Future<void> _from6To7() async {
    for (final (kind, name) in v7DroppedDependents) {
      await customStatement('DROP $kind "$name"');
    }
    for (final r in v7Rebuilds) {
      final cols = ['rowid', for (final c in r.columns) '"$c"'].join(', ');
      await customStatement(r.createTemp);
      await customStatement(
        'INSERT INTO "${r.temp}" ($cols) SELECT $cols FROM "${r.table}"',
      );
      final counts = await customSelect(
        'SELECT (SELECT count(*) FROM "${r.table}") AS a, '
        '(SELECT count(*) FROM "${r.temp}") AS b',
      ).getSingle();
      if (counts.read<int>('a') != counts.read<int>('b')) {
        throw DbMigrationException(DbMigrationException.rowCountMismatch);
      }
      await customStatement('DROP TABLE "${r.table}"');
      await customStatement('ALTER TABLE "${r.temp}" RENAME TO "${r.table}"');
      for (final sql in r.indexes) {
        await customStatement(sql);
      }
    }
    for (final (_, sql) in v7RestoredObjects) {
      await customStatement(sql);
    }
    for (final (_, sql) in v7AddedObjects) {
      await customStatement(sql);
    }
  }

  /// A plain in-memory instance with the same schema for the comparison.
  /// Its own runtime type, so drift's "opened twice" debug warning stays
  /// quiet.
  @protected
  GeneratedDatabase referenceInstance(QueryExecutor e) => _SchemaReference(e);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
      // Data in the FTS config tables, which createAll doesn't set (T-018).
      for (final sql in ftsOptionStatements) {
        await customStatement(sql);
      }
      if (_markRestoreNotice) {
        await into(dbMeta).insert(
          DbMetaCompanion.insert(key: restoreNoticeDueKey, value: '1'),
          mode: InsertMode.insertOrReplace,
        );
      }
    }),
    onUpgrade: (m, from, to) async {
      _upgradeFrom = from;
      // Off outside the transaction (it is a no-op inside one), so table
      // rebuilds can't cascade; the check below catches what they break.
      await customStatement('PRAGMA foreign_keys = OFF');
      await transaction(() async {
        // FREEZE-FIX: only violations the steps add fail the upgrade. A row
        // that already pointed nowhere before the steps (data an older build
        // left behind) is kept as it is; failing on it would refuse the
        // upgrade on every launch with no way out.
        final before = await _fkViolationCounts();
        await upgradeSteps(m, from, to);
        final after = await _fkViolationCounts();
        for (final MapEntry(:key, :value) in after.entries) {
          if (value > (before[key] ?? 0)) {
            throw DbMigrationException(DbMigrationException.fkViolation);
          }
        }
      });
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      if (validateSchema) await _checkSchema();
    },
  );

  /// `PRAGMA foreign_key_check` as a count per (child table, parent table).
  /// Not per rowid or FK index: a table rebuild may renumber either.
  Future<Map<String, int>> _fkViolationCounts() async {
    final counts = <String, int>{};
    for (final r in await customSelect('PRAGMA foreign_key_check').get()) {
      final key = '${r.data['table']}\u0000${r.data['parent']}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _checkSchema() async {
    final reference = referenceInstance(NativeDatabase.memory());
    final List<String> expected;
    try {
      expected = await schemaShapeOf(reference);
    } finally {
      await reference.close();
    }
    if (!sameSchemaShape(await schemaShapeOf(this), expected)) {
      throw DbMigrationException(DbMigrationException.schemaMismatch);
    }
  }

  /// True when the one-time restore notice is still due (the startup screen
  /// shows it, then calls [clearRestoreNotice]).
  Future<bool> restoreNoticeDue() async {
    final row = await (select(
      dbMeta,
    )..where((t) => t.key.equals(restoreNoticeDueKey))).getSingleOrNull();
    return row?.value == '1';
  }

  /// Deletes the restore notice row. Idempotent.
  Future<void> clearRestoreNotice() =>
      (delete(dbMeta)..where((t) => t.key.equals(restoreNoticeDueKey))).go();
}

final class _SchemaReference extends AppDatabase {
  _SchemaReference(super.e) : super(validateSchema: false);
}
