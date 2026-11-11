import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/registry_files.dart';

void main() {
  final base = RegistryFiles.load();
  final reg = RegistryLoader.load(
    manifest: base.manifest,
    shared: base.shared,
    institutions: base.institutions,
  ).registry!;
  final nbe = reg.byCode('nbe')!;
  final cib = reg.byCode('cib')!;
  final at = DateTime.utc(2026, 10, 23, 11, 14);

  Template tpl(Institution i, String id) =>
      i.templates.firstWhere((t) => t.id == id);

  ExtractedFields run(Institution i, String id, String body) {
    final t = tpl(i, id);
    final groups = matchTemplate(t, foldBody(body))!;
    return extractFields(i, t, groups, at);
  }

  group('parseTemplateDate', () {
    DatePolicy p(String f, {bool nearest = true}) => DatePolicy(f, nearest);
    final rows = <(String, String, DatePolicy, DateTime, String?)>[
      ('d/M this year', '23/10', p('d/M'), at, '2026-10-23'),
      ('same day is not in the future', '23/10', p('d/M'), at, '2026-10-23'),
      ('tomorrow wraps to last year', '24/10', p('d/M'), at, '2025-10-24'),
      ('dd/MM/yyyy', '05/01/2024', p('dd/MM/yyyy'), at, '2024-01-05'),
      ('d-M-yy', '5-1-24', p('d-M-yy'), at, '2024-01-05'),
      ('dotted', '5.1.2024', p('d.M.yyyy'), at, '2024-01-05'),
      (
        'Feb 29 leap year',
        '29/02',
        p('d/M'),
        DateTime.utc(2028, 3, 1),
        '2028-02-29',
      ),
      (
        'Feb 29 looks back to a leap year',
        '29/02',
        p('d/M'),
        DateTime.utc(2026, 3, 1),
        '2024-02-29',
      ),
      ('Feb 30 invalid', '30/02', p('d/M'), at, null),
      ('month 13 invalid', '1/13', p('d/M'), at, null),
      ('day 0 invalid', '0/5', p('d/M'), at, null),
      ('wrong separator', '23-10', p('d/M'), at, null),
      ('too many parts', '1/2/3', p('d/M'), at, null),
      ('letters', 'ab/cd', p('d/M'), at, null),
      (
        'received-year policy',
        '24/10',
        p('d/M', nearest: false),
        at,
        '2026-10-24',
      ),
    ];
    for (final (name, raw, policy, received, expected) in rows) {
      test(name, () {
        final d = parseTemplateDate(raw, policy, received);
        expect(
          d == null
              ? null
              : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
          expected,
        );
      });
    }
  });

  group('currency policy', () {
    test(r'$ on an EGP account is USD (FU-051)', () {
      final f = run(
        cib,
        'cib.card_symbol.en',
        r'CIB: Purchase $ 12.50 at NETFLIX card *9876',
      );
      expect(f.amount!.currency.code, 'USD');
      expect(f.problems, isEmpty);
    });

    test('an unresolvable currency capture is a problem, not the default', () {
      final f = run(
        cib,
        'cib.kwd_credit.en',
        'CIB: Credited bhd 1.000 to account *9876',
      );
      expect(f.amount!.currency.code, 'BHD');
      // Template currencies without a map entry still resolve as ISO codes;
      // an unknown marker must not fall back silently.
      final t = tpl(nbe, 'nbe.card_purchase.ar');
      final f2 = extractFields(nbe, t, {'amount': '10', 'cur': 'zzz'}, at);
      expect(f2.problems, containsAll(['currency']));
      expect(f2.amount, isNull);
    });

    test('no cur group uses the institution default', () {
      final f = run(
        cib,
        'cib.instapay_out.en',
        'CIB: You sent EGP 5.00 to 01012345678 via InstaPay. Ref 123456',
      );
      expect(f.amount!.currency.code, 'EGP');
    });

    test('excess precision is a problem, never rounded', () {
      final t = tpl(nbe, 'nbe.salary.ar');
      final f = extractFields(nbe, t, {'amount': '10.555', 'cur': 'جم'}, at);
      expect(f.amount, isNull);
      expect(f.problems, contains('amount'));
    });

    test('zero amount is a problem', () {
      final t = tpl(nbe, 'nbe.salary.ar');
      final f = extractFields(nbe, t, {'amount': '0.00'}, at);
      expect(f.problems, contains('amount'));
    });
  });

  group('field reading', () {
    test(
      'trailing sentence punctuation after a number is dropped (FU-051)',
      () {
        final f = run(
          nbe,
          'nbe.salary.ar',
          'تم ايداع راتب 12000. جم في حسابكم رقم **1234 بتاريخ 02/10/2026',
        );
        expect(f.amount!.toCanonicalString(), '12000.00');
      },
    );

    test('last4 that is not four digits is reported', () {
      final t = tpl(nbe, 'nbe.card_purchase.ar');
      final f = extractFields(nbe, t, {'amount': '1', 'last4': '12'}, at);
      expect(f.problems, contains('last4'));
      expect(f.last4, isNull);
    });

    test('merchant that cleans to nothing is reported', () {
      final t = tpl(nbe, 'nbe.card_purchase.ar');
      final f = extractFields(nbe, t, {'amount': '1', 'merchant': '   '}, at);
      expect(f.merchant, isNull);
    });

    test('shared merchantCleaning city list is applied', () {
      final t = tpl(nbe, 'nbe.declined.en');
      final f = extractFields(
        nbe,
        t,
        {'amount': '1', 'merchant': 'FATHALLA SMOUHA'},
        at,
        cleaning: reg.shared.merchantCleaning,
      );
      expect(f.merchant!.display, 'Fathalla');
    });

    test('ocur without a map or ISO code is a problem', () {
      final t = tpl(nbe, 'nbe.card_foreign.en');
      final f = extractFields(nbe, t, {
        'amount': '1',
        'oamount': '2',
        'ocur': 'qq',
      }, at);
      expect(f.problems, contains('originalCurrency'));
    });
  });

  test('matchTemplate returns null for a non-matching body', () {
    expect(matchTemplate(tpl(nbe, 'nbe.salary.ar'), 'hello'), isNull);
  });

  group('matchTemplateOriginal (display text from the original)', () {
    final pipeReg = () {
      final f = RegistryFiles.load(pipelineRoot);
      return RegistryLoader.load(
        manifest: f.manifest,
        shared: f.shared,
        institutions: f.institutions,
      ).registry!;
    }();
    final cibAr = pipeReg
        .byCode('cib')!
        .templates
        .firstWhere((t) => t.id == 'cib.instapay_out.ar');

    Map<String, String> orig(String body) =>
        matchTemplateOriginal(cibAr, foldKeyIndexed(body), body)!;

    test('Arabic counterparty keeps its letters, folded capture does not', () {
      const body =
          'تم تحويل 500.00 جم إلى أحمد محمود عبر إنستاباي. رقم مرجعي 123456789';
      expect(orig(body)['counterparty'], 'أحمد محمود');
      // The folded capture (the T-032 behaviour) shows the folded letters.
      expect(
        matchTemplate(cibAr, foldBody(body))!['counterparty'],
        'احمد محمود',
      );
    });

    test('tatweel and harakat are dropped, digits normalized', () {
      const body =
          'تم تحويل ٥٠٠٫٠٠ جم إلى مُـحَمَّد عبر إنستاباي. رقم مرجعي ١٢٣٤٥٦٧٨';
      final g = orig(body);
      expect(g['counterparty'], 'محمد');
      expect(g['ref'], '12345678');
      expect(g['amount'], '500.00');
    });

    test('non-display groups stay as folded text', () {
      const body =
          'تم تحويل 500.00 جم إلى إيمان عبر إنستاباي. رقم مرجعي 123456789. الرصيد 2400.50';
      final g = orig(body);
      expect(g['amount'], '500.00');
      expect(g['balance'], '2400.50');
    });

    test('Latin ids keep their case', () {
      final cibEn = pipeReg
          .byCode('cib')!
          .templates
          .firstWhere((t) => t.id == 'cib.instapay_out.en');
      const body =
          'CIB: You sent EGP 5.00 to Omar.K@instapay via InstaPay. Ref aBc123XyZ';
      final g = matchTemplateOriginal(cibEn, foldKeyIndexed(body), body)!;
      expect(g['ipa'], 'Omar.K@instapay');
      expect(g['ref'], 'aBc123XyZ');
    });

    test(
      'the same text twice in the match falls back to the folded capture',
      () {
        // The capture `الي` (folded) also appears in the template literal
        // before it, so its position is ambiguous: folded text, never a wrong
        // span.
        const body =
            'تم تحويل 5.00 جم إلى إلى عبر إنستاباي. رقم مرجعي 123456789';
        expect(orig(body)['counterparty'], 'الي');
      },
    );

    test('returns null when the pattern does not match', () {
      const body = 'hello';
      expect(matchTemplateOriginal(cibAr, foldKeyIndexed(body), body), isNull);
    });
  });
}
