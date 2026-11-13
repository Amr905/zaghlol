// T-052 (FU-110): app-level wiring of the cycle cache. One place deletes the
// stale `cycle_summaries` rows and then bumps [cycleDataVersionProvider], so
// readers recompute only after the delete (no race between two listeners).
// The app shell watches [cycleAppWiringProvider] once and calls
// [CycleResumeHandler.onResume] when the app returns to the foreground.
// Nothing here logs.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/settings/settings_providers.dart';
import '../../transactions/data/transactions_providers.dart' show clockProvider;
import 'budget_providers.dart';

/// The in-process event bus. The composition root may override it with the
/// bus its ingest engine publishes on.
final domainEventBusProvider = Provider<DomainEventBus>((ref) {
  final bus = DomainEventBus();
  ref.onDispose(() => unawaited(bus.dispose()));
  return bus;
}, name: 'domainEventBusProvider');

/// Bumped after the cache was changed; readers watch it to recompute.
final cycleDataVersionProvider = NotifierProvider<CycleDataVersion, int>(
  CycleDataVersion.new,
  name: 'cycleDataVersionProvider',
);

class CycleDataVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Watch once from the app shell: keeps the cache consistent with the
/// events and the settings for the life of the container.
final cycleAppWiringProvider = FutureProvider<void>((ref) async {
  final invalidator = await ref.watch(cycleCacheInvalidatorProvider.future);
  final version = ref.read(cycleDataVersionProvider.notifier);

  final sub = ref.watch(transactionsChangedProvider).listen((e) async {
    await invalidator.onTransactionsChanged(e);
    version.bump();
  });
  ref.onDispose(() => unawaited(sub.cancel()));

  // A primary-currency change drops every row (design note §6).
  ref.listen(primaryCurrencyProvider, (prev, next) async {
    if (prev?.value != null && prev?.value != next.value) {
      await invalidator.invalidateAll();
      version.bump();
    }
  });
}, name: 'cycleAppWiringProvider');

final cycleResumeHandlerProvider = Provider<CycleResumeHandler>(
  CycleResumeHandler.new,
  name: 'cycleResumeHandlerProvider',
);

class CycleResumeHandler {
  CycleResumeHandler(this._ref);

  final Ref _ref;
  int? _lastForegroundMs;

  /// App resume: re-reads the local day, then drops every cycle touched
  /// since the last foreground (the headless engine's writes, edits, links)
  /// and tells readers to recompute. The first call of a process has no
  /// previous foreground time and sweeps from 0 (correct, not cached).
  Future<void> onResume() async {
    _ref.read(todayProvider.notifier).reevaluate();
    final now = _ref.read(clockProvider)().toUtc().millisecondsSinceEpoch;
    final since = _lastForegroundMs ?? 0;
    final invalidator = await _ref.read(cycleCacheInvalidatorProvider.future);
    final schedule = await _ref.read(paydayScheduleProvider.future);
    await invalidator.sweepSince(since, schedule);
    _lastForegroundMs = now;
    _ref.read(cycleDataVersionProvider.notifier).bump();
  }
}
