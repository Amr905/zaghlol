import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

// Real-phone regression (2026-11-15): synthetic card/amount values only.
// Reads the bundled app registry and generated Guard base.
const String _assets = '../../app/assets';

final DateTime _at = DateTime.utc(2026, 11, 11, 10);

const String _usd =
    'Your Credit Card ending with * 4417 has been used for USD 38.50 on '
    '09/11/2026 at ANTHROPIC* CLAUDE SUB. Your available limit is EGP 98765.43';
const String _egp =
    'Your Credit Card ending with * 8821 has been used for EGP 1,250.75 on '
    '08/11/2026 at UDEMY SUBSCRIPTION. Your available limit is EGP 21034.10';

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
  final registry = _registry();
  final pipeline = ParsingPipeline(registry);
  final guard = CaptureGuard(
    parseGuardConfig(File('$_assets/guard/guard_base.json').readAsBytesSync())
        .config!,
  );

  ParseResult parse(
    String body,
    String source, [
    RegistryChannel ch = RegistryChannel.sms,
  ]) => pipeline.parse(
    ParseRequest(body: body, source: source, channel: ch, receivedAt: _at),
  );

  group('HSBC real wording', () {
    for (final sender in ['HSBC', 'hsbc', 'HSBC EG', 'HSBC-EG', 'HSBC_EGY']) {
      test('sender "$sender": Guard keeps, template parses', () {
        expect(
          guard.decide(channel: 'sms', source: sender, body: _usd),
          isA<GuardKeep>(),
        );
        final r = parse(_usd, sender);
        expect(r, isA<ParseParsed>());
        final f = (r as ParseParsed).fields;
        expect(r.templateId, 'hsbc.card_used_limit.en');
        expect(f.amount!.currency.code, 'USD');
        expect(f.amount!.minor, 3850);
        expect(f.last4, '4417');
        expect(f.available!.currency.code, 'EGP');
        expect(f.available!.minor, 9876543);
        expect(f.balance, isNull);
        expect(f.date, DateTime.utc(2026, 11, 9));
      });
    }

    test('EGP purchase with thousands', () {
      final r = parse(_egp, 'HSBC') as ParseParsed;
      expect(r.fields.amount!.minor, 125075);
      expect(r.fields.merchant!.display, 'Udemy Subscription');
    });

    test('arbitrary senders do not resolve to HSBC', () {
      for (final s in ['HSBCX', 'MYHSBC', 'HSBC EG PROMO', 'XHSBC']) {
        expect(
          registry.resolveSource(s, RegistryChannel.sms),
          isNull,
          reason: s,
        );
      }
    });
  });

  group('any registered bank: unknown wording falls back to generic', () {
    for (final s in ['NBE', 'CIB', 'BanqueMisr', 'QNB', 'Citibank', 'AAIB']) {
      test(s, () {
        final r = parse(_egp, s);
        expect(r, isA<ParseGeneric>());
        final g = r as ParseGeneric;
        expect(g.institutionCode, isNotNull);
        expect(g.amount.currency.code, 'EGP');
        expect(g.amount.minor, 125075);
        expect(g.last4, '8821');
        expect(g.direction, TemplateDirection.expense);
        expect(g.merchant!.display, 'Udemy Subscription');
        expect(g.occurredAt.day, 8);
        expect(g.confidencePermille, lessThan(kAutoAcceptThresholdPermille));
      });
    }

    test('foreign currency stays foreign', () {
      final g = parse(_usd, 'CIB') as ParseGeneric;
      expect(g.amount.currency.code, 'USD');
      expect(g.amount.minor, 3850);
      expect(g.last4, '4417');
    });

    test('unknown sender via share keeps the fields', () {
      final g = parse(_usd, 'whatever', RegistryChannel.share) as ParseGeneric;
      expect(g.institutionCode, isNull);
      expect(g.amount.minor, 3850);
      expect(g.last4, '4417');
    });
  });

  group('generic card shapes', () {
    final cases = <(String, String, int, String, String, String?)>[
      // body, currency, minor, last4, merchantDisplay, day
      (
        'Card ending 1234 charged USD 20.00 at SHELL 5 on 05/11',
        'USD',
        2000,
        '1234',
        'Shell',
        '5',
      ),
      (
        'Purchase of EGP 100.00 at ZARA with card **5075',
        'EGP',
        10000,
        '5075',
        'Zara',
        null,
      ),
      (
        'Your card xx5075 was used for 250.50 EGP at TALABAT on 03/11/2026',
        'EGP',
        25050,
        '5075',
        'Talabat',
        '3',
      ),
      (
        'Card ending in *5075: spent EGP 75.00 at MCDONALDS',
        'EGP',
        7500,
        '5075',
        'Mcdonalds',
        null,
      ),
      (
        'تم استخدام بطاقتك المنتهية برقم ١٢٣٤ لشراء بمبلغ ٢٥٠٫٥٠ جم لدى كارفور بتاريخ 09/11/2026',
        'EGP',
        25050,
        '1234',
        'كارفور',
        '9',
      ),
      (
        'عملية شراء بمبلغ 99 جم لدى طلبات ببطاقة تنتهي بـ 7788',
        'EGP',
        9900,
        '7788',
        'طلبات',
        null,
      ),
    ];
    for (var i = 0; i < cases.length; i++) {
      test('case $i', () {
        final c = cases[i];
        final r = parse(c.$1, 'CIB');
        expect(r, isA<ParseGeneric>());
        final g = r as ParseGeneric;
        expect(g.amount.currency.code, c.$2);
        expect(g.amount.minor, c.$3);
        expect(g.last4, c.$4);
        expect(g.merchant?.display, c.$5);
        expect(g.direction, TemplateDirection.expense);
        if (c.$6 != null) {
          expect(g.occurredAt.day, int.parse(c.$6!));
        }
      });
    }
  });
}
