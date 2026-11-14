// T-046: builds IngestRawMessages over one open database: the Drift store
// port, the accounts repository and T-075's categorizer (a fresh one per
// batch, over the Drift ports), all on the same connection, so their reads and writes run inside the use case's
// write transaction. [store] replaces the Drift store port (it must use the
// same [db]; tests wrap it to inject faults).

import 'package:zaghlol_domain/zaghlol_domain.dart' show DomainEventBus;
import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show Categorizer, ParsingPipeline;

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/accounts_dao.dart';
import '../../../core/db/daos/categories_dao.dart';
import '../../../core/db/daos/merchant_rules_dao.dart';
import '../../accounts/data/drift_accounts_repository.dart';
import '../../categorization/data/categorizer_ports.dart';
import '../../categorization/data/rules_repository.dart';
import '../../transfers/application/suggestion_hook.dart';
import '../application/ingest_raw_messages.dart';
import '../application/ingest_store_port.dart';
import '../domain/ingest_ports.dart';
import 'device_local_zone.dart';
import 'drift_ingest_store.dart';

IngestRawMessages buildIngestRawMessages(
  AppDatabase db, {
  required ParsingPipeline pipeline,
  required GuardConfigSource guardBase,
  required IngestIdGenerator newId,
  IngestClock? clock,
  LocalZone zone = const DeviceLocalZone(),

  /// Replaces the per-batch categorizer (tests).
  CategorizerFactory? categorizerFactory,
  IngestStorePort? store,
  CycleKeyOf? cycleKeyOf,
  List<PostPersistHook> hooks = const [],
  DiagSink diag = const NoDiag(),
  DomainEventBus? events,
}) => IngestRawMessages(
  store: store ?? DriftIngestStore(db),
  pipeline: pipeline,
  guardBase: guardBase,
  accounts: DriftAccountsRepository(
    AccountsDao(db),
    clock: clock,
    newId: newId,
  ),
  newCategorizer:
      categorizerFactory ??
      () async => Categorizer(
        driftCategorizerPorts(
          db,
          DriftRulesRepository(
            MerchantRulesDao(db),
            CategoriesDao(db),
            clock: clock,
            newId: newId,
          ),
        ),
      ),
  newId: newId,
  clock: clock,
  zone: zone,
  cycleKeyOf: cycleKeyOf,
  hooks: [ReimbursementSuggestionHook(db), ...hooks],
  diag: diag,
  events: events,
);
