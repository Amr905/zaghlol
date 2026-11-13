// T-041: the headless ingestion engine's Dart entrypoint (production, every
// build; FU-083). Started natively by the IngestionWorker
// (app.zaghlol.platform.ingest) at `ingestionMain`. Never creates, wipes or
// migrates the database (Q6), never logs or prints message content. Control
// channel: the Pigeon HeadlessIngestionApi (pigeons/ingestion_api.dart).

import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../core/platform/ingestion_api.g.dart';
import 'ingestion_runner.dart';
import 'quiet_errors.dart';
import 'spike_channel.dart';

/// Native → Dart commands of the headless engine.
final class HeadlessIngestionHandler implements HeadlessIngestionApi {
  HeadlessIngestionHandler(this._runner);

  final IngestionRunner _runner;

  /// Runs one cycle (serialised with a running one). Never throws: the
  /// runner turns every failure into a code-only report.
  @override
  Future<IngestCycleReport> drain() async => (await _runner.drain()).toReport();

  /// Stops after the current batch, waits for the running cycle and the
  /// database close; native destroys the engine only after this answers.
  @override
  Future<void> close() => _runner.close();
}

/// Installs the handler, then tells native it is ready. Returns the handler
/// (tests).
HeadlessIngestionHandler startHeadlessIngestion(
  IngestionRunner runner, {
  HeadlessIngestionHostApi? host,
  Duration retryDelay = const Duration(milliseconds: 25),
}) {
  final handler = HeadlessIngestionHandler(runner);
  HeadlessIngestionApi.setUp(handler);
  unawaited(_announceReady(host ?? HeadlessIngestionHostApi(), retryDelay));
  return handler;
}

/// Tells native the handler is installed. iOS installs its side only after
/// `FlutterEngine.run()` returns (the messenger aborts the process otherwise,
/// SPK-03), so the first `ready` can find no listener: retry every
/// [retryDelay] up to [_readyAttempts] times. A failure never throws; with no
/// native side the worker times out and tears down.
Future<void> _announceReady(
  HeadlessIngestionHostApi host,
  Duration retryDelay,
) async {
  for (var attempt = 0; attempt < _readyAttempts; attempt++) {
    try {
      await host.ready();
      return;
    } on Object {
      if (retryDelay == Duration.zero) return;
      await Future<void>.delayed(retryDelay);
    }
  }
}

const int _readyAttempts = 400;

/// Body of `ingestionMain` (lib/main.dart, the root library the native
/// DartEntrypoint looks it up in).
void runIngestionMain() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  installQuietErrorHandlers((_) {});
  startHeadlessIngestion(
    IngestionRunner(marks: defaultCycleMarks(), headless: true),
  );
}
