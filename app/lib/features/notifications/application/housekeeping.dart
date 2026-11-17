// FU-253: the jobs that must follow ingestion and run again at start and on
// resume (there is no OS daily job in v1; start and resume are the daily
// trigger): recurring detection, auto-mark, card dues, due reminders, budget
// alerts, and the sweep that frees links pointing at a deleted leg.
//
// Rules: one run at a time (a call during a run is dropped; the next
// trigger picks the change up), at most one run per [minInterval] unless
// forced (so a big inbox scan with many batches runs the jobs once), nothing
// runs while the restore gate is closed, a failing step never stops the
// others, and nothing here deletes a user transaction. Every step is
// idempotent by itself. Nothing here logs.

import '../../../ingestion/ingestion_pause_gate.dart';

/// One named, idempotent job.
typedef HousekeepingStep = ({String name, Future<void> Function() run});

/// What a run did, for tests: step names only.
final class HousekeepingReport {
  const HousekeepingReport({
    this.ran = const [],
    this.failed = const [],
    this.skipped,
  });

  final List<String> ran;
  final List<String> failed;

  /// `busy`, `throttled` or `paused` when nothing ran.
  final String? skipped;
}

final class Housekeeping {
  Housekeeping({
    required this.steps,
    required this.nowMs,
    this.gate,
    this.minInterval = const Duration(seconds: 60),
  });

  final List<HousekeepingStep> steps;
  final int Function() nowMs;
  final IngestionPauseGate? gate;
  final Duration minInterval;

  bool _running = false;
  int? _lastStartMs;

  Future<HousekeepingReport> run({bool force = false}) async {
    if (_running) return const HousekeepingReport(skipped: 'busy');
    if (gate?.paused ?? false) {
      return const HousekeepingReport(skipped: 'paused');
    }
    final now = nowMs();
    final last = _lastStartMs;
    if (!force &&
        last != null &&
        now - last >= 0 &&
        now - last < minInterval.inMilliseconds) {
      return const HousekeepingReport(skipped: 'throttled');
    }
    _running = true;
    _lastStartMs = now;
    final ran = <String>[];
    final failed = <String>[];
    try {
      for (final s in steps) {
        if (gate?.paused ?? false) break; // a restore began: stop between steps
        try {
          final g = gate;
          if (g == null) {
            await s.run();
          } else {
            await g.guard(s.run);
          }
          ran.add(s.name);
        } on Object {
          failed.add(s.name); // the next run tries again
        }
      }
    } finally {
      _running = false;
    }
    return HousekeepingReport(ran: ran, failed: failed);
  }
}
