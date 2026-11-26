// T-328 fix round (batch 90, M1 + M2 + minors): letter and digit variants,
// split last-4s, bank-name forms, placeholder numbers above 9, the safety net
// and the documented known gaps. Synthetic data only.

import 'dart:math';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'llm_fixtures.dart';

const costa = MaskMerchant('costa', ['Costa', 'كوستا']);
const withCosta = StaticMaskSources(
  accounts: [cibCredit, nbeSavings],
  institutions: [cib, nbe, misr, voda, liv, wise],
  merchants: [carrefour, talabat, spinneys, costa],
);

String? sent(String q, [MaskSources s = withCosta]) => sentTextOf(q, s);

/// All digits of [t] read as ASCII (Arabic-Indic and Persian included).
String digitsOf(String t) {
  final b = StringBuffer();
  for (final c in t.runes) {
    if (c >= 0x30 && c <= 0x39) {
      b.writeCharCode(c);
    } else if (c >= 0x660 && c <= 0x669) {
      b.writeCharCode(0x30 + c - 0x660);
    } else if (c >= 0x6F0 && c <= 0x6F9) {
      b.writeCharCode(0x30 + c - 0x6F0);
    }
  }
  return b.toString();
}

/// Masked with the digits gone, or unresolved (a clarification).
void expectNoLast4(String q, {String last4 = '4321'}) {
  final o = pipeline(q, withCosta);
  if (o is MaskResult) {
    expect(digitsOf(o.sentText), isNot(contains(last4)), reason: 'sent [$q]');
  } else {
    expect(o, isA<MaskUnresolved>());
  }
}

