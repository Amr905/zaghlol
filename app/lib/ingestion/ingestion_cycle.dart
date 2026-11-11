// T-008 (SPK-01): one drain cycle, shared by the headless engine
// (ingestion_main.dart) and the devSms UI engine (spike_foreground.dart).
//
// Order per batch: drain → parse → one DB transaction → ack. The ack is sent
// only after the commit returned; a commit failure or a crash before the ack
// re-delivers the entries and the unique body_hash absorbs the duplicate
// (BR-ING-02). Nothing here logs, prints or puts message text in an error.

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../core/platform/capture_api.g.dart';
import 'ingest_store.dart';
import 'ingestion_config.dart';
import 'raw_message_mapper.dart';
import 'spool_port.dart';
import 'ulid.dart';

/// Mirrors the native `CycleOutcome` (DrainLoop.kt); sent by name.
enum CycleOutcome {
  /// Everything drained was committed and acked (or nothing was pending).
  ok,

  /// No database file: keep the spool; the UI engine creates the database.
  noDatabase,

  /// The database needs the UI engine (migration, create or wipe).
  deferred,

  /// Transient: DB unavailable, commit or ack failed. Nothing was acked
  /// that was not committed.
  retry;

  String get wire => switch (this) {
    ok => 'OK',
    noDatabase => 'NO_DATABASE',
    deferred => 'DEFERRED',
    retry => 'RETRY',
  };
}

final class CycleResult {
  const CycleResult(
    this.outcome, {
    this.drained = 0,
    this.inserted = 0,
    this.code,
  });

  final CycleOutcome outcome;
  final int drained;
  final int inserted;

  /// A code (DB_* / PLATFORM_*) for a non-ok outcome; never message text.
  final String? code;

  Map<String, Object?> toWire() => {
    'result': outcome.wire,
    'drained': drained,
    'inserted': inserted,
    'code': code,
  };
}

/// Stage marks for the spike metrics (ULIDs only).
abstract interface class CycleMarks {
  void dbOpen();
  void mark(String stage, List<String> ids);
}

final class NoMarks implements CycleMarks {
  const NoMarks();
  @override
  void dbOpen() {}
  @override
  void mark(String stage, List<String> ids) {}
}

/// The parser once per engine (registry load timed by the caller).
typedef EntryParser = ParseResult? Function(SpoolEntry entry);

final class IngestionCycle {
  IngestionCycle({
    required this.spool,
    required this.store,
    required this.parse,
    required this.registryVersion,
    this.marks = const NoMarks(),
    UlidGenerator? ids,
    int Function()? nowMs,
    this.batchSize = kDrainBatchSize,
    this.budget = kCycleBudget,
  }) : _ids = ids ?? UlidGenerator(),
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SpoolPort spool;
  final IngestStore store;
  final EntryParser parse;
  final int registryVersion;
  final CycleMarks marks;
  final int batchSize;
  final Duration budget;
  final UlidGenerator _ids;
  final int Function() _nowMs;

  /// Codes that mean "the UI engine must do it" (not a transient failure).
  static const Set<String> deferCodes = {
    'DB_MIGRATION_PENDING',
    'DB_DEFERRED',
    'DB_SCHEMA_TOO_NEW',
  };

  Future<CycleResult> run() async {
    if (!await store.databaseExists()) {
      return const CycleResult(CycleOutcome.noDatabase);
    }
    try {
      await store.open();
    } on IngestStoreUnavailable catch (e) {
      return CycleResult(
        deferCodes.contains(e.code)
            ? CycleOutcome.deferred
            : CycleOutcome.retry,
        code: e.code,
      );
    }
    marks.dbOpen();
    final start = _nowMs();
    var drained = 0;
    var inserted = 0;
    while (_nowMs() - start < budget.inMilliseconds) {
      final List<SpoolEntry> entries;
      try {
        entries = await spool.drain(batchSize);
      } on SpoolPortException catch (e) {
        return CycleResult(
          CycleOutcome.retry,
          drained: drained,
          inserted: inserted,
          code: e.code,
        );
      }
      if (entries.isEmpty) break;
      drained += entries.length;
      final ids = [for (final e in entries) e.id];

      final mapped = <MappedEntry>[];
      for (final e in entries) {
        ParseResult? result;
        try {
          result = parse(e);
        } on Object {
          result = null; // stored for review; the parser never sees it twice
        }
        mapped.add(
          mapEntry(
            entry: e,
            result: result,
            registryVersion: registryVersion,
            rowId: _ids.next(),
            nowMs: _nowMs(),
          ),
        );
      }
      marks.mark('parsed', ids);

      try {
        inserted += await store.commit([...mapped.whereType<StoreRow>()]);
      } on Object {
        return CycleResult(
          CycleOutcome.retry,
          drained: drained,
          inserted: inserted,
          code: 'DB_WRITE_FAILED',
        );
      }
      marks.mark('commit', ids);

      try {
        await spool.ack(ids);
      } on SpoolPortException catch (e) {
        // Committed but not acked: re-delivered later, deduped by body_hash.
        return CycleResult(
          CycleOutcome.retry,
          drained: drained,
          inserted: inserted,
          code: e.code,
        );
      }
    }
    return CycleResult(CycleOutcome.ok, drained: drained, inserted: inserted);
  }
}

/// [EntryParser] over the T-033 pipeline. A body over maxParseBodyLength or
/// an unknown channel is not parsed (the row goes to review).
EntryParser pipelineParser(ParsingPipeline pipeline) => (entry) {
  final channel = registryChannelOf(entry.channel);
  if (channel == null) return null;
  return pipeline.parse(
    ParseRequest(
      body: entry.body,
      source: entry.source,
      channel: channel,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        entry.receivedAtMs,
        isUtc: true,
      ),
    ),
  );
};
