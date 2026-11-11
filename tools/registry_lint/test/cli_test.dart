import 'dart:io';

import 'package:registry_lint/registry_lint.dart';
import 'package:test/test.dart';

const String _bundle = '../../packages/zaghlol_parsing/test/fixtures/registry';

Future<(int, String)> _run(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runRegistryLint(args, out, err);
  return (code, '$out$err');
}

Directory _copyBundle() {
  final tmp = Directory.systemTemp.createTempSync('registry_lint_test');
  void copy(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final e in from.listSync()) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is Directory) {
        copy(e, Directory('${to.path}/$name'));
      } else if (e is File) {
        e.copySync('${to.path}/$name');
      }
    }
  }

  copy(Directory('$_bundle/bundle'), Directory('${tmp.path}/bundle'));
  copy(Directory('$_bundle/sms'), Directory('${tmp.path}/sms'));
  return tmp;
}

void main() {
  test('clean test registry exits 0 and reports counts', () async {
    final (code, text) = await _run([
      '--registry',
      '$_bundle/bundle',
      '--fixtures',
      '$_bundle/sms',
    ]);
    expect(code, 0, reason: text);
    expect(text, contains('findings: 0'));
    expect(text, contains('2 institutions'));
  });

  test('an invalid regex makes it exit 1', () async {
    final tmp = _copyBundle();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final f = File('${tmp.path}/bundle/institutions/cib.json');
    f.writeAsStringSync(f.readAsStringSync().replaceFirst(r'\\$|€', r'\\$|€('));
    final (code, text) = await _run([
      '--registry',
      '${tmp.path}/bundle',
      '--fixtures',
      '${tmp.path}/sms',
    ]);
    expect(code, 1, reason: text);
    expect(text, contains('badRegex'));
  });

  test(
    'a fixture regression makes it exit 1 and prints no message text',
    () async {
      final tmp = _copyBundle();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final f = File('${tmp.path}/sms/nbe/card_purchase_ar_plain.json');
      f.writeAsStringSync(
        f.readAsStringSync().replaceFirst('"450.00"', '"451.00"'),
      );
      final (code, text) = await _run([
        '--registry',
        '${tmp.path}/bundle',
        '--fixtures',
        '${tmp.path}/sms',
      ]);
      expect(code, 1, reason: text);
      expect(
        text,
        contains('card_purchase_ar_plain.json: fixtureFailed (amount)'),
      );
      expect(text, isNot(contains('CARREFOUR')));
      expect(text, isNot(contains('450')));
    },
  );

  test('--write-manifest repairs a stale manifest', () async {
    final tmp = _copyBundle();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final m = File('${tmp.path}/bundle/registry_manifest.json');
    m.writeAsStringSync(
      '{"schema":1,"registryVersion":99,"institutions":["nbe"]}',
    );
    final args = [
      '--registry',
      '${tmp.path}/bundle',
      '--fixtures',
      '${tmp.path}/sms',
    ];
    expect((await _run(args)).$1, 1);
    final (code, text) = await _run([...args, '--write-manifest']);
    expect(code, 0, reason: text);
    expect(m.readAsStringSync(), contains('"registryVersion": 3'));
  });

  test('guard config is written and a stale copy is detected', () async {
    final tmp = _copyBundle();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final g = '${tmp.path}/guard.json';
    final args = [
      '--registry',
      '${tmp.path}/bundle',
      '--fixtures',
      '${tmp.path}/sms',
    ];
    expect((await _run([...args, '--guard-config', g])).$1, 0);
    expect((await _run([...args, '--check-guard-config', g])).$1, 0);
    File(g).writeAsStringSync('{}');
    final (code, text) = await _run([...args, '--check-guard-config', g]);
    expect(code, 1);
    expect(text, contains('guard-config-stale'));
  });

  test('missing registry directory and bad arguments exit 2', () async {
    expect((await _run(['--registry', '/nonexistent-dir-zz'])).$1, 2);
    expect((await _run(['--bogus'])).$1, 2);
    expect((await _run(['--min-fixtures', 'x'])).$1, 2);
    expect((await _run(['--help'])).$1, 0);
  });
}
