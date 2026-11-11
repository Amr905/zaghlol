// T-041: the UI engine's ingestion (replaces the T-008 spike_foreground.dart).
// Opens (and on first launch creates) the database, drains the spool at start
// and on every CaptureEventsApi.onSpoolChanged (native notifies it after each
// spool write and when the worker sees the UI engine attached). main.dart
// starts it for devSms only; T-047 wires it for every build behind its
// startup gate.

import 'dart:async';

import '../core/platform/capture_api.g.dart';
import 'ingestion_runner.dart';
import 'spike_channel.dart';

/// Registers the CaptureEventsApi handler and drains once. Returns the runner.
IngestionRunner startForegroundIngestion({IngestionRunner? runner}) {
  final r =
      runner ?? IngestionRunner(marks: defaultCycleMarks(), headless: false);
  CaptureEventsApi.setUp(_Events(r));
  unawaited(r.drain());
  return r;
}

final class _Events implements CaptureEventsApi {
  _Events(this._runner);

  final IngestionRunner _runner;

  @override
  void onSpoolChanged(int pendingCount) => unawaited(_runner.drain());

  @override
  void onPermissionChanged(CaptureCapabilities c) {}
}
