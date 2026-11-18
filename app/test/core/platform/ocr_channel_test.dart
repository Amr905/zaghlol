import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/ocr_api.g.dart';

const String _channel = 'dev.flutter.pigeon.zaghlol.OcrHostApi';
const MessageCodec<Object?> _codec = OcrHostApi.pigeonChannelCodec;

/// Stands in for the native OCR host (Android T-159, iOS T-160): answers the
/// Pigeon channels from in-memory state, as the generated native code would.
class _FakeNative {
  _FakeNative(this.messenger) {
    _on('recognize', (List<Object?> args) {
      calls.add(<Object?>[args[0], args[1]]);
      final failure = failWith;
      if (failure != null) {
        throw PlatformException(code: failure);
      }
      return OcrResult(
        lines: <OcrLine>[
          OcrLine(
            text: 'EGP 100',
            confidence: 0.8,
            box: <double>[0.1, 0.2, 0.3, 0.05],
          ),
        ],
      );
    });
    _on('supportedLanguages', (_) => languages);
  }

  final TestDefaultBinaryMessenger messenger;
  final List<List<Object?>> calls = <List<Object?>>[];
  List<String> languages = <String>['ar', 'en'];
  String? failWith;

  void _on(String method, Object? Function(List<Object?> args) handler) {
    messenger.setMockMessageHandler('$_channel.$method', (
      ByteData? message,
    ) async {
      final args = message == null
          ? <Object?>[]
          : _codec.decodeMessage(message)! as List<Object?>;
      try {
        return _codec.encodeMessage(<Object?>[handler(args)]);
      } on PlatformException catch (e) {
        return _codec.encodeMessage(<Object?>[e.code, e.message, e.details]);
      }
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeNative native;
  late OcrHostApi api;

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    native = _FakeNative(messenger);
    api = OcrHostApi(binaryMessenger: messenger);
  });

  tearDown(() {
    for (final m in <String>['recognize', 'supportedLanguages']) {
      native.messenger.setMockMessageHandler('$_channel.$m', null);
    }
  });

  test(
    'recognize passes the handle and languages and returns typed lines',
    () async {
      final result = await api.recognize('share-id', <String>['ar', 'en']);
      expect(native.calls.single, <Object?>[
        'share-id',
        <String>['ar', 'en'],
      ]);
      final line = result.lines.single;
      expect(line.text, 'EGP 100');
      expect(line.confidence, 0.8);
      expect(line.box, <double>[0.1, 0.2, 0.3, 0.05]);
    },
  );

  test('supportedLanguages reflects what the host reports', () async {
    expect(await api.supportedLanguages(), <String>['ar', 'en']);
    native.languages = <String>['en'];
    expect(await api.supportedLanguages(), <String>['en']);
  });

  test('contract error codes surface as PlatformException codes', () async {
    for (final code in <String>[
      'OCR_FAILED',
      'NOT_AVAILABLE',
      'IO_ERROR',
      'SPOOL_DECRYPT_FAILED',
    ]) {
      native.failWith = code;
      await expectLater(
        api.recognize('x', <String>['en']),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
    }
  });
}
