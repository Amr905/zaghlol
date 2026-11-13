// T-051: Riverpod wiring for the cycle engine. The clock and the zone are
// providers so tests override them; nothing here reads the system clock.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/settings/settings_providers.dart';
import '../../ingestion/data/device_local_zone.dart';
import '../../ingestion/domain/ingest_ports.dart' show LocalZone;
import '../../transactions/data/transactions_providers.dart' show clockProvider;
import '../data/cycle_cache_invalidator.dart';
import '../data/cycle_repository.dart';
import '../data/payday_schedule_store.dart';
import 'cycle_app_wiring.dart';
import 'cycle_overview.dart';

final localZoneProvider = Provider<LocalZone>(
  (ref) => const DeviceLocalZone(),
  name: 'budgetLocalZoneProvider',
);

int Function() _nowUtcMs(Ref ref) {
  final clock = ref.watch(clockProvider);
  return () => clock().toUtc().millisecondsSinceEpoch;
}

final paydayScheduleStoreProvider = FutureProvider<PaydayScheduleStore>((
  ref,
) async {
  final settings = await ref.watch(settingsRepositoryProvider.future);
  final invalidator = await ref.watch(cycleCacheInvalidatorProvider.future);
  return PaydayScheduleStore(
    settings,
    nowUtcMs: _nowUtcMs(ref),
    zone: ref.watch(localZoneProvider),
    invalidateCycles: () async {
      await invalidator.invalidateAll();
    },
  );
});

/// The schedule in force; rebuilds when `payday_day` or `payday_eras` change.
final paydayScheduleProvider = FutureProvider<PaydaySchedule>((ref) async {
  ref.watch(paydayDayProvider);
  ref.watch(paydayErasProvider);
  return (await ref.watch(paydayScheduleStoreProvider.future)).load();
});

final cycleRepositoryProvider = FutureProvider<CycleRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return CycleRepository(
    db,
    nowUtcMs: _nowUtcMs(ref),
    zone: ref.watch(localZoneProvider),
  );
});

final cycleCacheInvalidatorProvider = FutureProvider<CycleCacheInvalidator>(
  (ref) async =>
      CycleCacheInvalidator(await ref.watch(appDatabaseProvider.future)),
);

/// Local "today". A timer re-armed after every firing (Cairo DST moves the
/// local midnight, so a fired timer can still be on the same civil date);
/// the app shell calls [TodayNotifier.reevaluate] on resume.
final todayProvider = NotifierProvider<TodayNotifier, CivilDate>(
  TodayNotifier.new,
  name: 'todayProvider',
);

class TodayNotifier extends Notifier<CivilDate> {
  Timer? _timer;

  int _now() => _nowUtcMs(ref)();

  @override
  CivilDate build() {
    ref.onDispose(() => _timer?.cancel());
    final zone = ref.watch(localZoneProvider);
    final now = _now();
    _arm(now, zone);
    return localToday(now, zone);
  }

  void _arm(int now, LocalZone zone) {
    _timer?.cancel();
    _timer = Timer(
      Duration(
        milliseconds: millisUntilNextLocalMidnight(
          now,
          zone.offsetAtInstant(now),
        ),
      ),
      reevaluate,
    );
  }

  /// Re-reads the clock; rebuilds dependants only when the date changed.
  void reevaluate() {
    final zone = ref.read(localZoneProvider);
    final now = _now();
    final today = localToday(now, zone);
    if (today != state) state = today;
    _arm(now, zone);
  }
}

/// The `TransactionsChanged` stream. The composition root overrides it with
/// `bus.on<TransactionsChanged>()`; the default is the app bus.
final transactionsChangedProvider = Provider<Stream<TransactionsChanged>>(
  (ref) => ref.watch(domainEventBusProvider).on<TransactionsChanged>(),
  name: 'transactionsChangedProvider',
);

/// The current cycle's overview in every currency with activity or a budget.
/// Recomputed when the schedule, the day, the budgets' inputs or a
/// `TransactionsChanged` change.
final currentCycleOverviewProvider = FutureProvider<CycleOverview>((ref) async {
  final schedule = await ref.watch(paydayScheduleProvider.future);
  final repo = await ref.watch(cycleRepositoryProvider.future);
  final today = ref.watch(todayProvider);
  final target = await ref.watch(incomeTargetProvider.future);
  // The app-level wiring (cycle_app_wiring.dart) deletes stale cache rows,
  // then bumps this version.
  ref.watch(cycleDataVersionProvider);
  final cycle = schedule.cycleOn(today);
  return buildCycleOverview(
    cycle: cycle,
    today: today,
    totals: await repo.totals(cycle),
    budgets: await repo.cycleBudgets(),
    incomeTarget: target,
  );
});
