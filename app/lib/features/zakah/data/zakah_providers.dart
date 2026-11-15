// T-168: Riverpod wiring for Zakah (ADR-001: plain providers). Widgets read
// these; they never touch the database.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database_providers.dart';
import '../../wealth/data/prices_providers.dart';
import 'zakah_repository.dart';

/// Zakah amounts' "cost" column is in EGP (A-58).
final Currency zakahCostCurrency = Currency.of('EGP');

final zakahRepositoryProvider = FutureProvider<ZakahRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return ZakahRepository(
    db: db,
    prices: await ref.watch(pricesRepositoryProvider.future),
    clock: ref.watch(pricesClockProvider),
    costCurrency: zakahCostCurrency,
  );
}, name: 'zakahRepositoryProvider');

final zakahViewProvider = FutureProvider<ZakahView>((ref) async {
  final repo = await ref.watch(zakahRepositoryProvider.future);
  return repo.compute();
}, name: 'zakahViewProvider');
