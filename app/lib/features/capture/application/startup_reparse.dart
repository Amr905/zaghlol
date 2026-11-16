// SMS-device: the re-parse after a registry version bump (T-076) was only
// ever started after a custom template was saved (custom_template_reparse),
// never at app start. A phone that stored bank SMS in review under an older
// build (registry version 1) kept them there for good: body-hash dedupe
// stops the same text from being read again, and nothing re-evaluated the
// stored row. This runs the job once per app start; each examined row is
// stamped with the current version, so a later start finds nothing to do.
// Best effort; nothing here logs.

import '../../../core/db/app_database.dart';
import '../../../ingestion/spike_registry.dart' show RegistryGuardBase;
import '../../../ingestion/ulid.dart';
import '../../ingestion/application/reparse.dart';
import '../../ingestion/data/custom_institutions.dart';
import '../../ingestion/data/drift_ingest_store.dart';
import '../../ingestion/data/ingest_factory.dart';

import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show ParsingPipeline, Registry;

/// Re-parses stale review / pending rows under [registry] (plus the user's
/// custom templates). Returns null when it could not start.
Future<ReparseSummary?> reparseOnStart(
  AppDatabase db,
  Registry registry,
) async {
  try {
    final withTemplates = await registryWithCustomTemplates(registry, db);
    final ids = UlidGenerator();
    final job = ReparseJob(
      store: DriftIngestStore(db),
      ingest: buildIngestRawMessages(
        db,
        pipeline: ParsingPipeline(withTemplates),
        guardBase: RegistryGuardBase(registry),
        newId: ids.next,
      ),
      registryVersion: registry.registryVersion,
    );
    return await job.run();
  } on Object {
    return null;
  }
}
