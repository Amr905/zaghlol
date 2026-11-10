import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_lints/src/runner.dart';

void main() {
  test('countLinted counts only lib/ files', () {
    final files = parseTree(['test/fixtures']);
    expect(countLinted(files), greaterThan(10));
  });

  group('CLI', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('zl_cli'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<ProcessResult> lint(List<String> roots) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/zaghlol_lints.dart', ...roots],
    );

    test(
      'a root with no lib/ files exits non-zero with a clear message',
      () async {
        File('${tmp.path}/a.dart').writeAsStringSync('int x = 1;');
        final r = await lint([tmp.path]);
        expect(r.exitCode, isNot(0));
        expect(r.stderr, contains('no lintable files'));
      },
    );

    test('an empty root among good roots still fails', () async {
      final r = await lint(['test/fixtures/lib/money', tmp.path]);
      expect(r.exitCode, 2);
    });

    test('a compliant root passes and reports the scanned count', () async {
      Directory('${tmp.path}/lib').createSync();
      File('${tmp.path}/lib/a.dart').writeAsStringSync('int x = 1;');
      final r = await lint([tmp.path]);
      expect(r.exitCode, 0);
      expect(r.stdout, contains('1 file(s) scanned'));
    });
  });
}
