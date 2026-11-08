// Generator merge guards: --fresh and the exponent/numeric guard (CR2, CR3).
import 'package:test/test.dart';

import '../../tool/gen_currencies.dart' as gen;
import 'iso4217_test_support.dart';

void main() {
  final listOne = loadListOne();
  final committed = loadTable();

  group('--fresh guard (R2-2)', () {
    test('refused on a genuine committed table without --i-know', () {
      expect(committed.published, isNot(gen.sentinelPublished));
      expect(gen.freshAllowed(committed, iKnow: false), isFalse);
      expect(gen.freshAllowed(committed, iKnow: true), isTrue);
    });

    test('allowed for the placeholder table or when there is none', () {
      final placeholder = gen.CurrencyTable('2000-01-01', committed.rows);
      expect(gen.freshAllowed(placeholder, iKnow: false), isTrue);
      expect(gen.freshAllowed(null, iKnow: false), isTrue);
      final other = gen.CurrencyTable('2000-01-02', committed.rows);
      expect(gen.freshAllowed(other, iKnow: false), isFalse);
    });
  });

  group('excluded codes (D-67)', () {
    test('XAD is skipped even though List One flags it IsFund', () {
      expect(gen.excludedCodes, contains('XAD'));
      const name = '<CcyNm IsFund="true">Arab Accounting Dinar</CcyNm>';
      final xad = '$name<Ccy>XAD</Ccy><CcyNbr>396</CcyNbr>';
      final entry = '<CcyNtry>$xad<CcyMnrUnts>2</CcyMnrUnts></CcyNtry>';
      final eur = entryXml('EUR', '978', '2');
      final xml = listOneXml('2026-09-17', '$eur$entry');
      final parsed = gen.parseListOne(xml);
      expect(parsed.rows.map((r) => r.code), ['EUR']);
    });

    test('the genuine snapshot lists XAD; the table does not', () {
      final raw = loadListOneSource();
      expect(raw, contains('<Ccy>XAD</Ccy>'));
      expect(listOne.rows.map((r) => r.code), isNot(contains('XAD')));
      expect(committed.rows.map((r) => r.code), isNot(contains('XAD')));
    });

    test('a committed XAD row is dropped, not kept as historic', () {
      final withXad = [...committed.rows, row('XAD', 396, 2)];
      final previous = gen.CurrencyTable('2026-09-17', withXad);
      final merged = merge(listOne, previous);
      expect(merged.rows.map((r) => r.code), isNot(contains('XAD')));
      expect(merged.rows.length, committed.rows.length);
    });

    test('render refuses a table containing XAD', () {
      final bad = gen.CurrencyTable('2026-09-17', [row('XAD', 396, 2)]);
      expect(() => gen.renderJson(bad), throwsFormatException);
      expect(() => gen.renderDart(bad), throwsFormatException);
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
