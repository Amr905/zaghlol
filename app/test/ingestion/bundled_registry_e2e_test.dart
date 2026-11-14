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
      expect((manifest['institutions']! as List<Object?>).length, 47);
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
