package app.zaghlol.platform.text

import io.flutter.plugin.common.BinaryMessenger
import java.text.Normalizer

/**
 * T-148: the Pigeon `TextNormalizationHostApi` (platform-channels §5). NFC for
 * the backup passphrase so Android and iOS derive the same key. Stateless; the
 * argument is never logged, stored or put into an error: any failure is a
 * code-only `NORMALIZATION_FAILED`.
 */
class TextNormalizationHost : TextNormalizationHostApi {
  override fun nfc(input: String): String =
    try {
      Normalizer.normalize(input, Normalizer.Form.NFC)
    } catch (e: Throwable) {
      throw TextNormalizationApiError(NORMALIZATION_FAILED, null, null)
    }

  companion object {
    const val NORMALIZATION_FAILED = "NORMALIZATION_FAILED"
  }
}

/** Registers the normalizer on the UI engine (backup runs in the foreground). */
object TextNormalizationRegistration {
  fun register(messenger: BinaryMessenger) {
    TextNormalizationHostApi.setUp(messenger, TextNormalizationHost())
  }
}
