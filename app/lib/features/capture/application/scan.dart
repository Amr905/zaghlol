// T-048: the historical inbox scan (Android, UI engine only). It pages
// `queryInbox` (T-042, sender-filtered in SQL, Guard run natively), turns
// each page into IncomingMessage rows with origin `inboxScan` and ingests
// them in small transactions through the same IngestStore / IngestRawMessages
// as the spool (T-041, T-046): dedupe is `body_hash`, so a message found by
// live capture and by the scan is stored once, and a re-run adds nothing.
//
// One scan at a time (a second request joins the running one). The scan
// restarts when native answers INVALID_ARGUMENT (the allowlist changed
// between pages, FU-109). Nothing here logs, and no progress value or error
// carries a body, an address or an amount: counts and codes only.

import 'dart:async';

import '../../../core/platform/capture_api.g.dart';
import '../../../ingestion/ingest_store.dart';
import '../../ingestion/domain/ingest_types.dart';
import '../data/capture_host_port.dart';
import '../domain/scan_plan.dart';

/// Where the scan gets its candidate senders (registry exact senders and the
/// user's SMS senders), already classified.
abstract interface class ScanSenderSource {
  Future<List<ScanSender>> read();
}

/// What to scan.
final class ScanRequest {
  const ScanRequest({
    required this.sinceMs,
    this.includePersonal = false,
    this.onlyInstitutions,
  });

  /// Lower bound (epoch ms) for registry and non-phone user senders.
  final int sinceMs;

  /// FU-109 M-1: also the user-added phone-number senders, from
  /// `max(sinceMs, now - 3 months)`.
  final bool includePersonal;

  /// FR-CAP-07: only the registry senders of these institutions (a re-scan
  /// for one card's institution); no user senders then.
  final Set<String>? onlyInstitutions;
}

final class InboxScanner {
  InboxScanner({
    required this.host,
    required this.senders,
    required this.store,
    int Function()? nowMs,
    this.ioRetries = 2,
    this.writeRetries = 3,
  }) : _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final CaptureHostPort host;
  final ScanSenderSource senders;
  final IngestStore store;
  final int Function() _nowMs;

  /// Extra tries of a page after `IO_ERROR`.
  final int ioRetries;

  /// Extra tries of a batch after a transient write failure.
  final int writeRetries;

  final StreamController<ScanProgress> _changes =
      StreamController<ScanProgress>.broadcast();
  ScanProgress _progress = ScanProgress.initial;
  Future<ScanProgress>? _running;
  bool _cancel = false;

  ScanProgress get progress => _progress;
  Stream<ScanProgress> get changes => _changes.stream;
  bool get isRunning => _running != null;

  /// Starts a scan, or joins the running one (its request wins).
  Future<ScanProgress> run(ScanRequest request) {
    final running = _running;
    if (running != null) return running;
    _cancel = false;
    final next = _scan(request).whenComplete(() => _running = null);
    _running = next;
    return next;
  }

  /// Stops after the current batch; the scan ends as cancelled.
  void cancel() => _cancel = true;

  Future<void> dispose() => _changes.close();

  void _set(ScanProgress p) {
    _progress = p;
    if (!_changes.isClosed) _changes.add(p);
  }

  Future<ScanProgress> _scan(ScanRequest req) async {
    _set(const ScanProgress(phase: ScanPhase.running));
    final found = <String>{};
    try {
      await store.open();
    } on IngestStoreUnavailable catch (e) {
      return _fail(e.code);
    } on Object {
      return _fail('INGEST_SETUP_FAILED');
    }
    try {
      var restarts = 0;
      while (true) {
        try {
          await _pass(req, found);
          break;
        } on CaptureHostException catch (e) {
          if (e.platformCode == 'INVALID_ARGUMENT' &&
              restarts < kMaxScanRestarts) {
            restarts++;
            _set(_progress.copyWith(restarts: restarts));
            continue;
          }
          return _fail(e.platformCode);
        }
      }
    } on _Stop catch (s) {
      return s.cancelled
          ? _finish(ScanPhase.cancelled)
          : _fail(s.code ?? 'SCAN_INTERNAL');
    } on IngestBatchFailed catch (e) {
      return _fail(e.code);
    } on IngestStoreUnavailable catch (e) {
      return _fail(e.code);
    } on Object {
      return _fail('SCAN_INTERNAL');
    }
    return _finish(ScanPhase.done);
  }

  ScanProgress _finish(ScanPhase phase) {
    final p = _progress.copyWith(phase: phase);
    _set(p);
    return p;
  }

