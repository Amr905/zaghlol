// T-008 (SPK-01): the UI engine's side of the spike, devSms builds only
// (`appFlavor == 'devSms'`; every other build returns at once). Stands in for
// the startup gate (T-047) and the foreground ingestion (T-041) so the spike
// can be measured: opens (and on first launch creates) the database, drains
// the spool at start and on every CaptureEventsApi.onSpoolChanged.

import 'dart:async';

import 'package:flutter/services.dart';

import '../core/platform/capture_api.g.dart';
import 'ingestion_config.dart';
import 'spike_channel.dart';
import 'spike_ingestion.dart';

/// Starts the foreground spike when this is the devSms build. Returns the
/// ingestion (tests) or null.
SpikeIngestion? startSpikeForeground({String? flavor = appFlavor}) {
  if (flavor != kSpikeFlavor) return null;
  final ingestion = SpikeIngestion(marks: SpikeChannel(), headless: false);
  CaptureEventsApi.setUp(_Events(ingestion));
  unawaited(ingestion.drain());
  return ingestion;
}

final class _Events implements CaptureEventsApi {
  _Events(this._ingestion);

  final SpikeIngestion _ingestion;

  @override
  void onSpoolChanged(int pendingCount) => unawaited(_ingestion.drain());

  @override
  void onPermissionChanged(CaptureCapabilities c) {}
}
