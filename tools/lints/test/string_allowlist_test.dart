import 'package:test/test.dart';
import 'package:zaghlol_lints/src/string_allowlist.dart';

void main() {
  group('isTechnicalString', () {
    test('allows strings without letters, including Arabic-Indic digits', () {
      for (final s in ['', ' ', '·', ': ', '123', '٣٠', '٫', '/', '-']) {
        expect(isTechnicalString(s), isTrue, reason: s);
      }
    });

    test('allows identifiers, routes, assets and URIs', () {
      for (final s in [
        'home_tab',
        'a.b',
        'tab-1',
        '/home/:id',
        'assets/images/pigeon.png',
        'zaghlol.riv',
        'package:foo/bar.dart',
        'https://example.com/x',
      ]) {
        expect(isTechnicalString(s), isTrue, reason: s);
      }
    });

    test('rejects user-facing text in English and Arabic', () {
      for (final s in [
        'Hello',
        'Save',
        'save',
        'Total: ',
        'زغلول',
        'مرحبا يا باشا',
        'Hello world',
      ]) {
        expect(isTechnicalString(s), isFalse, reason: s);
      }
    });
  });

  test('stripGenerics', () {
    expect(stripGenerics('ValueKey<String>'), 'ValueKey');
    expect(stripGenerics('Image.asset'), 'Image.asset');
  });
}
