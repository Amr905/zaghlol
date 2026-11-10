// T-015: the set of files whose presence means "a database exists" for the key
// bootstrap (design note §3). T-016 owns the directory (db_directory.dart);
// this file owns the names and the wipe order. A database counts as present when ANY of these files exists, so a
// half-written restore, a leftover WAL or a migration temp file is never
// mistaken for a first run.

import 'dart:io';

/// The main database file name (database-schema.md).
const String dbFileName = 'zaghlol.db';

/// Bases of every database-like file the app may leave on disk: the live
/// database, a restore being staged (T-148/T-149) and a migration copy
/// (T-016). Each base also has SQLite's `-wal`, `-shm` and `-journal`.
const List<String> dbFileBases = [
  dbFileName,
  '$dbFileName.restore.tmp',
  migrateTmpFileName,
];

/// The pre-migration copy while it is being written (T-016 §6). Renamed to
/// [migrateTmpFileName] once complete; a leftover `.part` is always garbage.
const String migratePartFileName = '$dbFileName.migrate.part';

/// The confirmed pre-migration copy (T-016 §6): its presence at startup means
/// a migration was not confirmed, so the opener rolls back to it.
const String migrateTmpFileName = '$dbFileName.migrate.tmp';

/// SQLite companion suffixes.
const List<String> dbCompanionSuffixes = ['', '-wal', '-shm', '-journal'];

/// Every file name of the set.
final List<String> dbFileNames = [
  for (final base in dbFileBases)
    for (final suffix in dbCompanionSuffixes) '$base$suffix',
];

/// The orphan-wipe order (T-016 §4 step 3): every `-wal`, `-shm` and
/// `-journal` first, then the migration `.part`, the restore and migration
/// copies, and the **main file last**. A crash mid-wipe then still leaves the
/// main file, so the next launch sees an orphan again and resumes; if the main
/// file went first, a leftover WAL plus a still-valid key could silently
/// create an empty database without the restore notice.
final List<String> dbWipeOrder = [
  for (final suffix in dbCompanionSuffixes.skip(1))
    for (final base in dbFileBases.reversed) '$base$suffix',
  migratePartFileName,
  for (final base in dbFileBases.reversed)
    if (base != dbFileName) base,
  dbFileName,
];

/// The database file set in [directory].
final class DbFileSet {
  DbFileSet(this.directory);

  final Directory directory;

  /// The main database file.
  File get mainFile => File('${directory.path}/$dbFileName');

  /// The pre-migration copy being written (never part of [files]).
  File get migratePart => File('${directory.path}/$migratePartFileName');

  /// The confirmed pre-migration copy.
  File get migrateTmp => File('${directory.path}/$migrateTmpFileName');

  /// [mainFile]'s `-wal`, `-shm` and `-journal`.
  List<File> get mainCompanions => [
    for (final suffix in dbCompanionSuffixes.skip(1))
      File('${directory.path}/$dbFileName$suffix'),
  ];

  /// Every file in [dbWipeOrder], in that order.
  List<File> get wipeOrder => [
    for (final name in dbWipeOrder) File('${directory.path}/$name'),
  ];

  /// Every file of the set (existing or not).
  List<File> get files => [
    for (final name in dbFileNames) File('${directory.path}/$name'),
  ];

  /// True when any name of the set exists in [directory] (a file, or anything
  /// else under that name). False only on positive evidence: the directory
  /// was listed without error, or it does not exist. Throws
  /// [FileSystemException] when the directory can't be listed; the bootstrap
  /// treats that as "can't tell", never as "absent".
  Future<bool> anyExists() async {
    final names = dbFileNames.toSet();
    try {
      await for (final entry in directory.list(followLinks: false)) {
        if (names.contains(_baseName(entry.path))) return true;
      }
    } on PathNotFoundException {
      return false;
    }
    return false;
  }

  static String _baseName(String path) {
    var p = path;
    while (p.length > 1 && p.endsWith(Platform.pathSeparator)) {
      p = p.substring(0, p.length - 1);
    }
    return p.substring(p.lastIndexOf(Platform.pathSeparator) + 1);
  }
}
