// WIRE-SVC: the re-parse that follows a saved custom template (T-164 -> T-076).
//
// Review messages from a sender/channel that now has a template are marked
// stale (registry_version 0), then the T-076 job re-parses them with the
// registry plus the saved templates. A re-parse never changes a stored
// amount or status (PO_DECISIONS, T-076): it can only turn a review message
// into a new transaction or fill empty fields. Best effort: every failure is
// swallowed by the caller and no content is logged.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../ingestion/spike_registry.dart' show RegistryGuardBase;
import '../../../ingestion/ulid.dart';
import '../../ingestion/application/reparse.dart';
import '../../ingestion/data/drift_ingest_store.dart';
import '../../ingestion/data/ingest_factory.dart';
import '../../ingestion/data/custom_institutions.dart';
import 'capture_providers.dart' show captureRegistryLoaderProvider;

import 'package:zaghlol_parsing/zaghlol_parsing.dart' show ParsingPipeline;

Future<ReparseSummary?> reparseAfterTemplateSaved(Ref ref) async {
  final base = ref.read(captureRegistryLoaderProvider)();
  final db = await ref.read(appDatabaseProvider.future);
  await db.customStatement(
    'UPDATE raw_messages SET registry_version = 0 '
    "WHERE parse_status = 'review' AND EXISTS ("
    'SELECT 1 FROM custom_templates t '
    'WHERE t.sender = raw_messages.sender '
    'AND t.channel = raw_messages.channel)',
  );
  final registry = await registryWithCustomTemplates(base, db);
  final ids = UlidGenerator();
  final job = ReparseJob(
    store: DriftIngestStore(db),
    ingest: buildIngestRawMessages(
      db,
      pipeline: ParsingPipeline(registry),
      guardBase: RegistryGuardBase(base),
      newId: ids.next,
    ),
    registryVersion: base.registryVersion,
  );
  return job.run();
}
