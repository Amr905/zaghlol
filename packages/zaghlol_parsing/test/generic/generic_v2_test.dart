import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/registry_files.dart';

// T-243: generic reader v2. Synthetic text only. A sender with no template
// (`SOMEBANK`) forces the generic reader.
final DateTime _at = DateTime.utc(2026, 11, 22, 10);

ParsingPipeline _pipeline() {
  final f = RegistryFiles.load(pipelineRoot);
  return ParsingPipeline(
    RegistryLoader.load(
      manifest: f.manifest,
      shared: f.shared,
      institutions: f.institutions,
    ).registry!,
  );
}

void main() {
  _negativeBalanceTests();
  final pipeline = _pipeline();
  ParseResult parse(String body) => pipeline.parse(
    ParseRequest(
      body: body,
      source: 'SOMEBANK',
      channel: RegistryChannel.share,
      receivedAt: _at,
    ),
  );
  ParseGeneric generic(String body) {
    final r = parse(body);
    expect(r, isA<ParseGeneric>());
    return r as ParseGeneric;
  }

  group('PO cases 1, 3, 5 without a template', () {
    test('case 1: glued balance, last-4 after رقم, merchant', () {
      final g = generic(
        'تم خصم 375 EGP  من بطاقة الخصم المباشر رقم 4471  عند KASHIER*BELLA '
        'CUCINA  يوم 21/11/26  الساعه 16:53  المتاح 4667.24EGP  للمزيد إتصل '
        'ب ١٩٦٢٣',
      );
      expect(g.amount.minor, 37500);
      expect(g.direction, TemplateDirection.expense);
      expect(g.last4, '4471');
      expect(g.merchant?.display.toLowerCase(), contains('bella cucina'));
      expect(g.balance?.minor, 466724);
      expect(g.balance?.currency.code, 'EGP');
    });

    test('case 3: 419*6128 mask, balance inherits the amount currency', () {
      final g = generic(
        'EG\nشراء بمبلغ EGP 170.10 من حساب 419*6128 .الرصيد المتوفر 1769.47 .',
      );
      expect(g.amount.minor, 17010);
      expect(g.direction, TemplateDirection.expense);
      expect(g.last4, '6128');
      expect(g.balance?.minor, 176947);
      expect(g.balance?.currency.code, 'EGP');
    });

    test('case 5: trx cue, merchant after from, available balance', () {
      final g = generic(
        'A Trx using Card XXXX8216 from GEIDEAE Nour Market for EGP 263.00 on '
        '20-Nov-2026 at 01:21 GMT+2. Available balance is EGP 36156.47.',
      );
      expect(g.amount.minor, 26300);
      expect(g.direction, TemplateDirection.expense);
      expect(g.last4, '8216');
      expect(g.merchant?.key, 'geideae nour market');
      expect(g.balance?.minor, 3615647);
    });
  });

  group('counterparty (transfers)', () {
    test('out: name with masks, no merchant, stops at the reference', () {
      final g = generic(
        'تم تنفيذ تحويل لحظي من حسابكم رقم xxx2734 بمبلغ 1985 جم إلى '
        'سامي ع*** ف**** ح****** رقم مرجعي 512837460921 يوم 2026-10-26',
      );
      expect(g.counterparty?.name, 'سامي ع*** ف**** ح******');
      expect(g.counterparty?.kind, CounterpartyKind.name);
      expect(g.merchant, isNull);
      expect(g.last4, '2734');
      expect(g.balance, isNull);
    });

    test('in: long name, no word limit', () {
      final g = generic(
        'تم إضافة تحويل لحظي لحسابكم رقم xxx3519 بمبلغ 300 جم من KARIM SAMIR '
        'FATHY ADEL MANSOUR رقم مرجعي 390817265544 يوم 2026-10-28',
      );
      expect(g.direction, TemplateDirection.income);
      expect(g.counterparty?.name, 'KARIM SAMIR FATHY ADEL MANSOUR');
    });

    test('English: ends at on / ref', () {
      final g = generic(
        'You received a transfer of EGP 50.00 from Mona Adel Hassan Ali on '
        '20-Nov-2026',
      );
      expect(g.counterparty?.name, 'Mona Adel Hassan Ali');
    });

    test('to your own account names nobody', () {
      final g = generic('Transfer of EGP 50.00 to your account 1234');
      expect(g.counterparty, isNull);
    });
  });

  group('balance and limit', () {
    test('available limit is kept apart from the balance', () {
      final g = generic(
        'Purchase of EGP 100.00 at ACME STORE. Available limit is EGP '
        '9,000.00',
      );
      expect(g.amount.minor, 10000);
      expect(g.available?.minor, 900000);
      expect(g.balance, isNull);
    });

    test('a balance is never the amount', () {
      final g = generic('Avail bal 5000.00 EGP. Debited EGP 20.00 at SHOP X');
      expect(g.amount.minor, 2000);
      expect(g.balance?.minor, 500000);
    });
  });

  group('last-4', () {
    test('after رقم with a card word nearby', () {
      expect(generic('خصم 20 جم من بطاقتك رقم 1234 عند متجر').last4, '1234');
    });
    test('rejected before a reference', () {
      final g = generic('تم خصم 20 جم من حسابك رقم 1234 مرجعي 5555 عند متجر');
      expect(g.last4, isNot('1234'));
    });
    test('long digit run is not a last-4', () {
      final g = generic('Debited EGP 20.00 card 1234567890123 at SHOP');
      expect(g.last4, isNull);
    });
    test('419*5015 prefix mask', () {
      expect(generic('Purchase EGP 5.00 acct 419*5015 at SHOP').last4, '5015');
    });
  });

  group('direction cues', () {
    test('has been used for', () {
      final g = generic('Your card ending 1111 has been used for EGP 80.00');
      expect(g.direction, TemplateDirection.expense);
    });
    test('credited still income', () {
      final g = generic('EGP 80.00 credited to your account ending 1111');
      expect(g.direction, TemplateDirection.income);
    });
  });

  group('merchant anchors', () {
    test('function words and links are not merchants', () {
      final g = generic(
        'تم خصم 40 جم من بطاقتك رقم 3333 في حالة الطوارئ من خلال الرابط '
        'https://example.invalid/x1',
      );
      expect(g.merchant, isNull);
    });
    test('inner dots stay in the merchant', () {
      final g = generic('Purchase EGP 90.00 at AMAZON.EG card ending 2222.');
      expect(g.merchant?.display.toLowerCase(), contains('amazon.eg'));
    });
  });

  group('T&C footer', () {
    test('fee footer only is not a transaction', () {
      final r = parse(
        'A late fee of EGP 150.00 applies if payment is not received by the '
        'due date. Terms and conditions apply.',
      );
      expect(r is ParseGeneric || r is ParseParsed, isFalse);
    });
    test('a real purchase with a footer still parses', () {
      final g = generic(
        'Purchase of EGP 150.00 at SHOP X. A late fee of EGP 50.00 applies '
        'if unpaid.',
      );
      expect(g.amount.minor, 15000);
    });
    test('a posted fee is still a transaction (batch 68 M-2)', () {
      for (final body in [
        'A late fee of EGP 150.00 has been charged to your card ending 1234.',
        'Late fee EGP 150.00 debited from card 1234',
        'تم خصم غرامه تاخير 150 جم من بطاقتك 1234',
        'Annual fee of EGP 300.00 debited from card 1234',
      ]) {
        final g = generic(body);
        expect(g.direction, TemplateDirection.expense, reason: body);
        expect(g.last4, '1234', reason: body);
      }
    });
    test('a conditional fee sentence is a footer', () {
      final r = parse(
        'A late fee of EGP 150.00 will be charged if not paid. '
        'Terms and conditions apply.',
      );
      expect(r is ParseGeneric || r is ParseParsed, isFalse);
    });
  });
}

// T-256 / FU-078: an overdrawn balance stays negative in the generic reader.
void _negativeBalanceTests() {
  final pipeline = _pipeline();
  ParseGeneric g(String body) => pipeline.parse(
    ParseRequest(
      body: body,
      source: 'SOMEBANK',
      channel: RegistryChannel.share,
      receivedAt: _at,
    ),
  ) as ParseGeneric;
  group('FU-078 negative balance (generic)', () {
    test('available balance is EGP -500.00', () {
      final r = g(
        'Purchase of EGP 170.10 at SHOP card 6128. '
        'Available balance is EGP -500.00.',
      );
      expect(r.amount.minor, 17010);
      expect(r.balance?.minor, -50000);
    });
    test('balance: -500.00 EGP', () {
      final r = g(
        'Purchase of EGP 170.10 at SHOP card 6128. Balance: -500.00 EGP',
      );
      expect(r.balance?.minor, -50000);
    });
    test('positive balance unchanged', () {
      final r = g(
        'Purchase of EGP 170.10 at SHOP card 6128. Balance: 500.00 EGP',
      );
      expect(r.balance?.minor, 50000);
    });
  });
}
