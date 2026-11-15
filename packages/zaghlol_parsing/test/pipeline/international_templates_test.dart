import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

// T-071 / T-072: international and GCC templates through the full pipeline
// (FX conversion legs, pending then settled, Indian grouping, 3-decimal KWD).
// Synthetic wording; every template is tagged `synthetic-unverified`.
const String _registryDir = '../../app/assets/registry';

ParsingPipeline _pipeline() {
  final institutions = <String, String>{};
  for (final f in Directory('$_registryDir/institutions').listSync()) {
    if (f is File) institutions[f.uri.pathSegments.last] = f.readAsStringSync();
  }
  final load = RegistryLoader.load(
    manifest: File('$_registryDir/registry_manifest.json').readAsStringSync(),
    shared: File('$_registryDir/shared.json').readAsStringSync(),
    institutions: institutions,
  );
  if (load.issues.isNotEmpty) {
    throw StateError("registry failed to load");
  }
  return ParsingPipeline(load.registry!);
}

ParseParsed _parse(
  ParsingPipeline p,
  String source,
  String body, {
  RegistryChannel channel = RegistryChannel.sms,
}) {
  final r = p.parse(
    ParseRequest(
      body: body,
      source: source,
      channel: channel,
      receivedAt: DateTime.utc(2026, 10, 23, 11, 14),
    ),
  );
  expect(r, isA<ParseParsed>());
  return r as ParseParsed;
}

void main() {
  final p = _pipeline();

  test('Wise USD to EGP conversion gives fx_conversion with two legs', () {
    final r = _parse(
      p,
      'com.transferwise.android',
      'Conversion complete\nYou converted 100.00 USD to 4,850.00 EGP',
      channel: RegistryChannel.notification,
    );
    expect(r.event, TemplateEvent.fxConversion);
    expect(r.fields.amount!.currency.code, 'USD');
    expect(r.fields.amount!.minor, 10000);
    expect(r.fields.originalAmount!.currency.code, 'EGP');
    expect(r.fields.originalAmount!.minor, 485000);
    expect(r.needsReview, isFalse);
  });

  test('Revolut pending then settled: same merchant, amount may change', () {
    final pending = _parse(
      p,
      'com.revolut.revolut',
      'Payment pending\n€60.00 pending at SHELL FUEL',
      channel: RegistryChannel.notification,
    );
    final settled = _parse(
      p,
      'com.revolut.revolut',
      'Payment completed\n€62.35 completed at SHELL FUEL',
      channel: RegistryChannel.notification,
    );
    expect(pending.event, TemplateEvent.pendingAuth);
    expect(settled.event, TemplateEvent.settled);
    expect(pending.fields.merchant!.key, settled.fields.merchant!.key);
    expect(pending.fields.amount!.minor, 6000);
    expect(settled.fields.amount!.minor, 6235);
  });

  test('HDFC Indian grouping 1,23,456.78 (EC-51)', () {
    final r = _parse(
      p,
      'HDFCBK',
      'HDFC Bank: Spent Rs.1,23,456.78 On HDFC Bank Credit Card xx4242 At APPLE STORE On 2026-10-22:11:14:00.Avl Lmt Rs.2,50,000.00',
    );
    expect(r.fields.amount!.currency.code, 'INR');
    expect(r.fields.amount!.minor, 12345678);
    expect(r.fields.available!.minor, 25000000);
    expect(r.fields.last4, '4242');
  });

  test('Rupee symbol parses', () {
    final r = _parse(
      p,
      'HDFCBK',
      'HDFC Bank: Spent ₹1,23,456.78 On HDFC Bank Card 4242 At AMAZON.IN',
    );
    expect(r.fields.amount!.currency.code, 'INR');
    expect(r.fields.amount!.minor, 12345678);
  });

  test('Warba KWD 12.345 keeps three decimals (EC-36)', () {
    final r = _parse(
      p,
      'Warba',
      'Warba: Purchase KWD 12.345 at TALABAT using card *4242. Balance KWD 1,234.567',
    );
    expect(r.fields.amount!.currency.code, 'KWD');
    expect(r.fields.amount!.minor, 12345);
    expect(r.fields.balance!.minor, 1234567);
  });

  test('Wise foreign card purchase: charged account amount + foreign', () {
    final r = _parse(
      p,
      'com.transferwise.android',
      'Card payment\nYou spent 25.00 USD at AMAZON (charged 19.80 GBP)',
      channel: RegistryChannel.notification,
    );
    expect(r.fields.amount!.currency.code, 'GBP');
    expect(r.fields.amount!.minor, 1980);
    expect(r.fields.originalAmount!.currency.code, 'USD');
    expect(r.fields.originalAmount!.minor, 2500);
  });

  test('Al Rajhi Arabic multi-line SMS with Arabic digits', () {
    final r = _parse(
      p,
      'AlRajhiBank',
      'شراء نقاط البيع\nبطاقة: ٤٢٤٢;مدى\nالمبلغ: SAR ٢٥٫٥٠\nلدى: TESCO',
    );
    expect(r.fields.amount!.currency.code, 'SAR');
    expect(r.fields.amount!.minor, 2550);
    expect(r.fields.last4, '4242');
  });

  test('every T-071/T-072 template is tagged synthetic-unverified', () {
    for (final code in [
      'wise',
      'revolut',
      'monzo',
      'bunq',
      'n26',
      'payoneer',
      'hdfc',
      'paytm',
      'alrajhi',
      'enbd',
      'liv',
      'warba',
    ]) {
      final text = File('$_registryDir/institutions/$code.json')
          .readAsStringSync();
      final templates = RegExp(r'"id": "').allMatches(text).length;
      final tagged = RegExp('"source": "synthetic-unverified"')
          .allMatches(text)
          .length;
      expect(tagged, templates, reason: code);
    }
  });
}
