import Flutter
import Foundation

/// T-148: the Pigeon `TextNormalizationHostApi` (platform-channels §5). NFC for
/// the backup passphrase so iOS and Android derive the same key. Stateless;
/// the argument is never logged, stored or put into an error.
final class TextNormalizationHost: TextNormalizationHostApi {
  func nfc(input: String) throws -> String {
    // Total on every valid Swift String; there is no failure path to map.
    return input.precomposedStringWithCanonicalMapping
  }
}

/// Registers the normalizer on the UI engine (backup runs in the foreground).
enum TextNormalizationRegistration {
  static let host = TextNormalizationHost()

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolTextNormalization") else { return }
    TextNormalizationHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
  }
}
