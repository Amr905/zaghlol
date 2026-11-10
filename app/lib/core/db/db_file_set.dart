// T-015: the set of files whose presence means "a database exists" for the key
// bootstrap (design note §3). T-016 owns the directory; this file owns the
// names. A database counts as present when ANY of these files exists, so a
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
  '$dbFileName.migrate.tmp',
];

/// SQLite companion suffixes.
const List<String> dbCompanionSuffixes = ['', '-wal', '-shm', '-journal'];

/// Every file name of the set.
final List<String> dbFileNames = [
  for (final base in dbFileBases)
    for (final suffix in dbCompanionSuffixes) '$base$suffix',
];

/// The database file set in [directory].
final class DbFileSet {
  DbFileSet(this.directory);

  final Directory directory;

  /// The main database file.
  File get mainFile => File('${directory.path}/$dbFileName');

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
