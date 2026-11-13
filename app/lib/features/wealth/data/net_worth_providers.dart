// T-113: Riverpod wiring for net worth (ADR-001: plain providers).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../ingestion/ulid.dart';
import 'net_worth_repository.dart';
import 'prices_providers.dart';

final netWorthRepositoryProvider = FutureProvider<NetWorthRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final ids = UlidGenerator();
  return NetWorthRepository(
    db: db,
    prices: await ref.watch(pricesRepositoryProvider.future),
    clock: ref.watch(pricesClockProvider),
    newId: ids.next,
  );
}, name: 'netWorthRepositoryProvider');