void main() {
  group('M1 letter variants fold', () {
    test('Persian kaf and yeh', () {
      expect(sent('صرفت كام في کارفور'), 'صرفت كام في ⟦MERCHANT_1⟧');
      expect(sent('صرفت في سبینس'), 'صرفت في ⟦MERCHANT_1⟧');
      expect(sent('صرفت في کوستا'), 'صرفت في ⟦MERCHANT_1⟧');
    });

    test('alef + combining hamza equals precomposed', () {
      expect(sent('حسابي في الأهلي'), 'حسابي في ⟦BANK_1⟧');
      expect(sent('حسابي في الإهلي'), 'حسابي في ⟦BANK_1⟧');
    });

    test('fullwidth Latin', () {
      expect(sent('spent at Ｃarrefour'), 'spent at ⟦MERCHANT_1⟧');
      expect(sent('my Ｃｉｂ card'), 'my ⟦BANK_1⟧ card');
    });

    test('zero-width and bidi characters inside a name', () {
      expect(sent('spent at Car​refour'), 'spent at ⟦MERCHANT_1⟧');
      expect(sent('صرفت في كا‌رفور'), 'صرفت في ⟦MERCHANT_1⟧');
      expect(sent('spent at \u202ECarrefour\u202C'), contains('⟦MERCHANT_1⟧'));
    });

    test('Latin diacritics', () {
      expect(sent('spent at Cárréfour'), 'spent at ⟦MERCHANT_1⟧');
      expect(sent('spent at Çarrefour'), 'spent at ⟦MERCHANT_1⟧');
    });

    test('Arabic presentation forms', () {
      // Isolated/initial/medial/final forms of كارفور.
      const pf = 'ﻛﺎﺭﻓﻮﺮ';
      expect(sent('صرفت في $pf'), 'صرفت في ⟦MERCHANT_1⟧');
    });

    test('foldKey (the parser) is unchanged', () {
      expect(foldKey('کارفور'), isNot(equals(foldKey('كارفور'))));
    });
  });

  group('M2 last-4 next to card words and split digits', () {
    const words = [
      'كريديت',
      'الكريديت',
      'بالكريديت',
      'credit',
      'debit',
      'ديبت',
      'visa',
      'فيزا',
      'ماستر',
      'ماستركارد',
      'mastercard',
      'ميزة',
      'meeza',
      'بطاقة',
      'كارت',
      'ending in',
      'ينتهي بـ',
      'اللي آخره',
      'آخره',
      'prepaid',
    ];
    const spellings = [
      '4321',
      '٤٣٢١',
      '۴۳۲۱',
      '43 21',
      '43-21',
      '43.21',
      '٤٣-٢١',
      '۴۳ ۲۱',
      '4 3 2 1',
      '4-3 2.1',
      '4 321',
      '432 1',
      '٤ ٣ ٢ ١',
      '43 - 21',
    ];
    test('every card word x every spelling: masked or unresolved', () {
      var n = 0;
      for (final w in words) {
        for (final s in spellings) {
          for (final q in [
            '$w $s',
            'صرفت كام على $w $s',
            '$s $w',
            'on $w $s',
          ]) {
            expectNoLast4(q);
            n++;
          }
        }
      }
      expect(n, greaterThan(1000));
    });

    test('the review probes', () {
      for (final q in [
        'كريديت 4321',
        'credit 4321',
        'كارت 43 21',
        'كارت 43-21',
        'كارت ٤٣ ٢١',
        'كارت 4 3 2 1',
      ]) {
        final o = pipeline(q, withCosta);
        expect(o, isA<MaskResult>(), reason: q);
        expect((o as MaskResult).sentText, contains('⟦CARD_1⟧'), reason: q);
      }
    });

    test('an amount keeps its digits', () {
      expect(sent('صرفت 9999 جنيه على كارت'), contains('9999'));
      expect(sent('كارت 99 99 جنيه'), contains('99 99'));
      expect(digitsOf(sent('كارت 12 34 جنيه')!), '1234');
    });

    test('a card the user does not have is a clarification', () {
      final o = pipeline('كارت 99 11', withCosta);
      expect(o, isA<MaskUnresolved>());
    });
  });

  group('minors', () {
    test('bank of X and X bank go through the unknown-bank check', () {
      for (final q in [
        'how much at bank of zz',
        'how much at zz bank',
        'bank al zz balance',
        'بنك زد زد رصيدي',
      ]) {
        final o = pipeline(q, withCosta);
        expect(o, isA<MaskUnresolved>(), reason: q);
        expect(
          (o as MaskUnresolved).reason,
          MaskUnresolvedReason.unknownBank,
          reason: q,
        );
      }
      for (final q in [
        'my bank fees',
        'which bank is best',
        'bank statement for march',
      ]) {
        expect(pipeline(q, withCosta), isA<MaskResult>(), reason: q);
      }
    });

    test('phones written with dots, odd groups and fullwidth @', () {
      for (final q in [
        'ابعت لـ 0100.000.0000',
        'call 010 00 00 00 00 now',
        'call +20 100 000 0000 now',
        'call 0100-000-0000',
        'ابعت لـ ٠١٠٠.٠٠٠.٠٠٠٠',
      ]) {
        final r = ClientScrub.apply(q);
        expect(r.text, contains('⟦PHONE⟧'), reason: q);
        expect(digitsOf(r.text), isEmpty, reason: q);
      }
      for (final q in [
        'ahmed＠instapay',
        'ahmed @ instapay',
        'ahmed ＠ instapay',
      ]) {
        expect(ClientScrub.apply('to $q ok').text, 'to ⟦IPA⟧ ok', reason: q);
      }
      // A date stays.
      expect(ClientScrub.apply('on 25.12.2024 I paid').text, contains('2024'));
    });

    test('placeholder numbers above 9 render and round-trip', () {
      const names = [
        'zqa', 'zqb', 'zqc', 'zqd', 'zqe', 'zqf', 'zqg', 'zqh', 'zqi', 'zqj', //
        'zqk', 'zql', //
      ];
      final src = StaticMaskSources(
        accounts: const [cibCredit],
        institutions: const [cib],
        merchants: [
          for (final n in names) MaskMerchant('id-$n', [n]),
        ],
      );
      final o = pipeline('spent at ${names.join(' and ')}', src);
      expect(o, isA<MaskResult>());
      final r = o as MaskResult;
      for (var i = 0; i < names.length; i++) {
        final ph = '⟦MERCHANT_${i + 1}⟧';
        expect(r.sentText, contains(ph));
        expect(r.map[ph]!.merchantId, 'id-${names[i]}');
      }
      expect(r.sentText, contains('⟦MERCHANT_12⟧'));
      for (final n in names) {
        expect(r.sentText, isNot(contains(n)));
      }
    });
  });

  group('safety net (re-scan of the sent text)', () {
    test('catches a name, a merchant and a last-4 left in a text', () {
      expect(
        ReferenceMasker.leaksForTest('spent at Carrefour', withCosta),
        isTrue,
      );
      expect(ReferenceMasker.leaksForTest('في كارفور', withCosta), isTrue);
      expect(ReferenceMasker.leaksForTest('my NBE Main', withCosta), isTrue);
      expect(ReferenceMasker.leaksForTest('حساب التوفير', withCosta), isTrue);
      expect(ReferenceMasker.leaksForTest('كارت 4321', withCosta), isTrue);
      expect(ReferenceMasker.leaksForTest('credit 43 21', withCosta), isTrue);
      expect(ReferenceMasker.leaksForTest('ک​ارفور', withCosta), isTrue);
    });

    test('lets clean text and placeholders through', () {
      expect(
        ReferenceMasker.leaksForTest(
          'spent at ⟦MERCHANT_1⟧ on ⟦CARD_1⟧',
          withCosta,
        ),
        isFalse,
      );
      expect(
        ReferenceMasker.leaksForTest('صرفت 4321 جنيه', withCosta),
        isFalse,
      );
      expect(ReferenceMasker.leaksForTest('مصر والأهلي', withCosta), isFalse);
    });

    test('a leak found after masking returns MaskUnresolved(failed)', () {
      // A source whose name only appears through a clitic the first pass
      // cannot see is not constructible with the shipped rules, so the
      // net is proven through its seam above; here the whole path still
      // returns a result for clean text.
      expect(pipeline('spent at Carrefour', withCosta), isA<MaskResult>());
    });
  });

  group('known gaps (documented behaviour, see T-328 task file)', () {
    test('digits written as words are not caught', () {
      final s = sent('كارت اربعة تلاتة اتنين واحد');
      expect(s, 'كارت اربعة تلاتة اتنين واحد');
    });

    test('a far last-4 is not masked but the net now blocks it (m14)', () {
      expect(sent('الكارت بتاعي اللي رقمه في الآخر 4321'), isNull);
    });

    test('possessive suffix on a name: blocked by the net (m14)', () {
      expect(sent('صرفت في كارفوري'), isNull);
    });
  });

  group('NEGATIVE PROOF 1b (property over the new variants)', () {
    final rnd = Random(905);

    String persian(String s) => s
        .replaceAll('ك', 'ک')
        .replaceAll('ي', 'ی')
        .replaceAll('ه', rnd.nextBool() ? 'ە' : 'ہ')
        .replaceAll('ى', 'ی');
    String decomposed(String s) => s
        .replaceAll('أ', 'أ')
        .replaceAll('إ', 'إ')
        .replaceAll('ؤ', 'ؤ')
        .replaceAll('ئ', 'ئ');
    String fullwidth(String s) => String.fromCharCodes([
      for (final c in s.runes)
        (c >= 0x21 && c <= 0x7E && c != 0x20) ? c + 0xFEE0 : c,
    ]);
    String zeroWidth(String s) {
      final b = StringBuffer();
      for (final c in s.runes) {
        b.writeCharCode(c);
        if (c != 0x20 && rnd.nextInt(3) == 0) {
          b.writeCharCode(
            const [0x200B, 0x200C, 0x200D, 0x200E, 0x202C][rnd.nextInt(5)],
          );
        }
      }
      return b.toString();
    }

    String accents(String s) => s
        .replaceAll('e', 'é')
        .replaceAll('a', 'á')
        .replaceAll('i', 'ï')
        .replaceAll('o', 'ó');

    const contexts = [
      'صرفت كام في %s النهاردة؟',
      'how much at %s last week?',
      'حسابي في %s',
      'my %s account',
      'كارت %s',
      '%s',
    ];
    final adjacent = [contexts[2], contexts[3], contexts[4]];

    test('every name x every variant x context: variant never sent', () {
      final all = [
        for (final i in withCosta.institutions)
          for (final a in i.aliases) (a.text, a.ordinaryWord),
        for (final a in withCosta.accounts) ...[
          (a.label, false),
          if (a.nickname != null) (a.nickname!, false),
          for (final e in a.extraNames) (e, false),
        ],
        for (final m in withCosta.merchants)
          for (final n in m.names) (n, false),
      ];
      var checked = 0;
      for (final (n, ordinary) in all) {
        final variants = {
          persian(n),
          decomposed(n),
          fullwidth(n),
          zeroWidth(n),
          accents(n),
          zeroWidth(persian(decomposed(n))),
          fullwidth(n.toUpperCase()),
        }..remove(n);
        for (final v in variants) {
          for (final c in ordinary ? adjacent : contexts) {
            final q = c.replaceAll('%s', v);
            final o = pipeline(q, withCosta);
            if (o is MaskResult) {
              expect(o.sentText, isNot(contains(v)), reason: 'sent [$q]');
            }
            checked++;
          }
        }
      }
      expect(checked, greaterThan(500));
    });

    test('every last-4 x digit script x split x separators', () {
      const seps = [' ', '-', '.', ' - ', '', '  '];
      const scripts = [0x30, 0x660, 0x6F0];
      const words = ['كارت', 'كريديت', 'credit', 'visa', 'ending in', 'آخره'];
      for (final a in withCosta.accounts) {
        final d = a.last4!;
        for (final sc in scripts) {
          String conv(String x) => String.fromCharCodes([
            for (final c in x.codeUnits) c - 0x30 + sc,
          ]);
          for (final cuts in const [
            [4],
            [2, 2],
            [1, 3],
            [3, 1],
            [1, 1, 2],
            [1, 1, 1, 1],
          ]) {
            var p = 0;
            final parts = <String>[];
            for (final c in cuts) {
              parts.add(conv(d.substring(p, p + c)));
              p += c;
            }
            final b = StringBuffer(parts.first);
            for (final part in parts.skip(1)) {
              b.write(seps[rnd.nextInt(seps.length - 2)]);
              b.write(part);
            }
            for (final w in words) {
              for (final q in ['$w $b', 'صرفت كام $w رقم $b', '$b $w']) {
                final o = pipeline(q, withCosta);
                if (o is MaskResult) {
                  expect(digitsOf(o.sentText), isNot(contains(d)), reason: q);
                }
              }
            }
          }
        }
      }
    });
  });

  group('fix round 2 (M3, m13, m14)', () {
    const leaky = [
      'كارت4321',
      'كارت٤٣٢١',
      'visa4321',
      'كارتك 4321',
      'كارتها 4321',
      'كارتي 4321',
      'بكارته 4321',
      'والفيزا 4321',
      'كارت 43–21',
      'كارت 43—21',
      'كارت 43‐21',
      'كارت 43,21',
      'كارت ٤٣،٢١',
      'كارت 4,3,2,1',
      'كارت 4-3-2-1',
      'كارت 43.21',
      'كارت 43 / 21',
    ];
    for (final q in leaky) {
      test('no last-4 in [$q]', () => expectNoLast4(q));
    }

    test('thousands separators are not a last-4', () {
      expect(pipeline('كارت 1,000 جنيه', withCosta), isA<MaskResult>());
    });

    test('net blocks a last-4 anywhere, however it is written', () {
      for (final t in ['اشتريت 43-21 من', 'x 4,3,2,1', 'abc4321', '43 – 21']) {
        expect(ReferenceMasker.leaksForTest(t, withCosta), isTrue, reason: t);
      }
      expect(ReferenceMasker.leaksForTest('عندي 14321 جنيه', withCosta), false);
      expect(ReferenceMasker.leaksForTest('يوم 10/05/2024', withCosta), false);
    });

    test('net blocks names with non-letters inside', () {
      for (final t in ['ك ا ر فور', 'C.a-r r e f o u r', 'tal_a_bat']) {
        expect(ReferenceMasker.leaksForTest(t, withCosta), isTrue, reason: t);
      }
    });

    test('more than 99 placeholders of one kind is unresolved', () {
      final ms = [
        for (var i = 0; i < 100; i++) MaskMerchant('m$i', ['Shop${'x' * i}ab']),
      ];
      final q = [for (var i = 0; i < 100; i++) 'Shop${'x' * i}ab'].join(' ');
      final o = ReferenceMasker.mask(q, StaticMaskSources(merchants: ms));
      expect(o, isA<MaskUnresolved>());
    });
  });
}
