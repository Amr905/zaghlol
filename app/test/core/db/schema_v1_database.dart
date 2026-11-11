// T-017: a real schema-v1 file (T-016's committed dump: `db_meta` only), to
// test the v1 → v2 step on an encrypted file. Usable on devices too, so the
// statements are embedded; a host test checks them against
// drift_schemas/app_database/drift_schema_v1.json.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart' show DbKeyMaterial;

import '../../support/synthetic_key.dart';

/// The v1 dump's `fixed_sql` (sqlite dialect).
const List<String> v1Sql = [
  'CREATE TABLE IF NOT EXISTS "db_meta" ("key" TEXT NOT NULL, '
      '"value" TEXT NOT NULL, PRIMARY KEY ("key"));',
];

/// A drift database at version 1 whose create runs [v1Sql] (plus [extra]).
class V1Database extends GeneratedDatabase {
  V1Database(super.executor, {this.extra = const []});

  final List<String> extra;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      for (final sql in [...v1Sql, ...extra]) {
        await customStatement(sql);
      }
    },
  );
}

/// Creates an encrypted v1 file at [file] (key seed [seed]) holding the
/// `db_meta` rows [meta] and any [extra] statements, then closes it.
Future<void> makeV1File(
  File file, {
  int seed = 61,
  Map<String, String> meta = const {'marker': 'v1'},
  List<String> extra = const [],
}) async {
  await file.parent.create(recursive: true);
  final db = V1Database(
    openEncryptedExecutor(
      file,
      DbKeyMaterial.copyOf(syntheticKeyBytes(seed)),
      inBackground: false,
    ),
    extra: extra,
  );
  for (final e in meta.entries) {
    await db.customStatement('INSERT INTO db_meta (key, value) VALUES (?, ?)', [
      e.key,
      e.value,
    ]);
  }
  await db.close();
}
