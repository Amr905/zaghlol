// T-075: Riverpod wiring (ADR-001) for the categorizer.
//
// Public API for the ingest use case (T-046):
//
//   final c = await ref.read(categorizerProvider.future); // one per run
//   final d = await c.categorize(categorizeInputFor(
//     merchantRaw: raw, merchantNorm: key,
//     counterpartyKind: kind, counterpartyValue: value));
//   // d.categoryId, d.catalogMerchantId, d.source.code, d.ruleId
//
// Create one [Categorizer] per batch/run (keywords are loaded once per
// instance; with `memoize` each distinct input is decided once). A port
// failure throws a code-only exception: do not treat it as "no category".

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/app_database_providers.dart';
import 'categorizer_ports.dart';
import 'recategorizer.dart';
import 'rules_providers.dart';

/// A fresh categorizer (not memoized; for one message or a short batch).
final categorizerProvider = FutureProvider<Categorizer>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final rules = await ref.watch(rulesRepositoryProvider.future);
  return Categorizer(driftCategorizerPorts(db, rules));
}, name: 'categorizerProvider');

/// A memoizing categorizer for backfills (apply-to-past, catalog update,
/// re-parse): each distinct merchant is decided once.
final backfillCategorizerProvider = FutureProvider<Categorizer>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final rules = await ref.watch(rulesRepositoryProvider.future);
  return Categorizer(driftCategorizerPorts(db, rules), memoize: true);
}, name: 'backfillCategorizerProvider');

final recategorizerProvider = FutureProvider<Recategorizer>((ref) async {
  return Recategorizer(await ref.watch(appDatabaseProvider.future));
}, name: 'recategorizerProvider');
