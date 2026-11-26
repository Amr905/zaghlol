// T-275: stale "notListening"/"done" from the previous (cancelled) session must
// not end the next recording.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:zaghlol/features/voice/application/speech_port.dart';
import 'package:zaghlol/features/voice/data/speech_to_text_port.dart';

const _ch = MethodChannel('plugin.csdcorp.com/speech_to_text');

Future<void> _native(String method, Object? args) async {
  final data = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, args),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(_ch.name, data, (_) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ch, (call) async {
          switch (call.method) {
            case 'initialize' || 'listen':
              return true;
            default:
              return null;
          }
        });
  });

  Future<(SpeechToTextPort, List<String>)> started() async {
    final port = SpeechToTextPort(SpeechToText.withMethodChannel());
    final events = <String>[];
    await port.start(
      localeId: 'ar_EG',
      onDevice: false,
      pauseFor: const Duration(seconds: 2),
      listenFor: const Duration(seconds: 30),
      sink: SpeechSink(
        onText: (t, {required isFinal}) => events.add('text:$t'),
        onLevel: (_) {},
        onEnded: () => events.add('ended'),
        onError: (e) => events.add('error:${e.name}'),
      ),
    );
    return (port, events);
  }

  test('late "notListening"/"done" before "listening" are ignored', () async {
    final (port, events) = await started();
    await _native('notifyStatus', 'notListening');
    await _native('notifyStatus', 'done');
    expect(events, isEmpty);
    await _native('notifyStatus', 'listening');
    await _native('notifyStatus', 'notListening');
    expect(events, ['ended']);
    await port.cancel();
  });

  test('a stale no-match error before listening is ignored', () async {
    final (port, events) = await started();
    await _native(
      'notifyError',
      '{"errorMsg":"error_no_match","permanent":true}',
    );
    expect(events, isEmpty);
    await _native('notifyStatus', 'listening');
    await _native(
      'notifyError',
      '{"errorMsg":"error_no_match","permanent":true}',
    );
    expect(events, ['error:noSpeech']);
    await port.cancel();
  });
}
