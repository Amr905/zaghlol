import 'dart:io';

import 'package:registry_lint/registry_lint.dart';
import 'package:test/test.dart';

// The bundled registry (app/assets/registry) against its synthetic fixtures
// (app/test/fixtures/sms): schema, regex safety, every fixture's expected
// output, cross-matches, >= 4 fixtures per template and Guard last-4 parity.
const String _registry = '../../app/assets/registry';
const String _fixtures = '../../app/test/fixtures/sms';

void main() {
  test('bundled registry lints clean against its fixtures', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runRegistryLint(
      ['--registry', _registry, '--fixtures', _fixtures],
      out,
      err,
    );
    expect(code, 0, reason: '$out$err');
    expect('$out', contains('findings: 0'));
    expect('$out', contains('47 institutions'));
  });

  test('every institution has an Arabic and an English template', () {
    final dir = Directory('$_registry/institutions');
    final files = dir.listSync().whereType<File>().toList();
    expect(files.length, greaterThanOrEqualTo(47));
    for (final f in files) {
      final text = f.readAsStringSync();
      expect(text, contains('"lang": "ar"'), reason: f.path);
      expect(text, contains('"lang": "en"'), reason: f.path);
    }
  });
}
