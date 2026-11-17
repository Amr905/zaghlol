// FU-130: the rooted-device warning (FR-SEC-07) is shown once per install,
// not once per launch. The mark lives in `db_meta`, a device table that a
// backup never carries, so a restore on another phone still warns there.

import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/app_database_providers.dart';

/// `db_meta` key set once the warning was shown on this install.
const String rootedWarningShownKey = 'rooted_warning_shown';

abstract interface class RootedWarningMemo {
  /// True when the warning was already shown on this install.
  Future<bool> seen();

  /// Records that the warning was shown.
  Future<void> markSeen();
}

final class DbRootedWarningMemo implements RootedWarningMemo {
  DbRootedWarningMemo(this._db);

  final Future<AppDatabase> Function() _db;

  @override
  Future<bool> seen() async {
    final db = await _db();
    final row = await (db.select(
      db.dbMeta,
    )..where((t) => t.key.equals(rootedWarningShownKey))).getSingleOrNull();
    return row != null;
  }

  @override
  Future<void> markSeen() async {
    final db = await _db();
    await db
        .into(db.dbMeta)
        .insert(
          DbMetaCompanion.insert(key: rootedWarningShownKey, value: '1'),
          mode: InsertMode.insertOrReplace,
        );
  }
}

final rootedWarningMemoProvider = Provider<RootedWarningMemo>(
  (ref) => DbRootedWarningMemo(() => ref.read(appDatabaseProvider.future)),
  name: 'rootedWarningMemoProvider',
);
