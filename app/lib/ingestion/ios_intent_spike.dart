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
  unawaited(
    channel
        .invokeMethod<void>('ready')
        .then<void>(
          (_) {},
          // No native side listening: nothing to do.
          onError: (Object _) {},
        ),
  );
  return channel;
}

/// Body of `spikeIntentMain` (lib/main.dart).
void runIosIntentSpike() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  startIosIntentSpike();
}
