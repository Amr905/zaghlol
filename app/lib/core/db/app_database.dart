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
import 'migrations/v2_financial_a.dart';
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

  /// The version steps, `from` → `to` (T-017: v1 → v2). Any other pair is
  /// refused before anything runs. Runs inside the upgrade transaction set
  /// up by [migration]; tests override this (FakeNextDatabase).
  @protected
  Future<void> upgradeSteps(Migrator m, int from, int to) async {
    if (from < 1 || from >= to || to != appSchemaVersion) {
      throw DbMigrationException(DbMigrationException.noMigrationPath);
    }
    await m.runMigrationSteps(
      from: from,
      to: to,
      steps: migrationSteps(from1To2: (m, _) => _from1To2()),
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

  /// A plain in-memory instance with the same schema for the comparison.
  /// Its own runtime type, so drift's "opened twice" debug warning stays
  /// quiet.
  @protected
  GeneratedDatabase referenceInstance(QueryExecutor e) => _SchemaReference(e);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
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
        await upgradeSteps(m, from, to);
        final broken = await customSelect('PRAGMA foreign_key_check').get();
        if (broken.isNotEmpty) {
          throw DbMigrationException(DbMigrationException.fkViolation);
        }
      });
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      if (validateSchema) await _checkSchema();
    },
  );

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
