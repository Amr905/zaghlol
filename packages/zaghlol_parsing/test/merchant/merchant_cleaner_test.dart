import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

typedef _Clean = (String name, String input, String display, String cleaned);

void main() {
  group('cleanMerchant', () {
    final rows = <_Clean>[
      ('spec example', 'CARREFOUR MAADI EG 041', 'Carrefour', 'CARREFOUR'),
      ('lowercase input', 'carrefour maadi eg 041', 'Carrefour', 'CARREFOUR'),
      ('pos token leading', 'POS SPINNEYS 12345', 'Spinneys', 'SPINNEYS'),
      ('pos token trailing', 'SPINNEYS POS 12345', 'Spinneys', 'SPINNEYS'),
      ('ecom and online', 'NOON ECOM ONLINE EG', 'Noon', 'NOON'),
      ('multi-word city', 'HYPERONE NASR CITY EG', 'Hyperone', 'HYPERONE'),
      ('city country code', 'TALABAT CAIRO EGY 0042', 'Talabat', 'TALABAT'),
      ('legal suffix', 'ORASCOM FOODS LLC', 'Orascom Foods', 'ORASCOM FOODS'),
      ('dotted legal', 'MISR FOODS S.A.E.', 'Misr Foods', 'MISR FOODS'),
      ('co with dot', 'DELTA TRADING CO.', 'Delta Trading', 'DELTA TRADING'),
      ('hash terminal', 'BREADFAST #4521', 'Breadfast', 'BREADFAST'),
      ('star separator', 'UBER*TRIP EG', 'Uber Trip', 'UBER TRIP'),
      ('short number kept', '7-ELEVEN 12', '7-Eleven 12', '7-ELEVEN 12'),
      ('digits in name kept', 'B TECH 2', 'B Tech 2', 'B TECH 2'),
      ('bank misr keeps country word', 'بنك مصر', 'بنك مصر', 'بنك مصر'),
      (
        'national bank of egypt',
        'NATIONAL BANK OF EGYPT',
        'National Bank Of Egypt',
        'NATIONAL BANK OF EGYPT',
      ),
      (
        'full country name kept',
        'TALABAT EGYPT',
        'Talabat Egypt',
        'TALABAT EGYPT',
      ),
      (
        'documents mid-name city kept',
        'CARREFOUR MAADI CITY CENTER EG',
        'Carrefour Maadi City Center',
        'CARREFOUR MAADI CITY CENTER',
      ),
      ('documents alnum id kept', 'SHOP T123A', 'Shop T123a', 'SHOP T123A'),
      ('first token kept', 'EGYPT AIR', 'Egypt Air', 'EGYPT AIR'),
      ('only noise falls back', 'POS', 'Pos', 'POS'),
      ('city only', 'MAADI', 'Maadi', 'MAADI'),
      ('arabic city suffix', 'كارفور القاهرة', 'كارفور', 'كارفور'),
      ('arabic digits code', 'كارفور المعادي ٠٤١', 'كارفور', 'كارفور'),
      ('arabic legal', 'شركة النيل ش.م.م', 'شركة النيل', 'شركة النيل'),
      ('tatweel removed', 'كـارفـور', 'كارفور', 'كارفور'),
      ('whitespace', '  CARREFOUR \t MAADI  ', 'Carrefour', 'CARREFOUR'),
      ('empty', '', '', ''),
      ('blank', '   ', '', ''),
      ('punctuation only', '- . -', '', ''),
    ];
    for (final (name, input, display, cleaned) in rows) {
      test(name, () {
        final r = cleanMerchant(input);
        expect(r.display, display);
        expect(r.cleaned, cleaned);
      });
    }

    test('custom config lists are honoured', () {
      const config = MerchantCleaningConfig(
        countryTokens: ['XX'],
        cityPhrases: ['SMALLVILLE'],
        legalSuffixes: [],
        noiseTokens: [],
      );
      final custom = cleanMerchant('SHOP SMALLVILLE XX', config: config);
      final plain = cleanMerchant('SHOP EG', config: config);
      expect(custom.display, 'Shop');
      expect(plain.display, 'Shop Eg');
    });

    test('never throws on odd input', () {
      final inputs = ['\u0000', '###', '٠٠٠', '‏', 'a' * 5000, '😀'];
      for (final s in inputs) {
        expect(() => cleanMerchant(s), returnsNormally);
      }
    });
  });

  group('merchantKey', () {
    final file = [
      File('test/fixtures/merchant_key_vectors.json'),
      File('packages/zaghlol_parsing/test/fixtures/merchant_key_vectors.json'),
    ].firstWhere((f) => f.existsSync());
    final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final list = doc['vectors'] as List<dynamic>;
    final vectors = list.cast<Map<String, dynamic>>();
    test('golden vectors are present', () {
      expect(vectors.length, greaterThanOrEqualTo(30));
    });
    for (final v in vectors) {
      final input = v['input'] as String;
      final key = v['key'] as String;
      test('vector: $input', () => expect(merchantKey(input), key));
    }

    test('ELEZABY, EL EZABY and El-Ezaby share a key', () {
      expect(merchantKey('ELEZABY'), merchantKey('EL EZABY'));
      final a = cleanMerchant('ELEZABY');
      final b = cleanMerchant('EL EZABY EG 0042');
      final c = cleanMerchant('El-Ezaby');
      expect(a.key, 'ezaby');
      expect(a.key, b.key);
      expect(a.key, c.key);
    });

    test('token boundaries survive for prefix matching', () {
      expect(merchantKey('UBER BREAK'), 'uber break');
      expect(merchantKey('UBERBREAK'), 'uberbreak');
    });

    test('capped at 64 characters without a trailing space', () {
      expect(merchantKey('a' * 200).length, merchantKeyMaxLength);
      final key = merchantKey('${'a' * 63} bb');
      expect(key, 'a' * 63);
    });

    test('unmappable input gives an empty key', () {
      expect(merchantKey('😀'), '');
      expect(cleanMerchant('😀').key, '');
    });

    test('article strip is applied once and is not a fixed point', () {
      expect(merchantKey('ELELEZABY'), 'elezaby');
      expect(merchantKey('elezaby'), 'ezaby');
    });

    test('output is words of a-z0-9 with single spaces, stable', () {
      final inputs = ['CARREFOUR 041', 'صيدليات العزبي', 'Ünï ٣٤', 'EL EZABY'];
      for (final s in inputs) {
        final k = merchantKey(s);
        expect(RegExp(r'^[a-z0-9]+( [a-z0-9]+)*$|^$').hasMatch(k), isTrue);
        expect(merchantKey(k), k, reason: s);
      }
    });
  });
}
