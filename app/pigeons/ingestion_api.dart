// Pigeon contract: the headless ingestion engine's control channel (T-041,
// platform-channels.md section 2; replaces the T-008 spike's
// `zaghlol/spike_metrics` command protocol). Android only: the IngestionWorker
// (app.zaghlol.platform.ingest) starts a headless engine at `ingestionMain`,
// waits for `ready`, then sends `drain` cycles and, before it destroys the
// engine, `close`. Regenerate with app/tool/generate_pigeon.sh.
//
// Only counts, an outcome and a code cross this channel; never a body,
// sender, amount or id list.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/ingestion_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/ingest/IngestionApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.ingest',
      errorClassName: 'IngestionApiError',
    ),
    // T-062: the iOS headless engine (App Intents, BGAppRefreshTask) uses the same control channel.
    swiftOut: 'ios/Runner/Platform/IngestionApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'IngestionApiError'),
  ),
)
/// The outcome of one drain cycle (ingestion_cycle.dart `CycleOutcome`).
enum IngestOutcome {
  /// Everything drained was committed and acked (or held), or the spool was
  /// empty, or only stuck entries are left.
  ok,

  /// No database file: the UI engine creates it and drains at start.
  noDatabase,

  /// The database needs the UI engine (migration, create or wipe).
  deferred,

  /// Transient (DB busy or unavailable, ack failed): try again later.
  retry,
}

class IngestCycleReport {
  IngestCycleReport({
    required this.outcome,
    required this.drained,
    required this.inserted,
    required this.stuck,
    required this.held,
    this.code,
  });

  IngestOutcome outcome;
  int drained;
  int inserted;
  int stuck;

  /// Entries handed to holdSpool in this cycle (FU-105).
  int held;

  /// A code (DB_* / PLATFORM_* / CONFIG_INVALID / INGEST_*), never text.
  String? code;
}

/// Native → Dart, headless engine only.
@FlutterApi()
abstract class HeadlessIngestionApi {
  /// Runs one cycle (serialised with any running one).
  @async
  IngestCycleReport drain();

  /// Stop after the current batch, wait for the running cycle, close the
  /// database (awaited). Native destroys the engine only after this answers.
  @async
  void close();
}

/// Dart → native, headless engine only.
@HostApi()
abstract class HeadlessIngestionHostApi {
  /// The HeadlessIngestionApi handler is installed.
  void ready();
}
