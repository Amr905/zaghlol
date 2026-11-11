// T-008 (SPK-01): one drain cycle, shared by the headless engine
// (ingestion_main.dart) and the devSms UI engine (spike_foreground.dart).
//
// Order per batch: drain → IngestRawMessages (parse, then one DB write
// transaction) → ack. The ack is sent only after the use case returned (its
// transaction committed); a failed batch or a crash before the ack
// re-delivers the entries and `body_hash` absorbs the duplicate
// (BR-ING-02). T-046: stuck entries (design note §10, platform-channels §2)
// and the 5 s minimum budget per batch. Nothing here logs, prints or puts
// message text in an error.

import '../core/platform/capture_api.g.dart';
import '../features/ingestion/domain/ingest_types.dart';
import 'ingest_store.dart';
import 'ingestion_config.dart';
import 'spool_port.dart';

/// Mirrors the native `CycleOutcome` (DrainLoop.kt); sent by name.
enum CycleOutcome {
  /// Everything drained was committed and acked (or nothing was pending, or
  /// only stuck entries are left).
  ok,

  /// No database file: keep the spool; the UI engine creates the database.
  noDatabase,

  /// The database needs the UI engine (migration, create or wipe).
  deferred,

  /// Transient: DB unavailable or busy, ack failed. Nothing was acked that
  /// was not committed.
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
    this.stuck = 0,
    this.code,
  });

  final CycleOutcome outcome;
  final int drained;

  /// Messages stored (new transactions, merges, review items, balances,
  /// deferred rows); duplicates and drops are not counted.
  final int inserted;

  /// Entries a drain returned again after their batch failed in this cycle
  /// (left in the spool; the native worker does not re-enqueue for them).
  final int stuck;

  /// A code (DB_* / PLATFORM_* / CONFIG_INVALID / INGEST_*) for a non-ok
  /// outcome or a failed batch; never message text.
  final String? code;

  Map<String, Object?> toWire() => {
    'result': outcome.wire,
    'drained': drained,
    'inserted': inserted,
    'stuck': stuck,
    'code': code,
  };
}

/// Stage marks for the spike metrics (ids only).
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

/// No batch starts with less than this left of the cycle budget (design
/// note §13), so the native drain bound is never hit mid-transaction.
const Duration kMinBatchBudget = Duration(seconds: 5);

final class IngestionCycle {
  IngestionCycle({
    required this.spool,
    required this.store,
    required this.mayCreateDatabase,
    this.marks = const NoMarks(),
    int Function()? nowMs,
    this.batchSize = kDrainBatchSize,
    this.budget = kCycleBudget,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SpoolPort spool;
  final IngestStore store;

  /// True only in the UI engine: a missing database is opened (created) like
  /// the app's startup does. False in the headless engine (Q6): a missing
  /// database is [CycleOutcome.noDatabase] and is never opened.
  final bool mayCreateDatabase;
  final CycleMarks marks;
  final int batchSize;
  final Duration budget;
  final int Function() _nowMs;

  /// Codes that mean "the UI engine must do it" (not a transient failure).
  static const Set<String> deferCodes = {
    'DB_MIGRATION_PENDING',
    'DB_DEFERRED',
    'DB_SCHEMA_TOO_NEW',
  };

  Future<CycleResult> run() async {
    if (!mayCreateDatabase && !await store.databaseExists()) {
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
    final lastStart = budget.inMilliseconds - kMinBatchBudget.inMilliseconds;
    final seen = <String>{};
    var drained = 0;
    var inserted = 0;
    var stuck = 0;
    String? failedCode;
    while (_nowMs() - start < lastStart) {
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
      final ids = [for (final e in entries) e.id];
      if (ids.every(seen.contains)) {
        // Only entries whose batch already failed in this cycle: stop
        // (they stay in the spool; never deleted).
        stuck = ids.length;
        break;
      }
      seen.addAll(ids);
      drained += entries.length;

      final IngestBatchResult result;
      try {
        result = await store.ingest([
          for (final e in entries)
            IncomingMessage(
              deliveryId: e.id,
              channel: e.channel,
              source: e.source,
              body: e.body,
              receivedAtMs: e.receivedAtMs,
              simSlot: e.simSlot,
              origin: MessageOrigin.spool,
            ),
        ]);
      } on IngestBatchFailed catch (e) {
        if (e.isTransient) {
          // Busy / I/O: nothing committed, nothing acked; the worker retries.
          return CycleResult(
            CycleOutcome.retry,
            drained: drained,
            inserted: inserted,
            code: e.code,
          );
        }
        // Not transient and not isolatable (CONFIG_INVALID, an oversized
        // batch): keep the entries, go on; the next drain returns them again
        // and the cycle ends with them as stuck. (A poison message no longer
        // gets here: the use case retries the batch one message at a time
        // and stores a failing one for review, CR-1/F2.)
        failedCode = e.code;
        continue;
      } on IngestStoreUnavailable catch (e) {
        return CycleResult(
          CycleOutcome.retry,
          drained: drained,
          inserted: inserted,
          code: e.code,
        );
      } on Object {
        return CycleResult(
          CycleOutcome.retry,
          drained: drained,
          inserted: inserted,
          code: 'DB_WRITE_FAILED',
        );
      }
      if (result.kept.isNotEmpty) {
        // Could not be stored even alone: left in the spool (not acked);
        // a later drain that returns only these ends the cycle as stuck.
        failedCode = IngestBatchFailed.unstorable;
      }
      marks.mark('commit', ids);
      inserted += result.outcomes.values
          .where((o) => o is! IngestDuplicate && o is! IngestDropped)
          .length;

      try {
        await spool.ack(result.ackable);
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
    return CycleResult(
      CycleOutcome.ok,
      drained: drained,
      inserted: inserted,
      stuck: stuck,
      code: failedCode,
    );
  }
}
