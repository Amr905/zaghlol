// Generator hardening: input validation (SEC F2, F9).
import 'dart:convert';

import 'package:test/test.dart';

import '../../tool/gen_currencies.dart' as gen;
import 'iso4217_test_support.dart';

void main() {
  group('generator input validation (SEC F2, F9)', () {
    final eur = entryXml('EUR', '978', '2');

    test('a Pblshd with a newline or */ is rejected', () {
      final bad = [
        '2026-01-01\nimport "dart:io";\n//',
        '2026-01-01*/',
        '2026-01-01 ',
        '2026-1-1',
        '',
      ];
      for (final published in bad) {
        final source = listOneXml(published, eur);
        expect(() => gen.parseListOne(source), throwsFormatException);
        final encoded = jsonEncode(published);
        final json = '{"published": $encoded, "currencies": []}';
        expect(() => gen.parseJson(json), throwsFormatException);
      }
    });

    test('YYYY-MM and YYYY-MM-DD are accepted', () {
      for (final published in ['2025-09', '2025-09-30']) {
        final parsed = gen.parseListOne(listOneXml(published, eur));
        expect(parsed.published, published);
      }
    });

    test('render refuses an unvalidated table', () {
      final badDate = gen.CurrencyTable('2026-01-01\n//', [row('EUR', 978, 2)]);
      expect(() => gen.renderDart(badDate), throwsFormatException);
      expect(() => gen.renderJson(badDate), throwsFormatException);
      final badRow = gen.CurrencyTable('2026-01-01', [row('EUR', 978, 5)]);
      expect(() => gen.renderDart(badRow), throwsFormatException);
    });
  });
}
