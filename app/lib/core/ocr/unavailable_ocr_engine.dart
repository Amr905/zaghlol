// T-161: the OCR engine of a phone with no OCR host yet (Android until T-159
// lands). Every call reports NOT_AVAILABLE; nothing else in the app changes
// when a real host replaces it behind [ocrEngineProvider].

import 'ocr_port.dart';

final class UnavailableOcrEngine implements OcrEngine {
  const UnavailableOcrEngine();

  @override
  Future<OcrOutcome> recognize(
    String encryptedImagePath, {
    List<String> languages = const ['ar', 'en'],
  }) =>
      Future<OcrOutcome>.error(const OcrException(OcrFailureCode.notAvailable));

  @override
  Future<List<String>> supportedLanguages() async => const <String>[];
}
