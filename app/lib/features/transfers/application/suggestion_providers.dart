// T-092 wiring (WIRE-2): PairSuggestions over the app database, with the
// real payday schedule, clock, ids and event bus.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../budget/application/budget_providers.dart';
import '../../budget/application/cycle_app_wiring.dart'
    show domainEventBusProvider;
import '../../transactions/data/transactions_providers.dart';
import 'suggestions.dart';

final pairSuggestionsProvider = FutureProvider<PairSuggestions>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return PairSuggestions(
    db,
    loadSchedule: () => ref.read(paydayScheduleProvider.future),
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
    events: ref.watch(domainEventBusProvider),
  );
}, name: 'pairSuggestionsProvider');
