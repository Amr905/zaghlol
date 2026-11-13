// T-048: the triggers of the inbox scan and the production CatchUpScheduler
// (T-047 port). Three entry points share one InboxScanner (one scan at a
// time):
//  - [startFirstRun]: onboarding, right after the SMS permission (FR-ONB-06);
//    depth = `scan_depth_months` (A-11), plus the personal senders only with
//    the opt-in (FU-109 M-1).
//  - [requestIfPending] (CatchUpScheduler): called by T-047 after every drain
//    while live SMS is active. Runs the catch-up once per app start (Q7,
//    `kInboxCatchUpEnabled`) and whenever a request is stored
//    (`capture.catchup.*`, a missed SMS or an invalidated key). It returns at
//    once; the scan runs in the background.
//  - [rescanInstitution]: FR-CAP-07 after un-ignoring a card.
// A null watermark with no stored request never triggers a catch-up (FU-085).
// Only the UI engine owns this class; the headless engine never scans.

import 'dart:async';

import '../data/alert_store.dart';
import '../data/capture_host_port.dart';
import '../data/catch_up_scheduler.dart';
import '../data/scan_sources.dart';
import '../domain/scan_plan.dart';
import 'scan.dart';

final class ScanSettings {
  const ScanSettings({
    this.depthMonths = kDefaultScanDepthMonths,
    this.includePersonal = false,
  });

  final int depthMonths;
  final bool includePersonal;
}

/// After a failed catch-up the next drain does not retry for this long.
const Duration kCatchUpRetryCooldown = Duration(minutes: 5);

final class InboxScanService implements CatchUpScheduler {
  InboxScanService({
    required this.scanner,
    required this.host,
    required this.alerts,
    required this.watermark,
    required this.settings,
    this.enabled = true,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final InboxScanner scanner;
  final CaptureHostPort host;
  final AlertStore alerts;
  final WatermarkSource watermark;
  final Future<ScanSettings> Function() settings;

  /// `kInboxCatchUpEnabled` (Q7): the per-open catch-up. A stored request
  /// (missed SMS, invalidated key) is served even when this is off.
  final bool enabled;
  final int Function() _nowMs;

  bool _openDone = false;
  int? _failedAtMs;
  Future<void>? _catchUp;

  /// Completes when the running catch-up (if any) ended; for tests.
  Future<void> get idle => _catchUp ?? Future<void>.value();

  Stream<ScanProgress> get progress => scanner.changes;

  Future<bool> _smsReady() async {
    try {
      final c = await host.getCapabilities();
      return c.smsFlavor && c.smsGranted;
    } on Object {
      return false;
    }
  }

  /// First-run scan. Returns the final progress; a scan that is already
  /// running is joined.
  Future<ScanProgress> startFirstRun() async {
    final s = await settings();
    return scanner.run(
      ScanRequest(
        sinceMs: firstRunSinceMs(nowMs: _nowMs(), depthMonths: s.depthMonths),
        includePersonal: s.includePersonal,
      ),
    );
  }

  /// FR-CAP-07: re-scan the registry senders of [institutionCode] for the
  /// scan depth. Duplicates are absorbed; cards that are still ignored stay
  /// ignored (the Guard and the ignore rules run on every message).
  Future<ScanProgress> rescanInstitution(String institutionCode) async {
    final s = await settings();
    return scanner.run(
      ScanRequest(
        sinceMs: firstRunSinceMs(nowMs: _nowMs(), depthMonths: s.depthMonths),
        onlyInstitutions: {institutionCode},
      ),
    );
  }

  @override
  Future<void> requestIfPending() async {
    if (_catchUp != null || scanner.isRunning) return;
    final failed = _failedAtMs;
    if (failed != null &&
        _nowMs() - failed < kCatchUpRetryCooldown.inMilliseconds) {
      return;
    }
    final run = _catchUpOnce().whenComplete(() => _catchUp = null);
    _catchUp = run;
    // Cheap for the caller: the scan itself is not awaited here.
    unawaited(run.then<void>((_) {}, onError: (Object _) {}));
  }

  Future<void> _catchUpOnce() async {
    if (!await _smsReady()) return;
    final persisted = await alerts.read();
    final requested = persisted.catchUpFromMs;
    int? firstMissed;
    try {
      firstMissed = (await host.getSpoolStatus()).firstMissedSmsAtMs;
    } on Object {
      // The persisted request still covers it.
    }
    final openCheck = enabled && !_openDone;
    if (!openCheck && requested == null && firstMissed == null) return;
    int? wm;
    try {
      wm = await watermark.maxSmsReceivedAtMs();
    } on Object {
      _failedAtMs = _nowMs();
      return;
    }
    final now = _nowMs();
    final since = catchUpSinceMs(
      nowMs: now,
      watermarkMs: wm,
      firstMissedSmsAtMs: firstMissed,
      requestedFromMs: requested,
    );
    if (since == null) {
      // No watermark and no request: nothing to catch up (FU-085).
      _openDone = true;
      return;
    }
    final s = await settings();
    final result = await scanner.run(
      ScanRequest(sinceMs: since, includePersonal: s.includePersonal),
    );
    if (result.phase == ScanPhase.done) {
      _openDone = true;
      _failedAtMs = null;
      if (requested != null) {
        try {
          await alerts.clearCatchUp(ifFromMs: requested);
        } on Object {
          // The request stays; the next drain serves it again (deduped).
        }
      }
    } else {
      _failedAtMs = _nowMs();
    }
  }
}
