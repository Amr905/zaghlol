// T-008: cycles are serialised per engine; a request during a run schedules
// exactly one more run. The foreground spike starts only in devSms.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';
import 'package:zaghlol/ingestion/spike_foreground.dart';
import 'package:zaghlol/ingestion/spike_ingestion.dart';

import 'ingestion_fakes.dart';

final class GatedStore extends FakeStore {
  GatedStore(super.log);

  Completer<void>? gate;

  @override
  Future<bool> databaseExists() async {
    await gate?.future;
    return super.databaseExists();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a drain during a run joins it and triggers one more run', () async {
    final log = <String>[];
    final store = GatedStore(log)..gate = Completer<void>();
    final ingestion = SpikeIngestion(
      marks: RecordingMarks(log),
      headless: true,
      spool: FakeSpool([], log),
      store: (_) => store,
      dbDirectory: () async => Directory.systemTemp,
    );
    final first = ingestion.drain();
    final second = ingestion.drain();
    final third = ingestion.drain();
    store.gate!.complete();
    store.gate = null;
    final results = await Future.wait([first, second, third]);
    expect(results.every((r) => r.outcome == CycleOutcome.ok), isTrue);
    expect(log.where((l) => l == 'exists'), hasLength(2));
  });

  test('setup failure is a code-only retry', () async {
    final ingestion = SpikeIngestion(
      marks: const NoMarks(),
      headless: true,
      spool: FakeSpool([], []),
      dbDirectory: () async => throw StateError(canary),
    );
    final r = await ingestion.drain();
    expect(r.outcome, CycleOutcome.retry);
    expect(r.code, 'INGEST_SETUP_FAILED');
  });

  test('foreground spike: off unless the flavour is devSms', () {
    expect(startSpikeForeground(flavor: null), isNull);
    expect(startSpikeForeground(flavor: 'devNoSms'), isNull);
    expect(startSpikeForeground(flavor: 'prodSms'), isNull);
    final started = startSpikeForeground(flavor: 'devSms');
    addTearDown(() => CaptureEventsApi.setUp(null));
    expect(started, isNotNull);
  });
}
