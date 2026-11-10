// T-015: DbFileSet decides "a database exists" (design note §3). False only
// on positive evidence; an unreadable directory throws.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/db_file_set.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zaghlol_t015_files_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('the set covers the database, its companions and temp copies', () {
    expect(dbFileNames, contains('zaghlol.db'));
    for (final suffix in ['-wal', '-shm', '-journal']) {
      expect(dbFileNames, contains('zaghlol.db$suffix'));
    }
    expect(dbFileNames, contains('zaghlol.db.restore.tmp'));
    expect(dbFileNames, contains('zaghlol.db.migrate.tmp'));
    expect(dbFileNames.toSet().length, dbFileNames.length);
    expect(DbFileSet(dir).files.length, dbFileNames.length);
    expect(DbFileSet(dir).mainFile.path, endsWith('/zaghlol.db'));
  });

  test('a missing directory means no database', () async {
    final missing = Directory('${dir.path}/missing');
    expect(await DbFileSet(missing).anyExists(), isFalse);
  });

  test('an empty directory or unrelated files mean no database', () async {
    expect(await DbFileSet(dir).anyExists(), isFalse);
    File('${dir.path}/zaghlol.dbx').writeAsStringSync('x');
    File('${dir.path}/other.db').writeAsStringSync('x');
    Directory('${dir.path}/sub').createSync();
    File('${dir.path}/sub/zaghlol.db').writeAsStringSync('x');
    expect(await DbFileSet(dir).anyExists(), isFalse);
  });

  for (final name in dbFileNames) {
    test('"$name" alone means a database exists', () async {
      File('${dir.path}/$name').writeAsBytesSync(const []);
      expect(await DbFileSet(dir).anyExists(), isTrue);
    });
  }

  test('a directory with a database name counts too', () async {
    Directory('${dir.path}/zaghlol.db-wal').createSync();
    expect(await DbFileSet(dir).anyExists(), isTrue);
  });

  test('a path that is not a directory throws (never "absent")', () async {
    final file = File('${dir.path}/plain')..writeAsStringSync('x');
    await expectLater(
      DbFileSet(Directory(file.path)).anyExists(),
      throwsA(isA<FileSystemException>()),
    );
  });
}
