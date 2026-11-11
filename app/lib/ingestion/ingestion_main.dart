// T-008 (SPK-01): the headless engine's Dart entrypoint. Started natively by
// IngestionWorker (src/devSms only; Dart has no flavours, and without the
// native side this is never invoked). Never creates, wipes or migrates the
// database (Q6), never logs or prints message content.

import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'quiet_errors.dart';
import 'spike_channel.dart';
import 'spike_ingestion.dart';

/// Native → Dart commands of the headless engine. `drain` runs a cycle;
/// `close` (sent before native destroys the engine, F1) waits for a running
/// cycle and closes the database, then answers `{result: CLOSED}`. Anything
/// else is ignored.
Future<Object?> handleSpikeCommand(
  SpikeIngestion ingestion,
  String command,
) async {
  switch (command) {
    case 'drain':
      return (await ingestion.drain()).toWire();
    case 'close':
      await ingestion.close();
      return const {'result': 'CLOSED'};
  }
  return null;
}

/// Body of `ingestionMain` (lib/main.dart, the root library the native
/// DartEntrypoint looks it up in).
void runIngestionMain() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  installQuietErrorHandlers((_) {});
  final channel = SpikeChannel();
  final ingestion = SpikeIngestion(marks: channel, headless: true);
  channel.onCommand((command) => handleSpikeCommand(ingestion, command));
  channel.ready();
}
