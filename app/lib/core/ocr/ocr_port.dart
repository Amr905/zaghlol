// T-160: the shared OCR port. T-161 (templates and confirmation screen) codes
// against [OcrEngine] only; the iOS host (Vision, T-160) and the Android host
// (ML Kit + Tesseract, T-159, deferred) both sit behind it with this shape.
//
// Recognized text is financial data: this file never logs it, and
// [OcrException] carries a code only.

/// One recognized line. [box] is x, y, width, height, normalized 0..1, with
/// the origin at the top-left on both platforms.
final class OcrTextLine {
  const OcrTextLine({
    required this.text,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final String text;

  /// 0..1 recognition confidence (not money).
  final double confidence;
  final double x;
  final double y;
  final double width;
  final double height;

  // No toString that includes [text]: it is financial data.
  @override
  String toString() => 'OcrTextLine(<redacted>)';
}

final class OcrOutcome {
  const OcrOutcome(this.lines);

  /// Top to bottom.
  final List<OcrTextLine> lines;

  /// The lines joined by newlines, for the OCR-channel templates (T-161).
  String get fullText => lines.map((l) => l.text).join('\n');

  @override
  String toString() => 'OcrOutcome(${lines.length} lines)';
}

/// Why OCR failed. Code only; never the image path, text or native message.
enum OcrFailureCode {
  ocrFailed('OCR_FAILED'),
  ioError('IO_ERROR'),
  spoolDecryptFailed('SPOOL_DECRYPT_FAILED'),
  notAvailable('NOT_AVAILABLE');

  const OcrFailureCode(this.wire);
  final String wire;

  static OcrFailureCode fromWire(String? code) {
    for (final c in values) {
      if (c.wire == code) return c;
    }
    return ocrFailed;
  }
}

final class OcrException implements Exception {
  const OcrException(this.code);
  final OcrFailureCode code;

  @override
  String toString() => 'OcrException(${code.wire})';
}

/// On-device OCR. The host deletes [encryptedImagePath] after the call
/// (success or failure), except when OCR is not available on this device.
abstract interface class OcrEngine {
  /// [languages] are ISO 639-1 codes, e.g. `['ar', 'en']`. Languages the
  /// engine does not support are dropped by the host (Arabic only when
  /// supported); see [supportedLanguages].
  Future<OcrOutcome> recognize(
    String encryptedImagePath, {
    List<String> languages = const ['ar', 'en'],
  });

  /// ISO 639-1 codes the engine can read on this device.
  Future<List<String>> supportedLanguages();
}
