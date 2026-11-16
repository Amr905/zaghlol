// SMS-AUTO (PO decision, 2026-11-16): bank SMS are saved without review when
// the sender, amount, currency and direction are clear; suspicious ones go to
// review; messages stored in review by an older build are re-evaluated once
// after the registry version bump. Real bundled registry and Guard base,
// synthetic messages (the PO's two HSBC samples with other digits).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/review_items_dao.dart';
import 'package:zaghlol/features/ingestion/application/ingest_raw_messages.dart';
import 'package:zaghlol/features/ingestion/application/reparse.dart';
import 'package:zaghlol/features/ingestion/data/drift_ingest_store.dart';
import 'package:zaghlol/features/ingestion/domain/body_hash.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_records.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart' show Registry;

import '../features/ingestion/support/ingest_harness.dart';

const String _usd =
    'Your Credit Card ending with * 5075 has been used for USD 114.00 on '
    '09/11/2026 at ANTHROPIC* CLAUDE SUB. Your available limit is '
    'EGP 110095.29';
const String _egp =
    'Your Credit Card ending with * 9375 has been used for EGP 1958.40 on '
    '08/11/2026 at UDEMY SUBSCRIPTION. Your available limit is EGP 27622.16';

final int _rx = DateTime.utc(2026, 11, 10, 10).millisecondsSinceEpoch;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final base = File('assets/guard/guard_base.json').readAsBytesSync();

  Future<(IngestWorld, Registry)> open() async {
    final registry = await preloadBundledRegistry();
    final w = await IngestWorld.open();
    addTearDown(w.close);
    return (w, registry);
  }

  test('the registry version moved past the build that stored the stale '
      'review rows', () async {
    final registry = await preloadBundledRegistry();
    expect(registry.registryVersion, greaterThanOrEqualTo(2));
  });

  test('HSBC rows stored in review by an older build are re-evaluated once: '
      'saved, review items resolved, no duplicates', () async {
    final (w, registry) = await open();
    final store = DriftIngestStore(w.db);
    var n = 0;
    for (final body in [_usd, _egp]) {
      final id = 'raw${n++}';
      await store.insertRaw(
        RawInsert(
          id: id,
          channel: 'sms',
          sender: 'HSBC',
          body: body,
          bodyHash: bodyHashV1(
            senderKey: senderKeyOf('sms', 'HSBC'),
            body: body,
          ),
          receivedAtMs: _rx,
          parseStatus: RawStatus.review,
          registryVersion: 1,
          createdAtMs: _rx,
        ),
      );
      await store.insertReview(
        id: 'rv$id',
        kind: ReviewKind.unrecognized,
        createdAtMs: _rx,
        rawMessageId: id,
        payload: {'reason': 'noTemplate'},
      );
    }
    ReparseJob job() => ReparseJob(
      store: store,
      ingest: w.useCase(registry: registry, guardBase: BytesGuardBase(base)),
      registryVersion: registry.registryVersion,
      diag: w.diag,
    );
    final s = await job().run();
    expect(s.converted, 2);
    final t = await w.txns();
    expect(t.length, 2);
    expect({for (final r in t) r['currency']}, {'USD', 'EGP'});
    expect({for (final r in t) r['amount_minor']}, {11400, 195840});
    expect(await w.count('review_items', 'resolved_at IS NULL'), 0);
    // A second launch changes nothing.
    expect((await job().run()).examined, 0);
    expect(await w.count('transactions'), 2);
  });

  Future<List<Map<String, Object?>>> ingest(String sender, String body) async {
    final (w, registry) = await open();
    final result = await w.useCase(
      registry: registry,
      guardBase: BytesGuardBase(base),
    )([sms('x', body, source: sender, rx: _rx)]);
    return [
      {'o': result.outcomes['x'], 't': await w.txns(), 'r': await w.reviews()},
    ];
  }

  // A known bank, wording no template reads: the generic reader decides.
  test(
    'known bank, clear debit with merchant and last-4: saved, no review',
    () async {
      final o = (await ingest(
        'NBE',
        'Dear customer, EGP 250.00 was debited from your account *4567 at '
            'CARREFOUR MAADI on 09/11/2026',
      )).single;
      expect(o['o'], isA<IngestInserted>());
      final t = (o['t']! as List).single as Map<String, Object?>;
      expect(t['direction'], 'expense');
      expect(t['amount_minor'], 25000);
      expect(t['currency'], 'EGP');
      expect(o['r'], isEmpty);
    },
  );

  test('credit-card settlement (generic cue, EN) is a transfer into the card '
      'account, not income', () async {
    final o = (await ingest(
      'ADIB',
      'We have received your payment of EGP 3,000.00 on your credit card '
          'ending 4321. Thank you',
    )).single;
    expect(o['o'], isA<IngestInserted>());
    final t = (o['t']! as List).single as Map<String, Object?>;
    expect(t['direction'], 'transfer_in');
    expect(t['amount_minor'], 300000);
    expect(t['acc_last4'], '4321');
    expect(o['r'], isEmpty);
  });

  test('credit-card settlement (generic cue, AR) is a transfer in', () async {
    final o = (await ingest(
      'ADIB',
      'تم استلام سداد بمبلغ 3000.00 جم على بطاقتك المنتهية بـ 4321',
    )).single;
    expect(o['o'], isA<IngestInserted>());
    final t = (o['t']! as List).single as Map<String, Object?>;
    expect(t['direction'], 'transfer_in');
    expect(t['amount_minor'], 300000);
  });

  test('HSBC settlement template: transfer in on the card account', () async {
    final o = (await ingest(
      'HSBC',
      'Payment of EGP 5000.00 has been received on your Credit Card ending '
          'with * 5075. Your available limit is EGP 110095.29',
    )).single;
    final t = (o['t']! as List).single as Map<String, Object?>;
    expect(t['direction'], 'transfer_in');
    expect(t['template_id'], 'hsbc.cc_payment.en');
  });

  test(
    'two currencies and no cue (D-28): goes to review, nothing saved',
    () async {
      final o = (await ingest(
        'NBE',
        'Dear customer, your account *4567 was debited at SOME SHOP. '
            'Charges EGP 250.00 and USD 5.00',
      )).single;
      expect(o['o'], isA<IngestReview>());
      expect(o['t'], isEmpty);
    },
  );

  test('no direction cue: review, nothing saved', () async {
    final o = (await ingest(
      'NBE',
      'Dear customer, EGP 250.00 on your account *4567 at SOME SHOP',
    )).single;
    expect(o['o'], isA<IngestReview>());
    expect(o['t'], isEmpty);
    expect(o['r'], hasLength(1));
  });

  test('unknown sender: never saved without review', () async {
    final o = (await ingest(
      'SomeBank',
      'Dear customer, EGP 250.00 was debited from your account *4567 at '
          'SOME SHOP',
    )).single;
    expect(o['t'], isEmpty);
  });
}
