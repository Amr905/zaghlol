// T-009 / SPK-03 spike: the headless entrypoint an iOS App Intent starts in
// perform(). Not production: T-061..T-067 replace it. It receives one body,
// returns code-only numbers (length, digit runs) and never logs or stores the
// body.

import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const iosIntentSpikeChannelName = 'zaghlol/spike/intent';

/// Installs the `process` handler, then tells native it is ready.
MethodChannel startIosIntentSpike({BinaryMessenger? messenger}) {
  final channel = MethodChannel(
    iosIntentSpikeChannelName,
    const StandardMethodCodec(),
    messenger,
  );
  channel.setMethodCallHandler((call) async {
    if (call.method != 'process') {
      throw MissingPluginException();
    }
    final args = call.arguments as Map<Object?, Object?>;
    final body = args['body']! as String;
    final holdMs = args['holdMs']! as int;
    if (holdMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: holdMs));
    }
    return <String, int>{
      'bodyLength': body.length,
      'digitRuns': RegExp('[0-9]+').allMatches(body).length,
    };
  });
  unawaited(_announceReady(channel));
  return channel;
}

/// Native installs its handler only after the engine runs (the messenger
/// asserts before that), so the first attempts may find nobody listening.
/// Retries every 20 ms for at most 10 s.
Future<void> _announceReady(MethodChannel channel) async {
  for (var i = 0; i < 500; i++) {
    try {
      if (await channel.invokeMethod<bool>('ready') ?? false) return;
    } on MissingPluginException {
      // not installed yet
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Body of `spikeIntentMain` (lib/main.dart).
void runIosIntentSpike() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  startIosIntentSpike();
}

/// Test entrypoint: starts but never announces ready (the "engine hangs"
/// case; a missing entrypoint aborts the process, so it can't be tested).
void runIosIntentSpikeSilent() {
  WidgetsFlutterBinding.ensureInitialized();
}
