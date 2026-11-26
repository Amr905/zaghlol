// T-328: ReferenceMasker (FR-LLM-18..20, D-92). Synthetic fixtures only.
//
// AC -> test map
//  AC1  'AC1 FR-LLM-03 ...'
//  AC2  'AC2 ...'
//  AC3  'AC3 ...'
//  AC4  'AC4 ...'
//  AC5  'NEGATIVE PROOF 1 ...' (and the property tests)
//  AC6  'NEGATIVE PROOF 2 ...'

import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'llm_fixtures.dart';

MaskResult masked(String q, [MaskSources s = ahmed]) {
  final o = pipeline(q, s);
  expect(o, isA<MaskResult>(), reason: 'expected a mask result');
  return o as MaskResult;
}

MaskUnresolved unresolved(String q, [MaskSources s = ahmed]) {
  final o = pipeline(q, s);
  expect(o, isA<MaskUnresolved>(), reason: 'expected unresolved');
  return o as MaskUnresolved;
}

final RegExp _placeholder = RegExp('⟦[A-Z]+(?:_[0-9]+)?⟧');

/// Names a sent text must not contain (folded comparison).
List<String> secretNames(MaskSources s, {required bool ordinary}) => [
  for (final i in s.institutions)
    for (final a in i.aliases)
      if (ordinary || !a.ordinaryWord) a.text,
  for (final a in s.accounts) ...[a.label, ?a.nickname, ...a.extraNames],
  for (final m in s.merchants) ...m.names,
];

bool _isLatin(String k) => RegExp('^[a-z0-9 ]+\$').hasMatch(k);

bool containsName(String sent, String name) {
  final text = foldKey(sent.replaceAll(_placeholder, ' '));
  final key = foldKey(name);
  if (_isLatin(key)) {
    return RegExp('(?<![a-z0-9])${RegExp.escape(key)}(?![a-z0-9])')
        .hasMatch(text);
  }
  return text.contains(key);
}

const _cardWordsForCheck = {
  'كارت', 'بكارت', 'بطاقه', 'فيزا', 'بفيزا', 'حساب', 'حسابي', 'منتهي',
  'card', 'account', 'visa', 'ending', //
};

/// A fixture last-4 within 3 words of a card/account word.
bool containsLast4NearCardWord(String sent, MaskSources s) {
  final words = RegExp(
    r'[\p{L}\p{N}]+',
    unicode: true,
  ).allMatches(foldKey(sent.replaceAll(_placeholder, ' '))).map((m) => m[0]!);
  final list = words.toList();
  for (var i = 0; i < list.length; i++) {
    for (final a in s.accounts) {
      if (list[i] != a.last4) {
        continue;
      }
      for (var d = -3; d <= 3; d++) {
        final j = i + d;
        if (d != 0 && j >= 0 && j < list.length) {
          final w = list[j];
          if (_cardWordsForCheck.contains(w) ||
              _cardWordsForCheck.contains(w.substring(w.isEmpty ? 0 : 1))) {
            return true;
          }
        }
      }
    }
  }
  return false;
}

void expectClean(String sent, MaskSources s, {bool ordinary = false}) {
  for (final n in secretNames(s, ordinary: ordinary)) {
    expect(containsName(sent, n), isFalse, reason: 'leaked [$n] in [$sent]');
  }
  expect(
    containsLast4NearCardWord(sent, s),
    isFalse,
    reason: 'leaked a last-4',
  );
}

