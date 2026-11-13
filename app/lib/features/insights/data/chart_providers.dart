// T-105: Riverpod wiring for the chart queries. The repository is rebuilt
// (so its memo is dropped) whenever the cycle data version bumps, which
// the app wiring does after every TransactionsChanged event.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../budget/application/cycle_app_wiring.dart';
import 'chart_repository.dart';

final chartRepositoryProvider = FutureProvider<ChartRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  ref.watch(cycleDataVersionProvider);
  return ChartRepository(db);
}, name: 'chartRepositoryProvider');
