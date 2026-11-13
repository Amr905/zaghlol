// T-048 host benchmark: a 10,000-message inbox through the real scan and
// IngestRawMessages into an encrypted database, first transactions visible
// quickly and the whole scan in under 60 s. Tagged `benchmark` (excluded
// from app-ci's default run). Device numbers: T-173. Synthetic data; the
// output is numbers only.
@Tags(['benchmark'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/capture/application/scan.dart';
import 'package:zaghlol/features/capture/data/scan_sources.dart';
import 'package:zaghlol/features/capture/domain/scan_plan.dart';

import '../../ingestion/support/ingest_harness.dart';
import '../support/capture_fakes.dart';
import '../support/scan_fakes.dart';

void main() {
  test('10k messages: first batch fast, whole scan under 60 s', () async {
    final w = await IngestWorld.open();
    addTearDown(w.close);
    final host = FakeHost();
    const now = t0 + 400 * 86400000;
    host.onQueryInbox = inboxOf([
      for (var i = 1; i <= 10000; i++)
        RawInboxMessage(
          address: 'ZBANK',
          body:
              'ZBANK: Purchase EGP ${i % 900 + 1}.${i % 100} at Synth Shop '
              'card *${4000 + i % 5}',
          dateMs: now - 86400000 + i * 1000,
          providerId: '$i',
        ),
    ]);
    final scanner = InboxScanner(
      host: host,
      senders: DriftScanSenderSource(w.db, () => testRegistry),
      store: UseCaseStore(w.useCase()),
      nowMs: () => now,
    );
    addTearDown(scanner.dispose);
    final watch = Stopwatch()..start();
    int? firstMs;
    final sub = scanner.changes.listen((p) {
      if (p.imported > 0) firstMs ??= watch.elapsedMilliseconds;
    });
    final p = await scanner.run(
      ScanRequest(sinceMs: firstRunSinceMs(nowMs: now, depthMonths: 6)),
    );
    watch.stop();
    await sub.cancel();
    // ignore: avoid_print
    print(
      'scan 10k: ${watch.elapsedMilliseconds} ms, first batch at $firstMs ms',
    );
    expect(p.imported + p.skipped, 10000);
    expect(firstMs, isNotNull);
    expect(firstMs!, lessThan(10000));
    expect(watch.elapsed, lessThan(const Duration(seconds: 60)));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
