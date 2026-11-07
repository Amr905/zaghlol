// Verifies the bundled ISO 4217 table against the pinned List One snapshot,
// an independent exponent oracle, and the append-only rule (T-012).
import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../tool/gen_currencies.dart' as gen;

/// Every code of the first committed table. A refresh may add codes or mark
/// them historic, never delete them; extend this list when codes are added.
const String _baselineCodes = '''
AED AFN ALL AMD AOA ARS AUD AWG AZN BAM BBD BDT BGN BHD BIF BMD BND BOB BOV
BRL BSD BTN BWP BYN BZD CAD CDF CHE CHF CHW CLF CLP CNY COP COU CRC CUC CUP
CVE CZK DJF DKK DOP DZD EGP ERN ETB EUR FJD FKP GBP GEL GHS GIP GMD GNF GTQ
GYD HKD HNL HTG HUF IDR ILS INR IQD IRR ISK JMD JOD JPY KES KGS KHR KMF KPW
KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK MNT MOP MRU MUR
MVR MWK MXN MXV MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN
PYG QAR RON RSD RUB RWF SAR SBD SCR SDG SEK SGD SHP SLE SOS SRD SSP STN SVC
SYP SZL THB TJS TMT TND TOP TRY TTD TWD TZS UAH UGX USD USN UYI UYU UYW UZS
VED VES VND VUV WST XAF XCD XCG XOF XPF YER ZAR ZMW ZWG
''';

