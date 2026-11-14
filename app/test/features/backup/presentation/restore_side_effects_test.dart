// WIRE-SVC item 1: the real restore side effects (pause/resume of sync and
// ingestion, catalog resync) and the restore flow over them.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/presentation/backup_ports.dart';
import 'package:zaghlol/features/backup/presentation/restore_flow.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/catalog_sync/application/sync_providers.dart';

import 'backup_fakes.dart';

void main() {
  late FakeGateway gw;
  late ProviderContainer c;

  setUp(() {
    gw = FakeGateway()..entries = [entry(DateTime.utc(2026, 10, 31))];
    final effects = Provider<RestoreSideEffects>(
      (ref) => DbRestoreSideEffects(
        ref,
        pauseTimeout: const Duration(milliseconds: 30),
      ),
    );
    c = ProviderContainer(
      overrides: [
        backupRestoreGatewayProvider.overrideWithValue(gw),
        restoreSideEffectsProvider.overrideWith((ref) => ref.watch(effects)),
      ],
    );
    addTearDown(c.dispose);
    c.listen(restoreFlowProvider, (_, _) {});
  });

  test('pause closes both gates; resume (in finally) reopens them', () async {
    await c.read(restoreFlowProvider.notifier).search();
    final ingest = c.read(ingestionPauseGateProvider);
    final sync = c.read(syncPauseGateProvider);
    gw.restoreGate = Completer<bool>();
    final done = c.read(restoreFlowProvider.notifier).restore('abcdefghij');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(gw.calls, contains('restore'));
    expect(ingest.paused, isTrue);
    expect(sync.paused, isTrue);
    gw.restoreGate!.complete(true);
    await done;
    expect(ingest.paused, isFalse);
    expect(sync.paused, isFalse);
  });

  test('resume runs in finally even when the restore throws', () async {
    await c.read(restoreFlowProvider.notifier).search();
    gw.restoreError = StateError('boom');
    final ingest = c.read(ingestionPauseGateProvider);
    await c.read(restoreFlowProvider.notifier).restore('abcdefghij');
    expect(ingest.paused, isFalse);
    expect(c.read(syncPauseGateProvider).paused, isFalse);
  });

  test('NEGATIVE: an ingestion cycle writing blocks the restore: the swap '
      'never starts and the gates reopen', () async {
    await c.read(restoreFlowProvider.notifier).search();
    final ingest = c.read(ingestionPauseGateProvider);
    final never = Completer<void>();
    unawaited(ingest.guard(() => never.future));
    await c.read(restoreFlowProvider.notifier).restore('abcdefghij');
    expect(gw.calls, isNot(contains('restore')));
    expect(c.read(restoreFlowProvider).phase, RestorePhase.error);
    expect(ingest.paused, isFalse);
    expect(c.read(syncPauseGateProvider).paused, isFalse);
    never.complete();
  });
}
