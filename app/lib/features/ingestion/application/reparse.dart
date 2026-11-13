// T-076: the re-parse job. After an app update ships a newer parsing
// registry, messages the old registry could not turn into transactions
// (review queue), events without a handler (`reparse_pending`) and
// messages parsed by a template that has since changed are parsed again
// through `IngestRawMessages.reparse` (design note in
// docs/04-tasks/tasks/T-076.md).
//
// Safety:
// - one write transaction per message; a message the user or another engine
//   changed meanwhile is skipped (conditional status update), so the job can
//   run next to live capture, the inbox scan and the review screen;
// - nothing is deleted; a user-verified or deleted transaction is never
//   written; amounts, directions, statuses and categories of existing
//   transactions never change;
// - a registry-stamp on every examined row means each start only looks at
//   what is still stale (`reparse_pending` rows are looked at every run);
// - one run at a time per job object; a second `run()` while one is active
//   returns the active run's future.
//
// Privacy: no body, sender, amount or id is logged or put into an error;
// diag codes and counts only.

import '../domain/ingest_ports.dart';
import '../domain/ingest_records.dart';
import '../domain/ingest_types.dart';
import 'ingest_raw_messages.dart';
import 'ingest_store_port.dart';

/// Diag codes of the job (fixed set).
abstract final class ReparseDiag {
  static const String converted = 'REPARSE_CONVERTED';
  static const String updated = 'REPARSE_UPDATED';
  static const String skipped = 'REPARSE_SKIPPED';
  static const String failed = 'REPARSE_FAILED';
  static const String hookFailed = 'REPARSE_HOOK_FAILED';
}

/// Counts of one run. No ids, no text.
final class ReparseSummary {
  const ReparseSummary({
    this.examined = 0,
    this.converted = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.skipped = 0,
    this.failed = 0,
    this.hookFailures = 0,
    this.stopped = false,
  });

  final int examined;
  final int converted;
  final int updated;
  final int unchanged;
  final int skipped;

  /// Messages whose re-parse threw a non-transient failure (left as they
  /// were; tried again on the next start).
  final int failed;

  /// Transfer-pairing calls that threw after the commit (the transaction is
  /// stored; pairing happens on its next trigger).
  final int hookFailures;

  /// True when a transient database failure or the row cap ended the run
  /// early; the remaining rows are picked up on the next start.
  final bool stopped;

  @override
  String toString() =>
      'ReparseSummary(examined: $examined, converted: $converted, '
      'updated: $updated, unchanged: $unchanged, skipped: $skipped, '
      'failed: $failed, hookFailures: $hookFailures, stopped: $stopped)';
}

typedef ReparsePersistedHook = Future<void> Function(String txnId);

final class ReparseJob {
  ReparseJob({
    required this._store,
    required this._ingest,
    required this._registryVersion,
    this._onPersisted,
    this._diag = const NoDiag(),
    this._pageSize = 50,
    this._maxRows = 5000,
  });

  final IngestStorePort _store;
  final IngestRawMessages _ingest;

  /// The version of the registry the app runs with now.
  final int _registryVersion;

  /// T-089 `TransferPairing.onPersisted`: called after the commit for every
  /// transaction a re-parse created or filled (it skips what is not a
  /// posted transfer leg). The job never removes a transaction, so
  /// `onRemoved` has no caller here.
  final ReparsePersistedHook? _onPersisted;
  final DiagSink _diag;
  final int _pageSize;
  final int _maxRows;

  Future<ReparseSummary>? _active;

  /// Runs the job once. Never throws for a single message; a transient
  /// database failure ends the run (`stopped`).
  Future<ReparseSummary> run() => _active ??= _run().whenComplete(() {
    _active = null;
  });

  Future<ReparseSummary> _run() async {
    var examined = 0;
    var converted = 0;
    var updated = 0;
    var unchanged = 0;
    var skipped = 0;
    var failed = 0;
    var hookFailures = 0;
    var stopped = false;
    var after = '';
    paging:
    while (true) {
      final List<StoredRaw> page;
      try {
        page = await _store.rawsToReparse(
          registryVersion: _registryVersion,
          afterId: after,
          limit: _pageSize,
        );
      } on Object {
        stopped = true;
        break;
      }
      if (page.isEmpty) break;
      for (final row in page) {
        after = row.id;
        if (examined >= _maxRows) {
          stopped = true;
          break paging;
        }
        examined++;
        final ReparseResult r;
        try {
          r = await _ingest.reparse(row);
        } on IngestBatchFailed catch (e) {
          if (e.isTransient) {
            stopped = true;
            break paging;
          }
          failed++;
          _diag.count(ReparseDiag.failed, 1);
          continue;
        } on Object {
          failed++;
          _diag.count(ReparseDiag.failed, 1);
          continue;
        }
        switch (r.outcome) {
          case ReparseOutcome.converted:
            converted++;
            _diag.count(ReparseDiag.converted, 1);
          case ReparseOutcome.updated:
            updated++;
            _diag.count(ReparseDiag.updated, 1);
          case ReparseOutcome.unchanged:
            unchanged++;
          case ReparseOutcome.skipped:
            skipped++;
            _diag.count(ReparseDiag.skipped, 1);
        }
        final hook = _onPersisted;
        if (hook != null) {
          for (final id in r.changedTxnIds) {
            try {
              await hook(id);
            } on Object {
              hookFailures++;
              _diag.count(ReparseDiag.hookFailed, 1);
            }
          }
        }
        // Let the UI isolate breathe between messages.
        await Future<void>.delayed(Duration.zero);
      }
      if (page.length < _pageSize) break;
    }
    return ReparseSummary(
      examined: examined,
      converted: converted,
      updated: updated,
      unchanged: unchanged,
      skipped: skipped,
      failed: failed,
      hookFailures: hookFailures,
      stopped: stopped,
    );
  }
}
