import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/ingestion_pause_gate.dart';

void main() {
  test('pause waits for the write in flight, then refuses new ones', () async {
    final g = IngestionPauseGate();
    final release = Completer<void>();
    final write = g.guard(() => release.future);
    var paused = false;
    final p = g.pause().then((_) => paused = true);
    await Future<void>.delayed(Duration.zero);
    expect(paused, isFalse, reason: 'the running write is awaited');
    release.complete();
    await write;
    await p;
    expect(g.paused, isTrue);
    await expectLater(
      g.guard(() async => 1),
      throwsA(
        isA<IngestBatchFailed>().having(
          (e) => e.isTransient,
          'transient',
          true,
        ),
      ),
    );
  });

  test('NEGATIVE: a write that does not finish refuses the pause and '
      'reopens the gate', () async {
    final g = IngestionPauseGate();
    final never = Completer<void>();
    unawaited(g.guard(() => never.future));
    await expectLater(
      g.pause(timeout: const Duration(milliseconds: 20)),
      throwsA(isA<IngestionBusyException>()),
    );
    expect(g.paused, isFalse);
    never.complete();
  });

  test('resume reopens, notifies listeners once, is idempotent', () async {
    final g = IngestionPauseGate();
    var n = 0;
    final remove = g.onResume(() => n++);
    await g.pause();
    g.resume();
    g.resume();
    expect(n, 1);
    expect(await g.guard(() async => 7), 7);
    remove();
    await g.pause();
    g.resume();
    expect(n, 1);
  });

  test('a throwing resume listener does not break resume', () async {
    final g = IngestionPauseGate();
    g.onResume(() => throw StateError('x'));
    await g.pause();
    g.resume();
    expect(g.paused, isFalse);
  });
}
