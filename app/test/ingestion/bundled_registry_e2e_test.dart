// SMS-TEMPLATES: the bundled registry and the Guard base generated from it,
// end to end on the Dart side: sender -> Guard (the real generated base) ->
// ingest (the real registry) -> a stored transaction. All messages are the
// PO's synthetic samples.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../features/ingestion/support/ingest_harness.dart';

const String _guardBase = 'assets/guard/guard_base.json';

typedef _Case = ({
  String name,
  String sender,
  String body,
  String direction,
  int amountMinor,
  String? last4,
  String? merchant,
  String? counterpartyKind,
  String? counterpartyValue,
});

const List<_Case> _cases = [
  (
    name: 'Banque Misr purchase (EN)',
    sender: 'BanqueMisr',
    body:
        'BM: Purchase of EGP 50.00 with card ****8901 at GOURMET. '
        'Avl Bal EGP 15,200.50',
    direction: 'expense',
    amountMinor: 5000,
    last4: '8901',
    merchant: 'Gourmet',
    counterpartyKind: null,
    counterpartyValue: null,
  ),
  (
    name: 'CIB purchase (AR)',
    sender: 'CIB',
    body:
        'البنك التجاري الدولي: عملية شراء بمبلغ 450.00 جم لدى UBER EG '
        'ببطاقة ينتهي رقمها بـ 1234. الرصيد 4500.20 جم',
    direction: 'expense',
    amountMinor: 45000,
    last4: '1234',
    merchant: 'Uber',
    counterpartyKind: null,
    counterpartyValue: null,
  ),
  (
    name: 'QNB purchase with a date (EN, Arabic-Indic digits)',
    sender: 'QNB',
    body:
        'QNB: Purchase of EGP ٣٠٠٫٠٠ made on 23/10 with Card ****٤٣٢١ at '
        'MCDONALDS. Avl Bal EGP 8,100.00',
    direction: 'expense',
    amountMinor: 30000,
    last4: '4321',
    merchant: 'Mcdonalds',
    counterpartyKind: null,
    counterpartyValue: null,
  ),
  (
    name: 'InstaPay transfer to an IPA',
    sender: 'InstaPay',
    body:
        'InstaPay: You transferred EGP 1,250.00 to ahmed.ali@instapay from '
        'A/C *4567. Ref: 62910482112',
    direction: 'transfer_out',
    amountMinor: 125000,
    last4: '4567',
    merchant: null,
    counterpartyKind: 'ipa',
    counterpartyValue: 'ahmed.ali@instapay',
  ),
  (
    name: 'Vodafone Cash transfer to a phone (AR)',
    sender: 'VodafoneCash',
    body:
        'فودافون كاش: تم تحويل 500.00 جنيه إلى 01098765432. '
        'رصيدك الحالي 1240.00 جنيه',
    direction: 'transfer_out',
    amountMinor: 50000,
    last4: null,
    merchant: null,
    counterpartyKind: 'phone',
    counterpartyValue: '01098765432',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final base = File(_guardBase).readAsBytesSync();
  final guard = CaptureGuard.load(base);

  test(
    'the pubspec asset wiring loads the same registry as the files',
    () async {
      final registry = await preloadBundledRegistry();
      expect(bundledRegistrySync(), same(registry));
      final manifest = jsonDecode(
        File('assets/registry/registry_manifest.json').readAsStringSync(),
      ) as Map<String, Object?>;
      expect((manifest['institutions']! as List<Object?>).length, 64);
      for (final c in _cases) {
        expect(
          registry.resolveSource(c.sender, RegistryChannel.sms),
          isNotNull,
          reason: c.name,
        );
      }
    },
  );

  for (final c in _cases) {
    test(
      '${c.name}: Guard keeps it, ingest stores the right transaction',
      () async {
        final decision = guard.decide(
          channel: 'sms',
          source: c.sender,
          body: c.body,
        );
        expect(
          decision,
          isA<GuardKeep>(),
          reason: 'the generated base passes the sender',
        );

        final registry = await preloadBundledRegistry();
        final w = await IngestWorld.open();
        addTearDown(w.close);
        final result = await w.useCase(
          registry: registry,
          guardBase: BytesGuardBase(base),
        )([sms('d1', c.body, source: c.sender)]);
        expect(result.outcomes['d1'], isA<IngestInserted>());
        final t = (await w.txns()).single;
        expect(t['direction'], c.direction);
        expect(t['amount_minor'], c.amountMinor);
        expect(t['currency'], 'EGP');
        expect(t['acc_last4'], c.last4);
        expect(
          t['merchant_norm'] == null ? null : t['merchant_raw'],
          c.merchant,
        );
        expect(t['counterparty_kind'], c.counterpartyKind);
        expect(t['counterparty_value'], c.counterpartyValue);
      },
    );
  }

  test(
    'a foreign-only NBE message stores a USD expense and no balance',
    () async {
      const body =
          'NBE: Purchase of USD 1000.00 at NETFLIX.COM with NBE Visa **4567. '
          'Avl Bal EGP 5000.00';
      final registry = await preloadBundledRegistry();
      final w = await IngestWorld.open();
      addTearDown(w.close);
      final result = await w.useCase(
        registry: registry,
        guardBase: BytesGuardBase(base),
      )([sms('fx1', body, source: 'NBE')]);
      expect(result.outcomes['fx1'], isA<IngestInserted>());
      final t = (await w.txns()).single;
      expect(t['direction'], 'expense');
      expect(t['amount_minor'], 100000);
      expect(t['currency'], 'USD');
      expect(t['balance_after_minor'], isNull);
    },
  );

  // SMS-AUTO: the PO's real-phone HSBC messages (synthetic digits, same
  // wording) must reach a stored transaction for every sender spelling.
  for (final sender in ['HSBC', 'HSBC EG', 'HSBC-EG', 'HSBC_EGY']) {
    for (final c in const [
      (
        body:
            'Your Credit Card ending with * 5075 has been used for USD 114.00 '
            'on 09/11/2026 at ANTHROPIC* CLAUDE SUB. Your available limit is '
            'EGP 110095.29',
        minor: 11400,
        currency: 'USD',
      ),
      (
        body:
            'Your Credit Card ending with * 9375 has been used for EGP 1958.40 '
            'on 08/11/2026 at UDEMY SUBSCRIPTION. Your available limit is '
            'EGP 27622.16',
        minor: 195840,
        currency: 'EGP',
      ),
    ]) {
      test(
        'HSBC "$sender" ${c.currency} card use is saved, not reviewed',
        () async {
          expect(
            guard.decide(channel: 'sms', source: sender, body: c.body),
            isA<GuardKeep>(),
          );
          final registry = await preloadBundledRegistry();
          final w = await IngestWorld.open();
          addTearDown(w.close);
          final result = await w.useCase(
            registry: registry,
            guardBase: BytesGuardBase(base),
          )([sms('h1', c.body, source: sender)]);
          expect(result.outcomes['h1'], isA<IngestInserted>());
          final t = (await w.txns()).single;
          expect(t['direction'], 'expense');
          expect(t['amount_minor'], c.minor);
          expect(t['currency'], c.currency);
        },
      );
    }
  }

  // SMS-po42: the PO's real-phone reports of 2026-11-18 (synthetic digits,
  // same wording).
  const promo =
      'بنفكرك إن فاضل 3 أيام على السحب الجاي. اربط شهادة الدهب دلوقتي وحتى آخر '
      'الشهر من خلال خدمات الإنترنت البنكية، لضمان فرصتك في دخول السحب على '
      'كيلو دهب أو جنيه من 25 جنيه دهب. شهادة الدهب متاحة لفترة محدودة. هذه '
      'المسابقة تحت إشراف وزارة التضامن الإجتماعي بترخيص رقم 7 لسنة 2026. '
      'تطبق الشروط والأحكام. رقم ت.ض: 100200300.';

  test('the CIB gold-certificate promo is dropped by the Guard', () {
    expect(
      guard.decide(channel: 'sms', source: 'CIB', body: promo),
      isA<GuardDrop>(),
    );
  });

  for (final c in const [
    (name: 'full promo', sender: 'CIB', body: promo),
    (
      name: 'promo without the drop phrases',
      sender: 'CIB',
      body:
          'اربط شهادة الدهب دلوقتي لضمان فرصتك في السحب على كيلو دهب أو '
          'جنيه من 25 جنيه دهب.',
    ),
  ]) {
    test('CIB ${c.name}: never a stored transaction', () async {
      final registry = await preloadBundledRegistry();
      final w = await IngestWorld.open();
      addTearDown(w.close);
      await w.useCase(registry: registry, guardBase: BytesGuardBase(base))([
        sms('p1', c.body, source: c.sender),
      ]);
      expect(await w.txns(), isEmpty);
      for (final r in await w.reviews()) {
        expect('${r['payload']}', isNot(contains('"direction"')));
      }
    });
  }

  for (final c in const [
    (
      name: 'Arab Bank InstaPay out (sender EG)',
      sender: 'EG',
      body:
          'تم تنفيذ تحويل لحظي بمبلغ EGP 50020.00 بتاريخ 28/10/2026 18:10. '
          'من حسابك 419*5044 الى AMR MOUSA  . رقم مرجعي77700668421. الرصيد '
          'المتوفر EGP 12320.23 للمزيد 19100.',
      direction: 'transfer_out',
      minor: 5002000,
      currency: 'EGP',
      last4: '5044',
    ),
    (
      name: 'Arab Bank salary in USD (sender ArabBankEG)',
      sender: 'ArabBankEG',
      body: 'قيد راتب بمبلغ USD 59.66 لحساب 410*5045 بتاريخ 26/10/2026 .',
      direction: 'income',
      minor: 5966,
      currency: 'USD',
      last4: '5045',
    ),
    (
      name: 'Mashreq card use (sender Mashreq-e&)',
      sender: 'Mashreq-e&',
      body:
          'تم استخدام بطاقتكم المنتهية ب9117  في 8180044-SAUDI GERMAN H '
          'بمبلغ EGP 2,000.00.',
      direction: 'expense',
      minor: 200000,
      currency: 'EGP',
      last4: '9117',
    ),
    (
      name: 'Vodafone Cash send (sender VF-Cash)',
      sender: 'VF-Cash',
      body:
          'تم تحويل 100.00 جنيه بنجاح الى رقم 01012345678. رصيدك الحالي '
          '250.00 جنيه. رقم العملية 987654321',
      direction: 'transfer_out',
      minor: 10000,
      currency: 'EGP',
      last4: null,
    ),
  ]) {
    test('${c.name}: Guard keeps it, ingest stores it', () async {
      expect(
        guard.decide(channel: 'sms', source: c.sender, body: c.body),
        isA<GuardKeep>(),
      );
      final registry = await preloadBundledRegistry();
      final w = await IngestWorld.open();
      addTearDown(w.close);
      final result = await w.useCase(
        registry: registry,
        guardBase: BytesGuardBase(base),
      )([sms('q1', c.body, source: c.sender)]);
      expect(result.outcomes['q1'], isA<IngestInserted>());
      final t = (await w.txns()).single;
      expect(t['direction'], c.direction);
      expect(t['amount_minor'], c.minor);
      expect(t['currency'], c.currency);
      expect(t['acc_last4'], c.last4);
    });
  }

  test(
    'an unknown sender with a non-financial text is dropped by the Guard',
    () {
      final d = guard.decide(
        channel: 'sms',
        source: 'NotABank',
        body: 'See you at five, bring the keys',
      );
      expect(d, isA<GuardDrop>());
    },
  );
}
