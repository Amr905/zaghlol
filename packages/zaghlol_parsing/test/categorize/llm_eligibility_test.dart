// T-355: LLM categorisation eligibility (no person, no identifier).
// Synthetic data only. Word lists come from the app assets (the rule itself
// reads no files).
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

String _asset(String n) => File('../../app/assets/data/$n').readAsStringSync();

final lexicon = NameLexicon.fromLines(
  givenNames: _asset('eg_given_names.txt'),
  honorifics: _asset('eg_honorifics.txt'),
  businessWords: _asset('eg_business_words.txt'),
);

const biz = LlmPaymentKind.businessPayment;

LlmEligibility check(
  String s, {
  LlmPaymentKind kind = biz,
  CategorizeInput input = const CategorizeInput(),
  bool Function(String)? tried,
  NameLexicon? lx,
}) => LlmEligibility.check(
  input,
  s,
  lx ?? lexicon,
  kind: kind,
  triedBefore: tried,
);

LlmIneligibleReason? why(String s) {
  final r = check(s);
  return r is Ineligible ? r.reason : null;
}

/// Port of the server's ContributionPrivacy.IsAcceptable (backend/src/
/// Zaghlol.Application/Contributions/ContributionPrivacy.cs): length <= 64,
/// no at sign, no run of 6 digits (any script) with <= 3 non-letters between.
bool serverAccepts(String text) {
  if (text.isEmpty || text.length > 64 || RegExp('[@＠﹫]').hasMatch(text)) {
    return false;
  }
  var digits = 0, gap = 0;
  for (final r in text.runes) {
    final c = String.fromCharCode(r);
    if (RegExp(r'^[\p{Nd}\p{No}]$', unicode: true).hasMatch(c)) {
      gap = 0;
      if (++digits >= 6) return false;
    } else if (RegExp(
      r'^[\p{Mn}\p{Me}\p{Mc}\p{Cf}]$',
      unicode: true,
    ).hasMatch(c)) {
      continue;
    } else if (RegExp(r'^\p{L}$', unicode: true).hasMatch(c)) {
      digits = 0;
      gap = 0;
    } else if (digits > 0 && gap < 3) {
      gap++;
    } else {
      digits = 0;
      gap = 0;
    }
  }
  return true;
}

