// Generator hardening: row validation and ignored XML sections (SEC F2,
// F9).
import 'dart:convert';

import 'package:test/test.dart';

import '../../tool/gen_currencies.dart' as gen;
import 'iso4217_test_support.dart';

Map<String, Object> jsonRow() {
  final item = <String, Object>{'code': 'EUR', 'numeric': 978};
  item['exponent'] = 2;
  item['status'] = 'active';
  return item;
}

String jsonDoc(Map<String, Object> item) {
  final doc = {'published': '2025-09-01', 'currencies': [item]};
  return jsonEncode(doc);
}

void main() {
  group('generator row validation (SEC F2, F9)', () {
    final eur = entryXml('EUR', '978', '2');

    test('exponent 0..4 and numeric 1..999 are enforced', () {
      final cases = ['978:5', '978:10', '000:2', '1000:2'];
      for (final c in cases) {
        final [numeric, minorUnits] = c.split(':');
        final entry = entryXml('EUR', numeric, minorUnits);
        final source = listOneXml('2025-09-01', entry);
        expect(() => gen.parseListOne(source), throwsFormatException);
      }
    });

    test('comments, CDATA and DOCTYPE are ignored', () {
      final hidden = entryXml('ZZZ', '123', '2');
      final doctype = '<!DOCTYPE ISO_4217 [ <!ENTITY x "y"> ]>';
      final comment = '<!-- <ISO_4217 Pblshd="1999-01-01"> -->';
      final body = '$eur<!-- $hidden --><![CDATA[$hidden]]>';
      final table = listOneXml('2025-09-01', body);
      final parsed = gen.parseListOne('$doctype\n$comment\n$table');
      expect(parsed.published, '2025-09-01');
      expect(parsed.rows.map((r) => r.code), ['EUR']);
    });

    test('parseJson accepts a valid row', () {
      final parsed = gen.parseJson(jsonDoc(jsonRow()));
      expect(parsed.rows.single.code, 'EUR');
    });

    test('parseJson rejects malformed rows', () {
      void expectRejected(String key, Object value) {
        final item = jsonRow();
        item[key] = value;
        expect(() => gen.parseJson(jsonDoc(item)), throwsFormatException);
      }

      expectRejected('code', 'eur');
      expectRejected('code', 'EU\nR');
      expectRejected('exponent', 9);
      expectRejected('exponent', -1);
      expectRejected('numeric', '978');
      expectRejected('numeric', 0);
      expectRejected('status', 'gone');
      expectRejected('fund', 'yes');
    });
  });
}
