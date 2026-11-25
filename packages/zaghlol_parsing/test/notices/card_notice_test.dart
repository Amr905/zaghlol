import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

// T-241 (D-83): card due reminders and statements are notices, never
// transactions. Synthetic texts: the PO suite's cases 7, 8 and 12 with other
// digits. Reads the bundled app registry.
const String _assets = '../../app/assets';

final DateTime _at = DateTime.utc(2026, 11, 25, 10);

const String _case7 =
    'عميلنا العزيز، سيتم خصم 51.77 جم من حسابكم لسداد بطاقتك المنتهية بـ 5490  '
    'في 25/11, في حالة أن يوم السداد يزامن عطلة رسمية سوف يتم الخصم قبل '
    'العطلات الرسمية. يمكنك الاطلاع على تفاصيل كشف الحساب من خلال الرابط '
    'التالي: https://example.invalid/x1';
const String _case8 =
    'كشف حساب شهر أكتوبر 2026  لبطاقتك الائتمانية المنتهية بـ 6603 هو 51.77 جم '
    '، الحد الأدنى للسداد قبل  25/11 هو 51.77 جم .يمكنك الاطلاع على تفاصيل '
    'كشف الحساب من خلال الرابط التالي: https://example.invalid/x1';
const String _case12 =
    'HSBC Credit Card ending *** 2859 Statement Date 03/10/2026. Total Amt Due '
    'EGP 47.82, Due Date 28/10/2026. Min. Amt Due EGP 47.82. Please ignore if '
    'paid.';

Registry _registry() {
  final inst = <String, String>{};
  for (final f in Directory('$_assets/registry/institutions').listSync()) {
    if (f is File) {
      inst[f.uri.pathSegments.last] = f.readAsStringSync();
    }
  }
  return RegistryLoader.load(
    manifest: File('$_assets/registry/registry_manifest.json')
        .readAsStringSync(),
    shared: File('$_assets/registry/shared.json').readAsStringSync(),
    institutions: inst,
  ).registry!;
}

