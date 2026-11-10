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
    final rows = <(String, String, String)>[
      ('latin', 'Carrefour', 'carrefour'),
      ('separate article', 'EL EZABY', 'ezaby'),
      ('attached article', 'ELEZABY', 'ezaby'),
      ('al article', 'AL RAWSHA', 'rawsha'),
      ('short word kept', 'ELF', 'elf'),
      ('short remainder kept', 'ELITE', 'elite'),
      ('lone el kept', 'EL', 'el'),
      ('arabic article', 'الاهرام', 'ahram'),
      ('arabic transliteration', 'كارفور', 'karfwr'),
      ('arabic digits', 'فرع ٢٣', 'fra23'),
      ('inner spaces removed', 'KOSHARY EL TAHRIR', 'kosharyeltahrir'),
      ('punctuation dropped', "McDonald's", 'mcdonalds'),
      ('digits kept', '7-ELEVEN', '7eleven'),
      ('tatweel and harakat', 'مَحَمّـد', 'mhmd'),
      ('alef variants', 'أحمد إبراهيم', 'ahmdabrahym'),
      ('empty', '', ''),
    ];
    for (final (name, input, expected) in rows) {
      test(name, () => expect(merchantKey(input), expected));
    }

    test('ELEZABY and EL EZABY share a key', () {
      expect(merchantKey('ELEZABY'), merchantKey('EL EZABY'));
      final a = cleanMerchant('ELEZABY');
      final b = cleanMerchant('EL EZABY EG 0042');
      final c = cleanMerchant('El-Ezaby');
      expect(a.key, b.key);
      expect(a.key, c.key);
    });

    test('capped at 64 characters', () {
      expect(merchantKey('a' * 200).length, merchantKeyMaxLength);
    });

    test('output is lowercase ASCII, idempotent, no whitespace', () {
      final inputs = ['CARREFOUR 041', 'صيدليات العزبي', 'Ünï ٣٤', 'EL  EZABY'];
      for (final s in inputs) {
        final k = merchantKey(s);
        expect(RegExp(r'^[a-z0-9]*$').hasMatch(k), isTrue, reason: s);
        expect(merchantKey(k), k, reason: s);
      }
    });
  });
}
