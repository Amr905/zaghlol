// WIRE-SVC item 1: the real restore side effects (pause/resume of sync and
// ingestion, catalog resync) and the restore flow over them.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/presentation/backup_ports.dart';
import 'package:zaghlol/features/backup/presentation/restore_flow.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/catalog_sync/application/sync_providers.dart';
import 'package:zaghlol/ingestion/native_drain_hold.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show PlatformFailure;

import 'backup_fakes.dart';

/// FU-194: a fake native host. [activePolls] answers of headlessActive are
/// true (a drain in flight) before it reports the drain ended; null = never.
final class FakeDrainHold implements NativeDrainHold {
  final log = <String>[];
  bool held = false;
  int? activePolls = 0;
  Object? holdError;
  void Function()? onHold;

  @override
  Future<bool> hold(Duration ttl) async {
    log.add('hold:${ttl.inMinutes}');
    if (holdError != null) throw holdError!;
    held = true;
    onHold?.call();
    return activePolls != 0;
  }

  @override
  Future<bool> headlessActive() async {
    log.add('active?');
    final n = activePolls;
    if (n == null) return true;
    if (n > 0) activePolls = n - 1;
    return activePolls != 0;
  }

  @override
  Future<void> release() async {
    log.add('release');
    held = false;
  }
}

void main() {
  late FakeGateway gw;
  late ProviderContainer c;
  late FakeDrainHold native;

  setUp(() {
    gw = FakeGateway()..entries = [entry(DateTime.utc(2026, 10, 31))];
    final effects = Provider<RestoreSideEffects>(
      (ref) => DbRestoreSideEffects(
        ref,
        pauseTimeout: const Duration(milliseconds: 30),
        drainPoll: const Duration(milliseconds: 1),
      ),
    );
    native = FakeDrainHold();
    c = ProviderContainer(
      overrides: [
        backupRestoreGatewayProvider.overrideWithValue(gw),
        restoreSideEffectsProvider.overrideWith((ref) => ref.watch(effects)),
        nativeDrainHoldProvider.overrideWithValue(native),
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

  test('FU-194: the native drain is held during the swap and released in '
      'the same finally', () async {
    await c.read(restoreFlowProvider.notifier).search();
    gw.restoreGate = Completer<bool>();
    final done = c.read(restoreFlowProvider.notifier).restore('abcdefghij');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(gw.calls, contains('restore'));
    expect(native.held, isTrue);
    expect(native.log.first, 'hold:10');
    gw.restoreGate!.complete(true);
    await done;
    expect(native.held, isFalse);
    expect(native.log.last, 'release');
  });

  test('FU-194: the hold is released when the restore throws', () async {
    await c.read(restoreFlowProvider.notifier).search();
    gw.restoreError = StateError('boom');
    await c.read(restoreFlowProvider.notifier).restore('abcdefghij');
    expect(gw.calls, contains('restore'));
    expect(native.held, isFalse);
  });

  test('FU-194: a headless drain that ends in time is waited for, then the '
      'swap runs', () async {
    await c.read(restoreFlowProvider.notifier).search();
    native.activePolls = 2;
    native.onHold = () => expect(gw.calls, isNot(contains('restore')));
    await c.read(restoreFlowProvider.notifier).restore('abcdefghij');
    expect(native.log, ['hold:10', 'active?', 'active?', 'release']);
    expect(gw.calls, contains('restore'));
    expect(c.read(restoreFlowProvider).phase, RestorePhase.done);
  });

  test('NEGATIVE (FU-194): a native drain in flight that does not end '
      'blocks the restore: no swap, hold released, gates reopen', () async {
    await c.read(restoreFlowProvider.notifier).search();
    native.activePolls = null;
    await c.read(restoreFlowProvider.notifier).restore('abcdefghij');
    expect(gw.calls, isNot(contains('restore')));
    expect(c.read(restoreFlowProvider).phase, RestorePhase.error);
    expect(native.held, isFalse);
    expect(c.read(ingestionPauseGateProvider).paused, isFalse);
    expect(c.read(syncPauseGateProvider).paused, isFalse);
  });

  test(
    'FU-194: a hold the native side cannot set refuses the restore',
    () async {
      await c.read(restoreFlowProvider.notifier).search();
      native.holdError = DrainHoldException(
        PlatformFailure.fromChannel('IO_ERROR'),
      );
      await c.read(restoreFlowProvider.notifier).restore('abcdefghij');
      expect(gw.calls, isNot(contains('restore')));
      expect(c.read(restoreFlowProvider).phase, RestorePhase.error);
      expect(c.read(ingestionPauseGateProvider).paused, isFalse);
    },
  );

  test('FU-194: the hold is renewed while the restore runs', () async {
    final renewing = ProviderContainer(
      overrides: [
        backupRestoreGatewayProvider.overrideWithValue(gw),
        nativeDrainHoldProvider.overrideWithValue(native),
        restoreSideEffectsProvider.overrideWith(
          (ref) => DbRestoreSideEffects(
            ref,
            holdRenewEvery: const Duration(milliseconds: 5),
          ),
        ),
      ],
    );
    addTearDown(renewing.dispose);
    renewing.listen(restoreFlowProvider, (_, _) {});
    await renewing.read(restoreFlowProvider.notifier).search();
    gw.restoreGate = Completer<bool>();
    final done = renewing
        .read(restoreFlowProvider.notifier)
        .restore('abcdefghij');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final renewals = native.log.where((e) => e == 'hold:10').length;
    expect(renewals, greaterThan(1));
    gw.restoreGate!.complete(true);
    await done;
    final after = native.log.length;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(native.log.length, after, reason: 'no renewal after the release');
    expect(native.held, isFalse);
  });
}
