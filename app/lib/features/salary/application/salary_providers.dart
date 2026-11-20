// T-195: Riverpod access to the salary service and the expected item.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../budget/application/budget_providers.dart';
import '../../budget/application/cycle_app_wiring.dart'
    show domainEventBusProvider;
import '../../transactions/data/transactions_providers.dart';
import 'salary_matching.dart';
import 'salary_service.dart';

final salaryPlanProvider = settingProvider<SalaryPlan?>(Settings.salaryPlan);
final salaryStateProvider = settingProvider<SalaryState>(Settings.salaryState);

// Declared types: housekeeping (reached from the transactions repository
// provider) reads these, which would otherwise be a cycle for inference.
final FutureProvider<SalaryMatching> salaryMatchingProvider =
    FutureProvider<SalaryMatching>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      return SalaryMatching(
        db,
        loadSchedule: () => ref.read(paydayScheduleProvider.future),
        clock: ref.watch(clockProvider),
        events: ref.watch(domainEventBusProvider),
      );
    }, name: 'salaryMatchingProvider');

final FutureProvider<SalaryService> salaryServiceProvider =
    FutureProvider<SalaryService>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final repo = await ref.watch(transactionRepositoryProvider.future);
      return SalaryService(
        db,
        repo,
        zone: ref.watch(localZoneProvider),
        clock: ref.watch(clockProvider),
      );
    }, name: 'salaryServiceProvider');

/// The expected salary on Home: recomputed when the plan, the state, today or
/// any transaction changes. Null: nothing to show.
final expectedSalaryProvider = FutureProvider<ExpectedSalary?>((ref) async {
  ref.watch(salaryPlanProvider);
  ref.watch(salaryStateProvider);
  final today = ref.watch(todayProvider);
  final sub = ref
      .watch(transactionsChangedProvider)
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(() => unawaited(sub.cancel()));
  final service = await ref.watch(salaryServiceProvider.future);
  return service.expected(today);
}, name: 'expectedSalaryProvider');
