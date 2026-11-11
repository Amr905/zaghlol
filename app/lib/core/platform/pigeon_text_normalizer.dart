// T-148: TextNormalizer over the Pigeon channel (platform-channels §5). Every
// failure becomes a code-only exception: the argument (a passphrase) and the
// native message never reach Dart errors or logs.

import '../../features/backup/crypto/passphrase.dart';
import 'text_normalization_api.g.dart';

/// A failed normalization. Code only.
final class TextNormalizationException implements Exception {
  const TextNormalizationException();

  @override
  String toString() => 'TextNormalizationException(NORMALIZATION_FAILED)';
}

final class PigeonTextNormalizer implements TextNormalizer {
  PigeonTextNormalizer({TextNormalizationHostApi? api})
    : _api = api ?? TextNormalizationHostApi();

  final TextNormalizationHostApi _api;

  @override
  Future<String> nfc(String input) async {
    try {
      return await _api.nfc(input);
    } on Object {
      throw const TextNormalizationException();
    }
  }
}
