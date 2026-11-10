// T-016 §2 (S-7): the database lives in one stable directory,
// `<applicationSupport>/db`, which the T-165 backup rules exclude on both
// platforms. A rename of the directory or the file breaks this test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/db_directory.dart';
import 'package:zaghlol/core/db/db_file_set.dart';

String withoutComments(String xml) =>
    xml.replaceAll(RegExp('<!--.*?-->', dotAll: true), '');

void main() {
  final support = Directory('/data/user/0/app.zaghlol/files');

  test('(a) the file set directory is the parent of the executor file', () {
    final files = DbFileSet(dbDirectoryFor(support));
    // The opener hands files.mainFile to the executor (no other path).
    final executorFile = files.mainFile;
    expect(files.directory.path, executorFile.parent.path);
    expect(files.directory.path, '${support.path}/db');
  });

  test('(b) golden: the path ends with /db/zaghlol.db', () {
    expect(
      DbFileSet(dbDirectoryFor(support)).mainFile.path,
      endsWith('/db/zaghlol.db'),
    );
    expect(dbDirectoryName, 'db');
    expect(dbFileName, 'zaghlol.db');
  });

  test('resolveDbDirectory appends db to the support directory', () async {
    final dir = await resolveDbDirectory(appSupport: () async => support);
    expect(dir.path, '${support.path}/db');
  });

  group('(c) the backup rules still cover <applicationSupport>/db', () {
    // path_provider: Android getApplicationSupportDirectory() is
    // Context.getFilesDir() (domain "file"); iOS is
    // Library/Application Support.
    const domains = [
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
      'device_root',
      'device_file',
      'device_database',
      'device_sharedpref',
    ];

    test('Android data_extraction_rules: cloud-backup and device-transfer '
        'exclude domain "file" (and every other) at path "."', () {
      final xml = withoutComments(
        File('android/app/src/main/res/xml/data_extraction_rules.xml')
            .readAsStringSync(),
      );
      for (final section in ['cloud-backup', 'device-transfer']) {
        final body = RegExp(
          '<$section[^>]*>(.*?)</$section>',
          dotAll: true,
        ).firstMatch(xml)!.group(1)!;
        expect(body.contains('<include'), isFalse, reason: section);
        for (final d in domains) {
          expect(
            body.contains('<exclude domain="$d" path="." />'),
            isTrue,
            reason: '$section $d',
          );
        }
      }
    });

    test('Android backup_rules (API 26-30) exclude domain "file"', () {
      final xml = withoutComments(
        File('android/app/src/main/res/xml/backup_rules.xml')
            .readAsStringSync(),
      );
      expect(xml.contains('<include'), isFalse);
      expect(xml.contains('<exclude domain="file" path="." />'), isTrue);
    });

    test('iOS: Application Support is in the launch-time exclusion set', () {
      final swift = File('ios/Shared/BackupExclusion.swift').readAsStringSync();
      final body = RegExp(
        r'static func appContainerDirectories\(.*?\n  \}',
        dotAll: true,
      ).firstMatch(swift)!.group(0)!;
      expect(body.contains('.applicationSupportDirectory'), isTrue);
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(delegate.contains('ZaghlolDirectories.applyAll()'), isTrue);
    });
  });
}
