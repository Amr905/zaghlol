// SMS-device: stale review rows (stored under registry version 1) are read
// again at app start. Fails without the start-up job: nothing but a saved
// custom template ever ran the re-parse, so the PO's phone kept its review
// rows and "HSBC is still not read".
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/review_items_dao.dart';
import 'package:zaghlol/features/capture/application/startup_reparse.dart';
import 'package:zaghlol/features/ingestion/application/ingest_raw_messages.dart';
import 'package:zaghlol/features/ingestion/data/drift_ingest_store.dart';
import 'package:zaghlol/features/ingestion/domain/body_hash.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_records.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';

import '../../ingestion/support/ingest_harness.dart';

const String _usd =
    'Your Credit Card ending with * 5076 has been used for USD 115.00 on '
    '09/11/2026 at ANTHROPIC* CLAUDE SUB. Your available limit is '
    'EGP 110096.30';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'review rows of an older registry become transactions once, at start',
    () async {
      final registry = await preloadBundledRegistry();
      final w = await IngestWorld.open();
      addTearDown(w.close);
      final store = DriftIngestStore(w.db);
      final rx = DateTime.utc(2026, 11, 10, 10).millisecondsSinceEpoch;
      await store.insertRaw(
        RawInsert(
          id: 'raw0',
          channel: 'sms',
          sender: 'HSBC',
          body: _usd,
          bodyHash: bodyHashV1(
            senderKey: senderKeyOf('sms', 'HSBC'),
            body: _usd,
          ),
          receivedAtMs: rx,
          parseStatus: RawStatus.review,
          registryVersion: 1,
          createdAtMs: rx,
        ),
      );
      await store.insertReview(
        id: 'rvraw0',
        kind: ReviewKind.unrecognized,
        createdAtMs: rx,
        rawMessageId: 'raw0',
        payload: {'reason': 'noTemplate'},
      );

      final first = await reparseOnStart(w.db, registry);
      expect(first, isNotNull);
      expect(first!.converted, 1);
      expect(await w.count('transactions'), 1);
      expect(await w.count('review_items', 'resolved_at IS NULL'), 0);

      // The next start finds nothing to do and adds nothing.
      final second = await reparseOnStart(w.db, registry);
      expect(second!.examined, 0);
      expect(await w.count('transactions'), 1);
    },
  );
}
