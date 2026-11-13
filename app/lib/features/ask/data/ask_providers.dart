// T-110: Riverpod wiring of the Ask Zaghlol engine. Rebuilt with the chart
// repository (so a transaction change drops the memo). The screen is T-111.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../accounts/data/accounts_providers.dart';
import '../../budget/application/budget_providers.dart';
import '../../insights/data/chart_providers.dart';
import '../application/ask_engine.dart';
import 'ask_entities_source.dart';

final askEngineProvider = FutureProvider<AskEngine>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final charts = await ref.watch(chartRepositoryProvider.future);
  final accounts = await ref.watch(accountsRepositoryProvider.future);
  final cycles = await ref.watch(cycleRepositoryProvider.future);
  final schedule = await ref.watch(paydayScheduleProvider.future);
  return AskEngine(
    charts: charts,
    accounts: () => accounts.listWithBalances(includeHidden: true),
    cycleBudgets: cycles.cycleBudgets,
    schedule: () async => schedule,
    entities: () =>
        loadAskEntities(db, () => accounts.list(includeHidden: true)),
    today: () => ref.read(todayProvider),
  );
}, name: 'askEngineProvider');
