// Pigeon contract: Unicode normalization (T-148). Dart has no Unicode
// normalizer, and the backup passphrase must give the same bytes on Android
// and iOS (keyboards may emit different code-point sequences for the same
// Arabic letter with hamza or madda). Contract: docs/03-technical/
// platform-channels.md §5; design: docs/04-tasks/tasks/T-148.md "Design note"
// §4. Regenerate with app/tool/generate_pigeon.sh; CI fails when the
// generated files are stale.
//
// Rules for the native side (both platforms): stateless; the argument is
// never logged, stored or put into an error. Errors cross the boundary as a
// code-only `NORMALIZATION_FAILED`.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/text_normalization_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/text/TextNormalizationApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.text',
      errorClassName: 'TextNormalizationApiError',
    ),
    swiftOut: 'ios/Runner/Platform/TextNormalizationApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'TextNormalizationApiError'),
  ),
)
@HostApi()
abstract class TextNormalizationHostApi {
  /// Unicode canonical composition (NFC) of [input]: Android
  /// `java.text.Normalizer.normalize(input, Form.NFC)`, iOS
  /// `precomposedStringWithCanonicalMapping`.
  String nfc(String input);
}
