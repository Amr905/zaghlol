// T-008 (SPK-01): the headless engine's Dart entrypoint. Started natively by
// IngestionWorker (src/devSms only; Dart has no flavours, and without the
// native side this is never invoked). Never creates, wipes or migrates the
// database (Q6), never logs or prints message content.

import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'quiet_errors.dart';
import 'spike_channel.dart';
import 'spike_ingestion.dart';

/// Body of `ingestionMain` (lib/main.dart, the root library the native
/// DartEntrypoint looks it up in).
void runIngestionMain() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  installQuietErrorHandlers((_) {});
  final channel = SpikeChannel();
  final ingestion = SpikeIngestion(marks: channel, headless: true);
  channel.onCommand((command) async {
    if (command != 'drain') return null;
    return (await ingestion.drain()).toWire();
  });
  channel.ready();
}
