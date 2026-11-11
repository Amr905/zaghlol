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
}) {
  final handler = HeadlessIngestionHandler(runner);
  HeadlessIngestionApi.setUp(handler);
  unawaited(
    (host ?? HeadlessIngestionHostApi()).ready().then<void>(
      (_) {},
      // No native side listening: the worker times out and tears down.
      onError: (Object _) {},
    ),
  );
  return handler;
}

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
