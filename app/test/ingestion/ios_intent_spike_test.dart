import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/ingestion/ios_intent_spike.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('process returns code-only numbers (fake native side)', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // No native side listens to `ready`: the spike must swallow that.
    startIosIntentSpike(messenger: messenger);

    const codec = StandardMethodCodec();
    final done = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      iosIntentSpikeChannelName,
      codec.encodeMethodCall(
        const MethodCall('process', {
          'body': 'synthetic 12 and 345',
          'holdMs': 0,
        }),
      ),
      done.complete,
    );
    final reply = codec.decodeEnvelope((await done.future)!) as Map;
    expect(reply, {'bodyLength': 20, 'digitRuns': 2});
  });
}
