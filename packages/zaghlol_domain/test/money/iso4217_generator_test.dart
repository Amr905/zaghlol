// Generator hardening: input validation and merge guards (SEC F2, F9;
// CR2, CR3).
import 'dart:convert';

import 'package:test/test.dart';

import '../../tool/gen_currencies.dart' as gen;
import 'iso4217_test_support.dart';

void main() {
  final listOne = loadListOne();

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

  group('merge guards (CR2, CR3)', () {
    test('without a previous table (--fresh) the result is the snapshot', () {
      final fresh = merge(listOne, null);
      expect(fresh.rows, listOne.rows);
      expect(fresh.rows.every((r) => r.active), isTrue);
    });

    test('a changed exponent or numeric throws unless allowed', () {
      final previous = gen.CurrencyTable('2025-01-01', [row('EUR', 978, 2)]);
      final newExponent = gen.CurrencyTable('2026-01-01', [row('EUR', 978, 3)]);
      final newNumeric = gen.CurrencyTable('2026-01-01', [row('EUR', 979, 2)]);
      expect(() => merge(newExponent, previous), throwsFormatException);
      expect(() => merge(newNumeric, previous), throwsFormatException);
      final allowed = mergeAllowing(newExponent, previous, {'EUR'});
      expect(allowed.rows.single.exponent, 3);
      final usd = {'USD'};
      final throws = throwsFormatException;
      expect(() => mergeAllowing(newExponent, previous, usd), throws);
      final same = gen.CurrencyTable('2026-01-01', [row('EUR', 978, 2)]);
      expect(merge(same, previous).rows.single.exponent, 2);
    });
  });
}
