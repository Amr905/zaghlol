// T-241 (D-83): a card due reminder or statement is a notice, never a
// transaction. Real bundled registry and Guard base; synthetic messages (the
// PO suite's cases 7, 8 and 12 with other digits).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/ingestion/data/ingest_factory.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_ports.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart' hide CategorySource;

import '../features/ingestion/support/ingest_harness.dart';

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
const String _ccPaymentPast =
    'البنك التجاري الدولي: تم استلام سداد بمبلغ 5000.00 جم على بطاقة '
    'الائتمان المنتهية بـ 1234. الحد المتاح 110095.29 جم';

final int _rx = DateTime.utc(2026, 11, 25, 8).millisecondsSinceEpoch;

final class _Recorder implements CardNoticeHook {
  final List<CardNoticeEvent> events = [];

  @override
  Future<void> onCardNotice(CardNoticeEvent event) async => events.add(event);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final base = File('assets/guard/guard_base.json').readAsBytesSync();

  Future<(IngestWorld, Registry)> open() async {
    final registry = await preloadBundledRegistry();
    final w = await IngestWorld.open();
    addTearDown(w.close);
    return (w, registry);
  }

  Future<(IngestWorld, IngestOutcome?)> ingest(
    String sender,
    String body, {
    CardNoticeHook hook = const NoopCardNoticeHook(),
  }) async {
    final (w, registry) = await open();
    final use = buildIngestRawMessages(
      w.db,
      pipeline: ParsingPipeline(registry),
      guardBase: BytesGuardBase(base),
      newId: w.newId,
      clock: () => DateTime.fromMillisecondsSinceEpoch(_rx, isUtc: true),
      zone: const FixedLocalZone(zoneOffsetMin),
      cardNoticeHook: hook,
      diag: w.diag,
      events: w.bus,
    );
    final result = await use([sms('x', body, source: sender, rx: _rx)]);
    return (w, result.outcomes['x']);
  }

  const cases = {
    'case 7 CIB due': ('CIB', _case7),
    'case 8 CIB statement': ('CIB', _case8),
    'case 12 HSBC statement': ('HSBC', _case12),
  };

  for (final c in cases.entries) {
    test('NEGATIVE PROOF ${c.key}: no transaction, no account, raw parsed, '
        'hook told once', () async {
      final hook = _Recorder();
      final (w, outcome) = await ingest(c.value.$1, c.value.$2, hook: hook);
      expect(outcome, isA<IngestNotice>());
      expect(await w.txns(), isEmpty);
      expect(await w.count('transactions'), 0);
      expect(await w.count('review_items'), 0);
      final raws = await w.raws();
      expect(raws.single['parse_status'], 'parsed');
      expect(hook.events.length, 1);
      expect(hook.events.single.rawId, raws.single['id']);
      expect(hook.events.single.notice.templateId, isNotNull);
    });
  }

  test('NEGATIVE PROOF: the same wording from another known bank (generic '
      'gate) is also never saved', () async {
    for (final body in [_case7, _case8, _case12]) {
      final (w, outcome) = await ingest('NBE', body);
      expect(outcome, isA<IngestNotice>());
      expect(await w.txns(), isEmpty);
    }
  });

  test('the default hook does nothing and the message still stores', () async {
    final (w, outcome) = await ingest('CIB', _case7);
    expect(outcome, isA<IngestNotice>());
    expect(await w.raws(), hasLength(1));
  });

  test('a past-tense CIB card payment still saves as cc_payment', () async {
    final (w, outcome) = await ingest('CIB', _ccPaymentPast);
    expect(outcome, isA<IngestInserted>());
    final t = (await w.txns()).single;
    expect(t['direction'], 'transfer_in');
    expect(t['amount_minor'], 500000);
  });
}