void main() {
  final xml = File(gen.xmlPath).readAsStringSync();
  final json = File(gen.jsonPath).readAsStringSync();
  final dart = File(gen.dartPath).readAsStringSync();
  final listOne = gen.parseListOne(xml);
  final table = gen.parseJson(json);

  group('generated files are in sync', () {
    test('currencies.json == merge(List One snapshot, committed table)', () {
      final merged = gen.mergeAppendOnly(listOne, table);
      expect(gen.renderJson(merged), json);
    });

    test('iso4217_table.g.dart is byte-identical to a fresh render', () {
      expect(gen.renderDart(table), dart);
    });

    test('the runtime table equals currencies.json', () {
      final runtime = Currency.all.toList();
      expect(runtime.length, table.rows.length);
      for (var i = 0; i < runtime.length; i++) {
        final c = runtime[i];
        final row = table.rows[i];
        expect(c.code, row.code);
        expect(c.numeric, row.numeric);
        expect(c.exponent, row.exponent);
        expect(c.status == CurrencyStatus.active, row.active);
        expect(c.isFund, row.fund);
      }
    });
  });

  group('verification 1: active entries equal the List One snapshot', () {
    test('every active JSON entry matches List One', () {
      final byCode = {for (final r in listOne.rows) r.code: r};
      for (final row in table.rows.where((r) => r.active)) {
        expect(byCode[row.code], row, reason: row.code);
      }
    });

    test('every List One code with numeric minor units is active', () {
      final active = table.rows.where((r) => r.active).map((r) => r.code);
      for (final row in listOne.rows) {
        expect(active, contains(row.code));
      }
      expect(table.published, listOne.published);
    });
  });

  group('verification 2: independent exponent oracle', () {
    const oracle = {
      3: ['KWD', 'BHD', 'OMR', 'JOD', 'TND', 'LYD', 'IQD'],
      0: ['JPY', 'KRW', 'VND', 'CLP', 'ISK', 'XOF', 'XAF', 'UGX', 'PYG'],
      2: ['EGP', 'USD', 'EUR', 'SAR', 'AED', 'QAR', 'GBP'],
      4: ['CLF', 'UYW'],
    };
    for (final MapEntry(key: exponent, value: codes) in oracle.entries) {
      for (final code in codes) {
        test('$code has exponent $exponent', () {
          expect(Currency.of(code).exponent, exponent);
        });
      }
    }
  });

  group('verification 3: shape and uniqueness', () {
    final code = RegExp(r'^[A-Z]{3}$');

    test('codes are three uppercase ASCII letters, sorted and unique', () {
      final codes = table.rows.map((r) => r.code).toList();
      for (final c in codes) {
        expect(code.hasMatch(c), isTrue, reason: c);
      }
      expect(codes.toSet().length, codes.length);
      final sorted = [...codes]..sort();
      expect(codes, sorted);
    });

    test('active numerics are unique and exponents are 0..4', () {
      final active = table.rows.where((r) => r.active).toList();
      final numerics = active.map((r) => r.numeric).toSet();
      expect(numerics.length, active.length);
      for (final row in table.rows) {
        expect(row.exponent, inInclusiveRange(0, 4), reason: row.code);
        expect(row.numeric, inInclusiveRange(1, 999), reason: row.code);
      }
    });
  });

  group('coverage rules (FR-CUR-07, D-51)', () {
    test('non-currency X-codes are excluded', () {
      const excluded = [
        'XAU',
        'XAG',
        'XPT',
        'XPD',
        'XDR',
        'XSU',
        'XUA',
        'XBA',
        'XBB',
        'XBC',
        'XBD',
        'XTS',
        'XXX',
      ];
      for (final c in excluded) {
        expect(Currency.tryOf(c), isNull, reason: c);
      }
    });

    test('circulating X-codes are regular active currencies', () {
      for (final c in ['XOF', 'XAF', 'XCD', 'XPF']) {
        final currency = Currency.of(c);
        expect(currency.status, CurrencyStatus.active);
        expect(currency.isFund, isFalse);
      }
    });

    test('funds codes are active, flagged and not featured', () {
      const funds = {
        'BOV',
        'CHE',
        'CHW',
        'CLF',
        'COU',
        'MXV',
        'USN',
        'UYI',
        'UYW',
      };
      final flagged = Currency.all.where((c) => c.isFund).map((c) => c.code);
      expect(flagged.toSet(), funds);
      for (final c in funds) {
        expect(Currency.of(c).status, CurrencyStatus.active);
        expect(Currency.featuredCodes, isNot(contains(c)));
      }
    });

    test('featured codes are active, in D-22 order', () {
      final featured = Currency.featuredCodes.join(' ');
      expect(featured, 'EGP USD SAR EUR AED QAR KWD BHD');
      for (final c in Currency.featuredCodes) {
        expect(Currency.of(c).status, CurrencyStatus.active);
      }
    });

    test('active excludes historic codes', () {
      bool isHistoric(Currency c) => c.status == CurrencyStatus.historic;
      final historic = Currency.all.where(isHistoric);
      expect(Currency.active.toSet().intersection(historic.toSet()), isEmpty);
      final total = Currency.active.length + historic.length;
      expect(total, Currency.all.length);
    });
  });

  group('append-only (historic codes)', () {
    test('no baseline code was deleted', () {
      final codes = Currency.all.map((c) => c.code).toSet();
      final baseline = _baselineCodes.split(RegExp(r'\s+'));
      for (final c in baseline.where((c) => c.isNotEmpty)) {
        expect(codes, contains(c));
      }
    });

    test('a code dropped from List One becomes historic, not deleted', () {
      final rows = listOne.rows.where((r) => r.code != 'EGP').toList();
      final withoutEgp = gen.CurrencyTable('2099-01-01', rows);
      final merged = gen.mergeAppendOnly(withoutEgp, table);
      expect(merged.rows.length, table.rows.length);
      final egp = merged.rows.singleWhere((r) => r.code == 'EGP');
      expect(egp.active, isFalse);
      expect(egp.numeric, 818);
      expect(egp.exponent, 2);
      final json = gen.renderJson(merged);
      final egpLine = json.split('\n').singleWhere((l) => l.contains('"EGP"'));
      expect(egpLine, contains('"status": "historic"'));
      expect(gen.parseJson(json).rows, merged.rows);
    });

    test('an empty List One keeps every code as historic', () {
      final empty = gen.CurrencyTable('2099-01-01', const []);
      final merged = gen.mergeAppendOnly(empty, table);
      expect(merged.rows.map((r) => r.code), table.rows.map((r) => r.code));
      expect(merged.rows.every((r) => !r.active), isTrue);
    });

    test('a re-added code becomes active again', () {
      final empty = gen.CurrencyTable('x', const []);
      final historic = gen.mergeAppendOnly(empty, table);
      final back = gen.mergeAppendOnly(listOne, historic);
      final direct = gen.mergeAppendOnly(listOne, table);
      expect(gen.renderJson(back), gen.renderJson(direct));
    });
  });

  group('parser edge cases', () {
    test('repeats collapse; N.A. and code-less entries are skipped', () {
      const sample = '''
<ISO_4217 Pblshd="2025-01-01"><CcyTbl>
<CcyNtry><CtryNm>A</CtryNm><CcyNm>Euro</CcyNm><Ccy>EUR</Ccy>
<CcyNbr>978</CcyNbr><CcyMnrUnts>2</CcyMnrUnts></CcyNtry>
<CcyNtry><CtryNm>B</CtryNm><CcyNm>Euro</CcyNm><Ccy>EUR</Ccy>
<CcyNbr>978</CcyNbr><CcyMnrUnts>2</CcyMnrUnts></CcyNtry>
<CcyNtry><CtryNm>ANTARCTICA</CtryNm><CcyNm>No universal currency</CcyNm>
</CcyNtry>
<CcyNtry><CtryNm>ZZ08_Gold</CtryNm><CcyNm>Gold</CcyNm><Ccy>XAU</Ccy>
<CcyNbr>959</CcyNbr><CcyMnrUnts>N.A.</CcyMnrUnts></CcyNtry>
<CcyNtry><CtryNm>CHILE</CtryNm><CcyNm IsFund="true">Unidad de Fomento</CcyNm>
<Ccy>CLF</Ccy><CcyNbr>990</CcyNbr><CcyMnrUnts>4</CcyMnrUnts></CcyNtry>
</CcyTbl></ISO_4217>
''';
      final parsed = gen.parseListOne(sample);
      expect(parsed.published, '2025-01-01');
      expect(parsed.rows.map((r) => r.code), ['CLF', 'EUR']);
      expect(parsed.rows.first.fund, isTrue);
      expect(parsed.rows.first.exponent, 4);
      expect(parsed.rows.last.fund, isFalse);
    });

    test('conflicting repeats are rejected', () {
      const sample = '''
<ISO_4217 Pblshd="2025-01-01"><CcyTbl>
<CcyNtry><Ccy>EUR</Ccy><CcyNbr>978</CcyNbr><CcyMnrUnts>2</CcyMnrUnts></CcyNtry>
<CcyNtry><Ccy>EUR</Ccy><CcyNbr>978</CcyNbr><CcyMnrUnts>3</CcyMnrUnts></CcyNtry>
</CcyTbl></ISO_4217>
''';
      expect(() => gen.parseListOne(sample), throwsFormatException);
    });
  });

  group('Currency lookup', () {
    test('tryOf is strict', () {
      expect(Currency.tryOf('EGP'), isNotNull);
      for (final bad in ['egp', 'Egp', ' EGP', 'EGP ', 'EG', 'EGPP', '']) {
        expect(Currency.tryOf(bad), isNull, reason: bad);
      }
    });

    test('of throws UnknownCurrency', () {
      expect(() => Currency.of('ZZZ'), throwsA(isA<UnknownCurrency>()));
    });

    test('canonical instances and code-based equality', () {
      expect(identical(Currency.of('EGP'), Currency.of('EGP')), isTrue);
      expect(Currency.of('EGP'), Currency.tryOf('EGP'));
      expect(Currency.of('EGP').hashCode, 'EGP'.hashCode);
      expect(Currency.of('EGP').toString(), 'EGP');
    });
  });
}
