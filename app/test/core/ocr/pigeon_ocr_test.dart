// T-160: the Dart side of the OCR channel against a fake platform
// implementation (synthetic text only).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ocr/ocr_port.dart';
import 'package:zaghlol/core/platform/ocr_api.g.dart';
import 'package:zaghlol/core/platform/pigeon_ocr.dart';

class _FakeApi extends OcrHostApi {
  Object? error;
  OcrResult result = OcrResult(lines: []);
  List<String> supported = ['en', 'ar'];
  final List<(String, List<String>)> calls = [];

  @override
  Future<OcrResult> recognize(
    String encryptedImagePath,
    List<String> languages,
  ) async {
    calls.add((encryptedImagePath, languages));
    final e = error;
    if (e != null) throw e;
    return result;
  }

  @override
  Future<List<String>> supportedLanguages() async {
    final e = error;
    if (e != null) throw e;
    return supported;
  }
}

void main() {
  test('maps lines, keeps order and passes languages through', () async {
    final api = _FakeApi()
      ..result = OcrResult(
        lines: [
          OcrLine(
            text: 'تم التحويل',
            confidence: 0.9,
            box: [0.1, 0.2, 0.5, 0.1],
          ),
          OcrLine(text: 'EGP 125.50', confidence: 0.8, box: [0, 0.4, 1, 0.1]),
          OcrLine(text: 'bad box', confidence: 0.8, box: [0, 1]),
        ],
      );
    final out = await PigeonOcrEngine(api: api).recognize('/p/x.bin');
    expect(api.calls.single.$2, ['ar', 'en']);
    expect(out.lines.map((l) => l.text), ['تم التحويل', 'EGP 125.50']);
    expect(out.lines.first.y, 0.2);
    expect(out.fullText, 'تم التحويل\nEGP 125.50');
  });

  test('toString never shows recognized text', () async {
    final api = _FakeApi()
      ..result = OcrResult(
        lines: [
          OcrLine(text: 'sentinel-text', confidence: 1, box: [0, 0, 1, 1]),
        ],
      );
    final out = await PigeonOcrEngine(api: api).recognize('/p/x.bin');
    expect(out.toString(), isNot(contains('sentinel')));
    expect(out.lines.single.toString(), isNot(contains('sentinel')));
  });

  for (final c in OcrFailureCode.values) {
    test('${c.wire} becomes a code-only exception', () async {
      final api = _FakeApi()
        ..error = PlatformException(
          code: c.wire,
          message: 'secret-sentinel',
          details: 'secret-sentinel',
        );
      final engine = PigeonOcrEngine(api: api);
      try {
        await engine.recognize('/secret-sentinel/x.bin');
        fail('expected an exception');
      } on OcrException catch (e) {
        expect(e.code, c);
        expect(e.toString(), isNot(contains('sentinel')));
      }
    });
  }

  test('an unknown code or a non-platform error maps to OCR_FAILED', () async {
    final api = _FakeApi()..error = PlatformException(code: 'weird');
    final engine = PigeonOcrEngine(api: api);
    await expectLater(
      engine.recognize('/p'),
      throwsA(
        isA<OcrException>().having(
          (e) => e.code,
          'code',
          OcrFailureCode.ocrFailed,
        ),
      ),
    );
    api.error = StateError('x');
    await expectLater(
      engine.supportedLanguages(),
      throwsA(isA<OcrException>()),
    );
  });

  test('supportedLanguages passes the list through', () async {
    expect(await PigeonOcrEngine(api: _FakeApi()).supportedLanguages(), [
      'en',
      'ar',
    ]);
  });
}
