// Pigeon contract: ocr (T-004; Android host T-159, iOS host T-160), exactly as
// in docs/03-technical/platform-channels.md section 4. Regenerate with
// app/tool/generate_pigeon.sh; CI fails when the generated files are stale.
//
// Errors are PlatformExceptions with codes OCR_FAILED, NOT_AVAILABLE, IO_ERROR
// or SPOOL_DECRYPT_FAILED and never carry recognised text. On Android
// `encryptedImagePath` is the id of a pending share in the T-060 store.
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
class OcrLine {
  OcrLine({required this.text, required this.confidence, required this.box});

  String text;

  /// 0..1.
  double confidence;

  /// x, y, width, height, each normalized to the image (0..1).
  List<double> box;
}

class OcrResult {
  OcrResult({required this.lines});

  List<OcrLine> lines;
}

@HostApi()
abstract class OcrHostApi {
  /// [languages] is a subset of `['ar', 'en']`. Unknown codes are ignored.
  @async
  OcrResult recognize(String encryptedImagePath, List<String> languages);

  List<String> supportedLanguages();
}
