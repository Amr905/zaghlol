// T-160: [OcrEngine] over the Pigeon `OcrHostApi` (platform-channels section
// 4). Every failure becomes a code-only [OcrException]: the native message
// and the image path never reach Dart errors or logs.

import 'package:flutter/services.dart';

import '../ocr/ocr_port.dart';
import 'ocr_api.g.dart';

final class PigeonOcrEngine implements OcrEngine {
  PigeonOcrEngine({OcrHostApi? api}) : _api = api ?? OcrHostApi();

  final OcrHostApi _api;

  @override
  Future<OcrOutcome> recognize(
    String encryptedImagePath, {
    List<String> languages = const ['ar', 'en'],
  }) async {
    final OcrResult result;
    try {
      result = await _api.recognize(encryptedImagePath, languages);
    } on PlatformException catch (e) {
      throw OcrException(OcrFailureCode.fromWire(e.code));
    } on Object {
      throw const OcrException(OcrFailureCode.ocrFailed);
    }
    final lines = <OcrTextLine>[];
    for (final l in result.lines) {
      final b = l.box;
      if (b.length != 4) continue; // malformed line: skip, never guess a box
      lines.add(
        OcrTextLine(
          text: l.text,
          confidence: l.confidence,
          x: b[0],
          y: b[1],
          width: b[2],
          height: b[3],
        ),
      );
    }
    return OcrOutcome(List.unmodifiable(lines));
  }

  @override
  Future<List<String>> supportedLanguages() async {
    try {
      return List.unmodifiable(await _api.supportedLanguages());
    } on PlatformException catch (e) {
      throw OcrException(OcrFailureCode.fromWire(e.code));
    } on Object {
      throw const OcrException(OcrFailureCode.ocrFailed);
    }
  }
}