  ScanProgress _fail(String code) {
    final p = _progress.copyWith(phase: ScanPhase.failed, code: code);
    _set(p);
    return p;
  }

  /// One pass over the current sender list. Throws [CaptureHostException]
  /// (INVALID_ARGUMENT restarts the pass), [IngestBatchFailed] or [_Stop].
  Future<void> _pass(ScanRequest req, Set<String> found) async {
    final all = await senders.read();
    final only = req.onlyInstitutions;
    final candidates = only == null
        ? all
        : [
            for (final s in all)
              if (s.kind == ScanSenderKind.registry &&
                  only.contains(s.institutionCode))
                s,
          ];
    final set = ScanSenderSet.build(
      candidates,
      includePersonal: req.includePersonal,
    );
    if (set.isEmpty) return;
    final now = _nowMs();
    final institutionOf = <String, String>{
      for (final s in set.full)
        if (s.institutionCode != null)
          s.address.toLowerCase(): s.institutionCode!,
    };
    final personalAddresses = {
      for (final s in set.personal) s.address.toLowerCase(),
    };
    final groups = <(List<String>, int)>[
      ([for (final s in set.full) s.address], req.sinceMs),
      (
        [for (final s in set.personal) s.address],
        personalSinceMs(nowMs: now, sinceMs: req.sinceMs),
      ),
    ];
    var first = _progress.scanned == 0;
    for (final (addresses, since) in groups) {
      for (final chunk in chunkAddresses(addresses)) {
        String? cursor;
        while (true) {
          if (_cancel) throw const _Stop.cancelled();
          final page = await _queryWithRetry(
            InboxQuery(
              sinceEpochMs: since,
              senderAddresses: chunk,
              afterCursor: cursor,
              pageSize: first ? kFirstPageSize : kPageSize,
            ),
          );
          first = false;
          _set(
            _progress.copyWith(scanned: _progress.scanned + page.scannedTotal),
          );
          await _ingestPage(
            page.items,
            institutionOf,
            personalAddresses,
            found,
          );
          cursor = page.nextCursor;
          if (cursor == null) break;
          // Let the UI isolate draw between pages.
          await Future<void>.delayed(Duration.zero);
        }
      }
    }
  }

  Future<InboxPage> _queryWithRetry(InboxQuery q) async {
    var attempt = 0;
    while (true) {
      try {
        return await host.queryInbox(q);
      } on CaptureHostException catch (e) {
        if (e.platformCode == 'IO_ERROR' && attempt < ioRetries) {
          attempt++;
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _ingestPage(
    List<RawInboxMessage> items,
    Map<String, String> institutionOf,
    Set<String> personalAddresses,
    Set<String> found,
  ) async {
    for (var i = 0; i < items.length; i += kIngestBatchSize) {
      if (_cancel) throw const _Stop.cancelled();
      final end = i + kIngestBatchSize > items.length
          ? items.length
          : i + kIngestBatchSize;
      final slice = items.sublist(i, end);
      final batch = [
        for (final m in slice)
          IncomingMessage(
            deliveryId: m.providerId,
            channel: 'sms',
            source: m.address,
            body: m.body,
            receivedAtMs: m.dateMs,
            simSlot: m.simSlot,
            origin: personalAddresses.contains(m.address.toLowerCase())
                ? MessageOrigin.inboxScanPersonal
                : MessageOrigin.inboxScan,
          ),
      ];
      final result = await _ingestWithRetry(batch);
      var imported = 0;
      var skipped = 0;
      for (final m in slice) {
        final o = result.outcomes[m.providerId];
        if (o == null) continue; // kept: not stored, still in the inbox
        if (o is IngestDuplicate || o is IngestDropped) {
          skipped++;
        } else {
          imported++;
          final inst = institutionOf[m.address.toLowerCase()];
          if (inst != null) found.add(inst);
        }
      }
      _set(
        _progress.copyWith(
          imported: _progress.imported + imported,
          skipped: _progress.skipped + skipped,
          institutions: found.length,
        ),
      );
    }
  }

  Future<IngestBatchResult> _ingestWithRetry(
    List<IncomingMessage> batch,
  ) async {
    var attempt = 0;
    while (true) {
      try {
        return await store.ingest(batch);
      } on IngestBatchFailed catch (e) {
        if (e.isTransient && attempt < writeRetries) {
          attempt++;
          await Future<void>.delayed(Duration(milliseconds: 50 * attempt));
          continue;
        }
        rethrow;
      }
    }
  }
}

final class _Stop implements Exception {
  const _Stop.cancelled() : cancelled = true, code = null;

  final bool cancelled;
  final String? code;
}
