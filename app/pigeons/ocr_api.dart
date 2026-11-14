// Pigeon contract: OCR (T-004 names, T-160 iOS host). Contract:
// docs/03-technical/platform-channels.md section 4. Regenerate with
// app/tool/generate_pigeon.sh; CI fails when the generated files are stale.
//
// Rules for both hosts: images and recognized text are financial data. They
// stay on the device, are never logged and never put into an error (errors
// are code-only: OCR_FAILED, IO_ERROR, SPOOL_DECRYPT_FAILED, NOT_AVAILABLE).
// The image is decrypted in memory and the file at encryptedImagePath is
// deleted in a finally block (receipt images are never persisted, FR-SEC-03).
// Box: x, y, width, height, normalized 0..1, ORIGIN TOP-LEFT on both
// platforms (Vision's bottom-left origin is flipped by the iOS host).
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/ocr_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut:
        'android/app/src/main/kotlin/app/zaghlol/platform/ocr/OcrApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.ocr',
      errorClassName: 'OcrApiError',
    ),
    swiftOut: 'ios/Runner/Platform/OcrApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'OcrApiError'),
  ),
)
@HostApi()
abstract class OcrHostApi {
  /// [languages] are ISO 639-1 codes, e.g. ['ar', 'en']. A language the engine
  /// does not support at runtime is dropped (Arabic is used only when
  /// supported); when none is left the host uses Latin-only recognition.
  @async
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  OcrResult recognize(String encryptedImagePath, List<String> languages);

  /// ISO 639-1 codes the engine can recognize on this device, at runtime.
  List<String> supportedLanguages();
}

class OcrResult {
  OcrResult({required this.lines});

  List<OcrLine> lines;
}

class OcrLine {
  OcrLine({required this.text, required this.confidence, required this.box});

  String text;

  /// 0..1 (not money).
  double confidence;

  /// [x, y, width, height], normalized, top-left origin.
  List<double> box;
}