void main() {
  final pipeline = ParsingPipeline(_registry());
  ParseResult parse(String body, String source, [DateTime? at]) =>
      pipeline.parse(
        ParseRequest(
          body: body,
          source: source,
          channel: RegistryChannel.sms,
          receivedAt: at ?? _at,
        ),
      );
  Money egp(String s) => Money.parse(s, Currency.of('EGP'));

  group('templates', () {
    test('case 7: CIB due reminder', () {
      final r = parse(_case7, 'CIB') as ParseNotice;
      expect(r.kind, NoticeKind.ccDue);
      expect(r.templateId, 'cib.cc_due.ar');
      expect(r.last4, '5490');
      expect(r.amountDue, egp('51.77'));
      expect(r.minDue, isNull);
      expect(r.dueDate, DateTime.utc(2026, 11, 25));
    });

    test('case 7: an undated due date is the nearest future date, with a '
        '7-day grace', () {
      final late =
          parse(_case7, 'CIB', DateTime.utc(2026, 11, 26, 9)) as ParseNotice;
      expect(late.dueDate, DateTime.utc(2026, 11, 25));
      final later =
          parse(_case7, 'CIB', DateTime.utc(2026, 12, 5, 9)) as ParseNotice;
      expect(later.dueDate, DateTime.utc(2027, 11, 25));
    });

    test('case 8: CIB statement, total and minimum due', () {
      final r = parse(_case8, 'CIB') as ParseNotice;
      expect(r.kind, NoticeKind.ccStatement);
      expect(r.templateId, 'cib.cc_statement.ar');
      expect(r.last4, '6603');
      expect(r.amountDue, egp('51.77'));
      expect(r.minDue, egp('51.77'));
      expect(r.dueDate, DateTime.utc(2026, 11, 25));
    });

    test('case 12: HSBC statement, both dates, past statement date', () {
      final r = parse(_case12, 'HSBC') as ParseNotice;
      expect(r.kind, NoticeKind.ccStatement);
      expect(r.templateId, 'hsbc.cc_statement.en');
      expect(r.last4, '2859');
      expect(r.amountDue, egp('47.82'));
      expect(r.minDue, egp('47.82'));
      expect(r.statementDate, DateTime.utc(2026, 10, 3));
      expect(r.dueDate, DateTime.utc(2026, 10, 28));
    });
  });

  group('generic notice gate (known bank, no template)', () {
    test(
      'the same wording from another bank is a notice, not a transaction',
      () {
        for (final body in [_case7, _case8, _case12]) {
          final r = parse(body, 'NBE');
          expect(r, isA<ParseNotice>(), reason: 'NBE notice');
          expect((r as ParseNotice).institutionCode, 'nbe');
          expect(r.fromTemplate, isFalse);
        }
        final due = parse(_case7, 'NBE') as ParseNotice;
        expect(due.kind, NoticeKind.ccDue);
        expect(due.amountDue, egp('51.77'));
      },
    );

    test('NEGATIVE PROOF: a due notice from a known bank is never '
        'auto-save eligible', () {
      for (final body in [_case7, _case8, _case12]) {
        expect(genericAutoSaveEligible(parse(body, 'NBE')), isFalse);
        expect(genericAutoSaveEligible(parse(body, 'CIB')), isFalse);
      }
    });

    test('NEGATIVE PROOF: a notice cue beside a purchase is review, not a '
        'transaction and not a notice', () {
      final r = parse(
        'Purchase of EGP 250.00 at SUNNY CORNER with card ending 1937. '
            'Payment due date 28/12/2026',
        'NBE',
      );
      expect(r, isA<ParseUnrecognized>());
      expect(
        (r as ParseUnrecognized).reason,
        UnrecognizedReason.genericNoticeConflict,
      );
      expect(genericAutoSaveEligible(r), isFalse);
    });

    test('past-tense card payment wording is still a payment', () {
      final r = parse(
        'تم الخصم 51.77 جم من حسابكم لسداد بطاقتك المنتهية بـ 5490',
        'NBE',
      );
      expect(r, isA<ParseGeneric>());
      expect((r as ParseGeneric).event, GenericEvent.ccPayment);
    });

    test('a plain purchase from a known bank is unaffected', () {
      final r = parse(
        'Dear customer, EGP 250.00 was debited from your account *4567 at '
            'CARREFOUR MAADI on 09/11/2026',
        'NBE',
      );
      expect(r, isA<ParseGeneric>());
    });
  });

  test('a template cannot declare a notice event with a money direction', () {
    final bad = RegistryLoader.load(
      manifest: '{"schema":1,"registryVersion":1,"institutions":["x"]}',
      shared: File('$_assets/registry/shared.json').readAsStringSync(),
      institutions: {
        'x.json':
            '{"code":"x","names":{"ar":"x","en":"x"},"country":"EG",'
            '"defaultCurrency":"EGP","senders":[{"match":"exact","value":"X"}],'
            '"templates":[{"id":"x.due","version":1,"lang":"en","event":"cc_due",'
            '"direction":"expense","baseConfidence":0.9,'
            '"pattern":"due (?<amount>[\\\\d.]+) (?<cur>egp)"}]}',
      },
    );
    expect(bad.registry, isNull);
  });

  test('a notice event must declare direction neutral (FU-295 n-1)', () {
    RegistryLoadResult load(String dir) => RegistryLoader.load(
      manifest: '{"schema":1,"registryVersion":1,"institutions":["xbank"]}',
      shared: File('$_assets/registry/shared.json').readAsStringSync(),
      institutions: {
        'xbank.json':
            '{"code":"xbank","names":{"ar":"x","en":"x"},"country":"EG",'
            '"defaultCurrency":"EGP","senders":[{"match":"exact","value":"X"}],'
            '"templates":[{"id":"x.due","version":1,"lang":"en",'
            '"event":"cc_statement",$dir"baseConfidence":0.9,'
            '"pattern":"due (?<amount>[\\\\d.]+) (?<cur>egp)"}]}',
      },
    );
    expect(load('').registry, isNull, reason: 'missing direction');
    final ok = load('"direction":"neutral",');
    expect(ok.registry, isNotNull, reason: '${ok.issues}');
  });

  // T-241 fix (M-1): a completed debit or payment with a due or statement
  // tail is never a notice (it would vanish without a trace).
  const moved = {
    'purchase with due date line':
        'تم خصم 200 جم من بطاقتك 1234 لدى كارفور. تاريخ الاستحقاق 25/12',
    'was charged with payment due':
        'Your card 1234 was charged EGP 450.00 at UBER. Payment due 25/12',
    'loan debit with next due date ar':
        'تم خصم 500.00 جم من حسابك لسداد قسط القرض. موعد السداد القادم 05/12',
    'loan debit with next due date en':
        'Your account was debited EGP 1,250.00 for loan installment. '
        'Next due date 05/12/2026',
    'card payment made ar':
        'تم سداد 3000 جم لبطاقتك المنتهية ب 1234. الحد الأدنى للسداد 0 جم',
    'card payment received with statement balance':
        'Payment of EGP 3,000.00 received for credit card ending 1234. '
        'Statement balance EGP 0.00',
    'valU installment paid': 'تم دفع قسط 750 جم. موعد سداد القسط القادم 1/1',
  };
  for (final e in moved.entries) {
    test('NEGATIVE PROOF: ${e.key} is not a notice', () {
      final r = parse(e.value, 'BanqueMisr');
      expect(r, isNot(isA<ParseNotice>()));
      expect(r, isA<ParseUnrecognized>());
      expect(
        (r as ParseUnrecognized).reason,
        UnrecognizedReason.genericNoticeConflict,
      );
    });
  }

  test('future tense stays a notice', () {
    expect(
      parse(
        'سيتم خصم 51.77 جم من حسابكم لسداد بطاقتك المنتهية بـ 5490 في 25/11',
        'BanqueMisr',
      ),
      isA<ParseNotice>(),
    );
    expect(
      parse(
        'EGP 51.77 will be debited from your account for card 5490. '
            'Payment due 25/11',
        'BanqueMisr',
      ),
      isA<ParseNotice>(),
    );
  });
}
