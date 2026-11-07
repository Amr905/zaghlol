// Generator hardening: row validation and ignored XML sections (SEC F2,
// F9).
import 'dart:convert';

import 'package:test/test.dart';

import '../../tool/gen_currencies.dart' as gen;
import 'iso4217_test_support.dart';

void main() {
  group('generator row validation (SEC F2, F9)', () {
    final eur = entryXml('EUR', '978', '2');

    test('exponent 0..4 and numeric 1..999 are enforced', () {
      final bad = [
        entryXml('EUR', '978', '5'),
        entryXml('EUR', '978', '10'),
        entryXml('EUR', '000', '2'),
        entryXml('EUR', '1000', '2'),
      ];
      for (final entry in bad) {
        final source = listOneXml('2025-09-01', entry);
        expect(() => gen.parseListOne(source), throwsFormatException);
      }
    });

    test('comments, CDATA and DOCTYPE are ignored', () {
      final hidden = entryXml('ZZZ', '123', '2');
      final parts = [
        '<!DOCTYPE ISO_4217 [ <!ENTITY x "y"> ]>',
        '<!-- <ISO_4217 Pblshd="1999-01-01"> -->',
        listOneXml('2025-09-01', '$eur<!-- $hidden --><![CDATA[$hidden]]>'),
      ];
      final source = parts.join('\n');
      final parsed = gen.parseListOne(source);
      expect(parsed.published, '2025-09-01');
      expect(parsed.rows.map((r) => r.code), ['EUR']);
    });

    test('parseJson rejects malformed rows', () {
      final base = <String, Object>{
        'code': 'EUR',
        'numeric': 978,
        'exponent': 2,
        'status': 'active',
      };
      final good = {'published': '2025-09-01', 'currencies': [base]};
      expect(gen.parseJson(jsonEncode(good)).rows.single.code, 'EUR');
      final overrides = <Map<String, Object>>[
        {'code': 'eur'},
        {'code': 'EU\nR'},
        {'exponent': 9},
        {'exponent': -1},
        {'numeric': '978'},
        {'numeric': 0},
        {'status': 'gone'},
        {'fund': 'yes'},
      ];
      for (final override in overrides) {
        final item = {...base, ...override};
        final doc = {'published': '2025-09-01', 'currencies': [item]};
        expect(() => gen.parseJson(jsonEncode(doc)), throwsFormatException);
      }
    });
  });
}