void main() {
  group('acceptance', () {
    test('AC1 FR-LLM-03 example: no phone, IPA or 1234; question kept', () {
      const q = 'حولت لـ 01000000000 و ahmed@instapay، صرفت كام بكارت 1234؟';
      final r = masked(q, ahmedPlus1234);
      expect(r.sentText, 'حولت لـ ⟦PHONE⟧ و ⟦IPA⟧، صرفت كام بكارت ⟦CARD_1⟧؟');
      expect(r.sentText, isNot(contains('01000000000')));
      expect(r.sentText, isNot(contains('instapay')));
      expect(r.sentText, isNot(contains('1234')));
      expect(r.sentText, contains('صرفت كام'));
      // With no card ending 1234 nothing is sent at all.
      expect(pipeline(q, ahmed), isA<MaskUnresolved>());
    });

    test('AC2 FR-LLM-18 ar: exact sentence', () {
      expect(
        masked('صرفت كام بكارت 4321 في كارفور من حسابي في CIB؟').sentText,
        'صرفت كام بكارت ⟦CARD_1⟧ في ⟦MERCHANT_1⟧ من حسابي في ⟦BANK_1⟧؟',
      );
    });

    test('AC2 FR-LLM-18 en: exact sentence, Uber kept', () {
      expect(
        masked(
          'How much went out of my savings account at NBE vs my card ending 4321 at Uber?',
        ).sentText,
        'How much went out of my ⟦ACCOUNT_1⟧ account at ⟦BANK_1⟧ vs my card ending ⟦CARD_1⟧ at Uber?',
      );
    });

    test('AC2 a bare 4-digit amount stays; Arabic-Indic digits by a card', () {
      expect(masked('صرفت 4321 جنيه').sentText, 'صرفت 4321 جنيه');
      expect(
        masked('صرفت كام بكارت ٤٣٢١ الشهر ده؟').sentText,
        'صرفت كام بكارت ⟦CARD_1⟧ الشهر ده؟',
      );
      expect(masked('كارت ٤٣٢١ جنيه').sentText, 'كارت ⟦CARD_1⟧ جنيه');
      // Unknown 4-digit amount next to a card word and a currency: an amount.
      expect(masked('كارت 5000 جنيه').sentText, 'كارت 5000 جنيه');
    });

    test('AC2 map resolves placeholders on the phone', () {
      final r = masked('صرفت كام بكارت 4321 في كارفور من حسابي في CIB؟');
      expect(r.map['⟦CARD_1⟧']!.accountIds, ['acc-cib-credit']);
      expect(r.map['⟦BANK_1⟧']!.institutionId, 'cib');
      expect(r.map['⟦BANK_1⟧']!.accountIds, ['acc-cib-credit']);
      expect(r.map['⟦MERCHANT_1⟧']!.merchantId, 'carrefour');
      expect(
        [for (final t in r.tokens) t.placeholder],
        ['⟦CARD_1⟧', '⟦MERCHANT_1⟧', '⟦BANK_1⟧'],
      );
    });

    test('AC3 FR-LLM-20: unresolvable references stay on the phone', () {
      final noCard = unresolved('spent on card 9999?');
      expect(noCard.reason, MaskUnresolvedReason.noSuchCard);
      expect([for (final a in noCard.candidates) a.id], ['acc-cib-credit']);

      final noAccount = unresolved('صرفت كام من حسابي في بنك مصر؟');
      expect(noAccount.reason, MaskUnresolvedReason.bankWithoutAccount);
      expect(noAccount.candidates, hasLength(2));

      final unknown = unresolved('حسابي في بنك الزغاليل');
      expect(unknown.reason, MaskUnresolvedReason.unknownBank);
      expect(unknown.candidates, hasLength(2));
      expect(
        unresolved('my account at bank Zaghaleel').reason,
        MaskUnresolvedReason.unknownBank,
      );

      const twin = MaskAccount(
        id: 'acc-twin',
        label: 'Twin',
        institutionId: 'cib',
        type: MaskAccountType.debitCard,
        last4: '4321',
      );
      const dup = StaticMaskSources(
        accounts: [cibCredit, twin],
        institutions: [cib],
      );
      final ambiguous = unresolved('كارت 4321 صرف كام', dup);
      expect(ambiguous.reason, MaskUnresolvedReason.ambiguousCard);
      expect(
        [for (final a in ambiguous.candidates) a.id],
        ['acc-cib-credit', 'acc-twin'],
      );
    });

    test('AC4 word-like aliases only next to a bank/account/card word', () {
      expect(masked('الأهلي كسب امبارح').sentText, 'الأهلي كسب امبارح');
      expect(masked('رحت مصر الجديدة').sentText, 'رحت مصر الجديدة');
      expect(masked('I like Liv a lot').sentText, 'I like Liv a lot');
      expect(masked('Wise guys').sentText, 'Wise guys');
      expect(masked('حسابي في الأهلي كام؟').sentText, 'حسابي في ⟦BANK_1⟧ كام؟');
      expect(masked('NBE account').sentText, '⟦BANK_1⟧ account');
      expect(masked('the الأهلي card').sentText, 'the ⟦BANK_1⟧ card');
      // No account at Liv: next to "account" it must be resolved first.
      expect(
        unresolved('my Liv account').reason,
        MaskUnresolvedReason.bankWithoutAccount,
      );
      expect(
        unresolved('حسابي في مصر').reason,
        MaskUnresolvedReason.bankWithoutAccount,
      );
    });

    test('numbering by first appearance; repeats reuse their token', () {
      expect(
        masked('كارفور وطلبات وكارفور تاني').sentText,
        '⟦MERCHANT_1⟧ و⟦MERCHANT_2⟧ و⟦MERCHANT_1⟧ تاني',
      );
      final r = masked('كارت 4321 وكارت ٤٣٢١ و CIB و سي آي بي');
      expect(r.sentText, 'كارت ⟦CARD_1⟧ وكارت ⟦CARD_1⟧ و ⟦BANK_1⟧ و ⟦BANK_1⟧');
      expect(r.map.length, 2);
    });

    test('longest match first', () {
      // "Commercial International Bank" beats the shorter "Bank"-less CIB.
      expect(
        masked('Commercial International Bank card 4321').sentText,
        '⟦BANK_1⟧ card ⟦CARD_1⟧',
      );
    });

    test('clitic prefixes, tatweel, diacritics, case, spelling variants', () {
      expect(masked('بكارفور').sentText, 'ب⟦MERCHANT_1⟧');
      expect(masked('وللأهلي حساب').sentText, 'ول⟦BANK_1⟧ حساب');
      expect(masked('كــارفُـور').sentText, '⟦MERCHANT_1⟧');
      expect(masked('cIb ACCOUNT').sentText, '⟦BANK_1⟧ ACCOUNT');
      expect(masked('سى آى بى').sentText, '⟦BANK_1⟧');
      expect(masked('c.i.b').sentText, '⟦BANK_1⟧');
      expect(masked('Carrefour-Maadi').sentText, '⟦MERCHANT_1⟧-Maadi');
      expect(masked('NBEX').sentText, 'NBEX');
      expect(masked('xCIB').sentText, 'xCIB');
    });

    test('typed brackets cannot forge a placeholder', () {
      expect(masked('⟦CARD_1⟧ كارفور').sentText, 'CARD_1 ⟦MERCHANT_1⟧');
    });

    test('scrub tokens are protected from name matches', () {
      const phoneMerchant = StaticMaskSources(
        merchants: [
          MaskMerchant('p', ['Phone']),
        ],
      );
      expect(
        masked('call 01000000000 phone', phoneMerchant).sentText,
        'call ⟦PHONE⟧ ⟦MERCHANT_1⟧',
      );
    });

    test('empty sources and empty text', () {
      expect(masked('', ahmed).sentText, '');
      expect(
        unresolved('كارت 4321', const StaticMaskSources()).reason,
        MaskUnresolvedReason.noSuchCard,
      );
    });

    test('speed: a typical question under the 10 ms budget', () {
      const q = 'صرفت كام بكارت 4321 في كارفور من حسابي في CIB الشهر ده؟';
      masked(q);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        pipeline(q, ahmed);
      }
      expect(sw.elapsedMilliseconds / 200, lessThan(10));
    });
  });

  group('question table (SRS §10.1 style, test/fixtures/llm)', () {
    final lines = File('test/fixtures/llm/questions.tsv')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .toList();
    test('fixture has at least 40 questions', () {
      expect(lines.length, greaterThanOrEqualTo(40));
    });
    for (final line in lines) {
      final cols = line.split('\t');
      test(cols[0], () {
        final o = pipeline(cols[0], ahmedPlus1234);
        final got = o is MaskResult
            ? o.sentText
            : 'UNRESOLVED:${(o as MaskUnresolved).reason.name}';
        expect(got, cols[1]);
      });
    }

    test('NEGATIVE PROOF 1 inspection over the question set', () {
      for (final line in lines) {
        final q = line.split('\t')[0];
        for (final s in [ahmed, ahmedPlus1234]) {
          final o = pipeline(q, s);
          if (o is MaskResult) {
            expectClean(o.sentText, s);
          }
        }
      }
    });
  });

  group('NEGATIVE PROOF 1 (property over generated references)', () {
    final rnd = Random(278);

    String tatweel(String s) {
      final b = StringBuffer();
      for (final r in s.runes) {
        b.writeCharCode(r);
        if (r >= 0x0628 && r <= 0x064A && r != 0x0627 && rnd.nextBool()) {
          b.write('ـ');
        }
      }
      return b.toString();
    }

    String harakat(String s) {
      final b = StringBuffer();
      for (final r in s.runes) {
        b.writeCharCode(r);
        if (r >= 0x0628 && r <= 0x064A && rnd.nextInt(3) == 0) {
          b.write(['َ', 'ُ', 'ِ', 'ّ'][rnd.nextInt(4)]);
        }
      }
      return b.toString();
    }

    String spelling(String s) => s
        .replaceAll('ا', 'أ')
        .replaceAll('ي', 'ى')
        .replaceAll('ه', 'ة')
        .replaceAll('أ', rnd.nextBool() ? 'إ' : 'آ');

    String caseMix(String s) => String.fromCharCodes([
      for (final c in s.codeUnits)
        rnd.nextBool() ? String.fromCharCode(c).toUpperCase().codeUnitAt(0) : c,
    ]);

    String arDigits(String s) => String.fromCharCodes([
      for (final c in s.codeUnits) c >= 0x30 && c <= 0x39 ? c + 0x0630 : c,
    ]);

    const contexts = [
      'صرفت كام في %s النهاردة؟',
      'how much at %s last week?',
      'حسابي في %s',
      'my %s account',
      'كارت %s',
      '%s',
      'compare %s with my account',
      'وصرفت على %s كام؟',
    ];

    final adjacent = [contexts[2], contexts[3], contexts[4]];

    test('every name, every variant, every context: clean or unresolved', () {
      final names = secretNames(ahmedPlus1234, ordinary: true);
      final plain = secretNames(ahmedPlus1234, ordinary: false).toSet();
      var checked = 0;
      for (final n in names) {
        final variants = {
          n,
          n.toUpperCase(),
          n.toLowerCase(),
          caseMix(n),
          tatweel(n),
          harakat(n),
          spelling(n),
          harakat(tatweel(spelling(n))),
          if (RegExp('[؀-ۿ]').hasMatch(n)) 'ب$n',
        };
        for (final v in variants) {
          // A word-like alias is only masked next to a bank/account/card word.
          for (final c in plain.contains(n) ? contexts : adjacent) {
            final q = c.replaceAll('%s', v);
            final o = pipeline(q, ahmedPlus1234);
            if (o is MaskResult) {
              expectClean(o.sentText, ahmedPlus1234, ordinary: true);
            }
            checked++;
          }
        }
      }
      expect(checked, greaterThan(800));
    });

    test(
      'every last-4, digits, card words, positions: clean or unresolved',
      () {
        const words = [
          'كارت',
          'بكارت',
          'بطاقة',
          'فيزا',
          'حساب',
          'حسابي',
          'منتهي',
          'card',
          'account',
          'visa',
          'ending',
        ];
        const fillers = ['', 'بتاعي', 'my', 'رقم', 'منتهي ب'];
        for (final a in ahmedPlus1234.accounts) {
          for (final digits in [a.last4!, arDigits(a.last4!)]) {
            for (final w in words) {
              for (final f in fillers) {
                for (final q in [
                  '$w $f $digits',
                  '$digits $f $w',
                  'صرفت كام $w $f $digits في الشهر',
                  'spent on $w $f $digits',
                  '$w •••• $digits',
                  '$w ****$digits',
                  '$w x$digits',
                ]) {
                  final o = pipeline(q, ahmedPlus1234);
                  if (o is MaskResult) {
                    expectClean(o.sentText, ahmedPlus1234);
                    expect(o.sentText, isNot(contains(a.last4)));
                    expect(o.sentText, isNot(contains(arDigits(a.last4!))));
                  }
                }
              }
            }
          }
        }
      },
    );

    test('no throw on odd input', () {
      for (final q in [
        '',
        ' ',
        '⟦',
        '\u0000',
        '😀' * 50,
        'ا' * 5000,
        '4' * 100,
        '@' * 20,
        'بنك',
        'bank',
      ]) {
        expect(() => pipeline(q, ahmedPlus1234), returnsNormally);
      }
    });
  });

  group('NEGATIVE PROOF 2 (redaction)', () {
    const marker = 'ZZMARKERZZ';
    const markerSources = StaticMaskSources(
      accounts: [
        MaskAccount(
          id: 'id-$marker',
          label: 'Label$marker',
          nickname: 'Nick$marker',
          institutionId: 'inst-$marker',
          type: MaskAccountType.creditCard,
          last4: '7777',
        ),
      ],
      institutions: [
        MaskInstitution('inst-$marker', [MaskAlias('Bank$marker')]),
      ],
      merchants: [
        MaskMerchant('m-$marker', ['Shop$marker']),
      ],
    );

    test('result, map, tokens, targets and candidates never print names', () {
      final r = pipeline(
        'Shop$marker with Nick$marker and Bank$marker card 7777',
        markerSources,
      ) as MaskResult;
      expect(r.sentText, isNot(contains(marker)));
      final printed = [
        r.toString(),
        r.map.toString(),
        for (final t in r.tokens) t.toString(),
        for (final p in r.map.placeholders) r.map[p].toString(),
        markerSources.accounts.first.toString(),
        markerSources.institutions.first.toString(),
        markerSources.institutions.first.aliases.first.toString(),
        markerSources.merchants.first.toString(),
      ].join(' ');
      expect(printed, isNot(contains(marker)));
      expect(printed, isNot(contains('7777')));

      final u = pipeline('card 9999 Shop$marker', markerSources);
      expect(u, isA<MaskUnresolved>());
      expect(u.toString(), isNot(contains(marker)));
      expect(u.toString(), isNot(contains('9999')));
    });

    test('a failing source never throws and never echoes', () {
      final o = ReferenceMasker.mask('Shop$marker', _ThrowingSources());
      expect(o, isA<MaskUnresolved>());
      expect((o as MaskUnresolved).reason, MaskUnresolvedReason.failed);
      expect(o.toString(), isNot(contains(marker)));
    });
  });
}

final class _ThrowingSources implements MaskSources {
  @override
  List<MaskAccount> get accounts => throw Exception('ZZMARKERZZ boom');
  @override
  List<MaskInstitution> get institutions => const [];
  @override
  List<MaskMerchant> get merchants => const [];
}