void main() {
  group('table: eligible', () {
    for (final s in [
      'Dr Hany Clinic',
      'صيدلية الشفاء',
      'Koshary Abou Tarek',
      'Carrefour',
      'كارفور',
      'Zawya Coffee',
      'مكتبة النور',
      'Talabat',
      'سوبر ماركت الأمل',
      'Seven Eleven 24',
      'Spinneys Maadi',
      'مطعم أبو طارق',
      'Cairo Pharmacy',
      'Uber',
      'كافيه ريفييرا',
      'Fresh Bakery',
      'Al Ahram Store',
      'ABC Co',
      'Smart Lab',
      'معمل البرج',
    ]) {
      test(s, () => expect(check(s).isEligible, isTrue));
    }
  });

  group('table: ineligible text', () {
    final cases = <String, LlmIneligibleReason>{
      // FR-LCAT-05 excluded list
      'Mohamed Ahmed Ali': LlmIneligibleReason.personLike,
      'أحمد محمود': LlmIneligibleReason.personLike,
      'حاج سيد': LlmIneligibleReason.personLike,
      '01012345678': LlmIneligibleReason.identifier,
      'EG380019000500000000263180002': LlmIneligibleReason.identifier,
      'mona.s@instapay': LlmIneligibleReason.identifier,
      'REF 1234567': LlmIneligibleReason.identifier,
      // persons
      'Dr Mona': LlmIneligibleReason.personLike,
      'محمود': LlmIneligibleReason.personLike,
      'Mona': LlmIneligibleReason.personLike,
      'Mr Hany': LlmIneligibleReason.personLike,
      'Eng. Karim': LlmIneligibleReason.personLike,
      'Dr.Mona':
          LlmIneligibleReason.identifier, // domain shape: refused either way
      'م. كريم': LlmIneligibleReason.personLike,
      'دكتورة منى': LlmIneligibleReason.personLike,
      'الحاجة فاطمة': LlmIneligibleReason.personLike,
      'محمد احمد على': LlmIneligibleReason.personLike,
      'مـحـمـود أحـمـد': LlmIneligibleReason.personLike, // tatweel
      'أَحْمَد مَحْمُود': LlmIneligibleReason.personLike, // harakat
      'ﺃﺣﻤﺪ ﻣﺤﻤﻮﺩ': LlmIneligibleReason.personLike, // presentation forms
      'ＭＯＨＡＭＥＤ ＡＬＩ': LlmIneligibleReason.personLike, // fullwidth
      'M​o​hamed Ali': LlmIneligibleReason.personLike, // zero width
      'm o h a m e d': LlmIneligibleReason.personLike, // letter spacing
      'Abou Tarek': LlmIneligibleReason.personLike,
      'El Sayed Ahmed': LlmIneligibleReason.personLike,
      'کریم علی': LlmIneligibleReason.personLike, // Persian kaf/yeh
      // identifiers
      '٠١٠١٢٣٤٥٦٧٨٩': LlmIneligibleReason.identifier,
      '+20 100 123 4567': LlmIneligibleReason.identifier,
      '+201001234567': LlmIneligibleReason.identifier,
      '0100-123-4567': LlmIneligibleReason.identifier,
      '0100 123 4567': LlmIneligibleReason.identifier,
      '۰۱۰۰۱۲۳۴۵۶۷': LlmIneligibleReason.identifier, // Persian digits
      '０１００１２３４５６７': LlmIneligibleReason.identifier, // fullwidth
      'Shop 1234': LlmIneligibleReason.identifier,
      'متجر ١٢٣٤': LlmIneligibleReason.identifier,
      'Store 12 34 56': LlmIneligibleReason.identifier,
      'Store 1-2-3-4-5-6': LlmIneligibleReason.identifier,
      '1​2​3​4': LlmIneligibleReason.identifier,
      'eg38 0019 0005 0000 0000 2631 8000 2': LlmIneligibleReason.identifier,
      'ＥＧ380019000500000000263180002': LlmIneligibleReason.identifier,
      'mona@gmail.com': LlmIneligibleReason.identifier,
      'منى＠gmail': LlmIneligibleReason.identifier,
      '@mona_ali': LlmIneligibleReason.identifier,
      'pay mona instapay': LlmIneligibleReason.identifier,
      'www.shop.eg': LlmIneligibleReason.identifier,
      'https://x.y/pay': LlmIneligibleReason.identifier,
      'shop.com': LlmIneligibleReason.identifier,
      'Ref 12': LlmIneligibleReason.identifier,
      'رقم 7 كافيه': LlmIneligibleReason.identifier,
      'Card 4111 1111': LlmIneligibleReason.identifier,
      // length
      'a': LlmIneligibleReason.badLength,
      '': LlmIneligibleReason.badLength,
      '​​': LlmIneligibleReason.badLength,
    };
    cases.forEach((s, reason) {
      test('$s -> ${reason.name}', () {
        expect(why(s), reason);
      });
    });
    test('too long', () {
      expect(why('Cafe ${'x' * 70}'), LlmIneligibleReason.badLength);
    });
  });

  group('table: kind, counterparty, history', () {
    test('kinds other than business payment are refused', () {
      expect(
        check('Carrefour', kind: LlmPaymentKind.transfer),
        isA<Ineligible>().having(
          (e) => e.reason,
          'r',
          LlmIneligibleReason.transfer,
        ),
      );
      expect(
        (check('Carrefour', kind: LlmPaymentKind.atmCash) as Ineligible).reason,
        LlmIneligibleReason.atmCash,
      );
      expect(
        (check('Carrefour', kind: LlmPaymentKind.income) as Ineligible).reason,
        LlmIneligibleReason.income,
      );
      expect(
        (check('Carrefour', kind: LlmPaymentKind.unknown) as Ineligible).reason,
        LlmIneligibleReason.notBusinessPayment,
      );
    });
    test('person counterparty', () {
      final r = check(
        'Carrefour',
        input: const CategorizeInput(counterpartyKind: PartyKind.person),
      );
      expect((r as Ineligible).reason, LlmIneligibleReason.personCounterparty);
    });
    test('ipa / phone / own account / bank counterparties', () {
      for (final k in [
        PartyKind.ipa,
        PartyKind.phone,
        PartyKind.ownAccount,
        PartyKind.bank,
      ]) {
        expect(
          check(
            'Carrefour',
            input: CategorizeInput(counterpartyKind: k),
          ).isEligible,
          isFalse,
        );
      }
    });
    test('merchant counterparty is fine', () {
      expect(
        check(
          'Carrefour',
          input: const CategorizeInput(counterpartyKind: PartyKind.merchant),
        ).isEligible,
        isTrue,
      );
    });
    test('event categories cash / income / instapay', () {
      for (final e in ['sys:cash', 'sys:income', 'sys:instapay']) {
        expect(
          check(
            'Carrefour',
            input: CategorizeInput(eventCategoryId: e),
          ).isEligible,
          isFalse,
        );
      }
    });
    test('already tried', () {
      expect(
        (check('Carrefour', tried: (_) => true) as Ineligible).reason,
        LlmIneligibleReason.alreadyTried,
      );
      expect(check('Carrefour', tried: (_) => false).isEligible, isTrue);
    });
    test('empty lexicon fails closed', () {
      final empty = NameLexicon(
        givenNames: [],
        honorifics: [],
        businessWords: [],
      );
      expect(
        (check('Carrefour', lx: empty) as Ineligible).reason,
        LlmIneligibleReason.lexiconMissing,
      );
    });
    test('result carries no text', () {
      expect(
        const Ineligible(LlmIneligibleReason.identifier).toString(),
        isNot(contains('Carrefour')),
      );
    });
  });

  group('properties', () {
    final rnd = Random(355);
    const digitScripts = [0x30, 0x660, 0x6F0, 0xFF10];
    const alphabet = [
      'a',
      'b',
      'Cafe',
      'shop',
      'مطعم',
      'محمد',
      ' ',
      '-',
      '.',
      '/',
      '@',
      '+',
      'ـ',
      '​',
      'ABC',
      'نور',
      '١',
      '٢',
      '3',
      '۴',
      '５',
      'EG',
      'Dr',
      'حاج',
    ];
    String digit() {
      final base = digitScripts[rnd.nextInt(digitScripts.length)];
      return String.fromCharCode(base + rnd.nextInt(10));
    }

    String randomText() {
      final b = StringBuffer();
      for (var i = rnd.nextInt(14) + 1; i > 0; i--) {
        b.write(
          rnd.nextInt(5) == 0
              ? digit()
              : alphabet[rnd.nextInt(alphabet.length)],
        );
      }
      return b.toString();
    }

    test('NEG-PROOF 1: any eligible output passes the server privacy rule', () {
      var eligible = 0;
      for (var i = 0; i < 20000; i++) {
        final s = randomText();
        if (check(s).isEligible) {
          eligible++;
          expect(serverAccepts(s), isTrue, reason: 'case #$i');
        }
      }
      expect(eligible, greaterThan(500)); // the generator does hit eligible
    });

    test('>= 4 consecutive digits after normalisation is refused', () {
      for (var i = 0; i < 5000; i++) {
        final run = List.generate(4 + rnd.nextInt(6), (_) => digit()).join();
        final s =
            '${rnd.nextBool() ? 'Cafe ' : ''}$run${rnd.nextBool() ? ' مطعم' : ''}';
        expect(why(s), LlmIneligibleReason.identifier, reason: 'case #$i');
      }
    });

    test('NEG-PROOF 2: transfer / ATM / income / person is never eligible', () {
      for (var i = 0; i < 5000; i++) {
        final s = rnd.nextBool() ? randomText() : 'Carrefour';
        for (final k in [
          LlmPaymentKind.transfer,
          LlmPaymentKind.atmCash,
          LlmPaymentKind.income,
          LlmPaymentKind.unknown,
        ]) {
          expect(check(s, kind: k).isEligible, isFalse);
        }
        expect(
          check(
            s,
            input: const CategorizeInput(counterpartyKind: PartyKind.person),
          ).isEligible,
          isFalse,
        );
      }
    });

    test('NEG-PROOF 3: all-given-name strings are refused', () {
      final names = _asset('eg_given_names.txt')
          .split('\n')
          .where((n) => n.length > 2)
          .toList();
      final biz = _asset('eg_business_words.txt').split('\n').toSet();
      for (var i = 0; i < 3000; i++) {
        final n = 1 + rnd.nextInt(4);
        final toks = List.generate(n, (_) => names[rnd.nextInt(names.length)]);
        if (toks.any(biz.contains)) continue;
        expect(check(toks.join(' ')).isEligible, isFalse, reason: 'case #$i');
      }
    });

    test('1,000 merchants well under 100 ms', () {
      final inputs = List.generate(
        1000,
        (i) => 'مطعم الشفاء فرع ${i % 9} Cafe Zawya',
      );
      for (final s in inputs) {
        check(s); // JIT warm-up (the app runs AOT)
      }
      var best = 1 << 30; // best of 3 passes: robust to a GC pause
      for (var pass = 0; pass < 3; pass++) {
        final sw = Stopwatch()..start();
        for (final s in inputs) {
          check(s);
        }
        sw.stop();
        if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
      }
      expect(best, lessThan(100));
    });
  });
}
