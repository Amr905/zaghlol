// T-016 §2 (S-7): the one stable directory of zaghlol.db.
//
// `<applicationSupport>/db`: Android `files/db`, iOS
// `Library/Application Support/db`. Both are excluded from OS backup and
// device transfer by the T-165 rules (every Android domain is excluded with
// path "."; iOS sets isExcludedFromBackup on Application Support at launch),
// so no extra native code is needed. Deviation from the task text
// ("no-backup dir"): `noBackupFilesDir` would need a channel method for no
// gain. A host test pins the path and the backup rules that cover it.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The database directory name under the application support directory.
const String dbDirectoryName = 'db';

/// The database directory for [appSupport]. The only place the path is
/// built: `dbDirectoryProvider` and the executor (via `DbFileSet.mainFile`)
/// both come from it.
Directory dbDirectoryFor(Directory appSupport) =>
    Directory('${appSupport.path}/$dbDirectoryName');

/// Resolves the database directory on this device. Startup overrides
/// `dbDirectoryProvider` with the result. [appSupport] is injectable for
/// tests.
Future<Directory> resolveDbDirectory({
  Future<Directory> Function() appSupport = getApplicationSupportDirectory,
}) async => dbDirectoryFor(await appSupport());
