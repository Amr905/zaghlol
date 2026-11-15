import Flutter
import Speech

/// T-120 (D-42): `FlutterMethodChannel("zaghlol/speech")`
/// `onDeviceSupport({locale}) -> Bool`.
///
/// True only when the OS recognizer for the locale can run without the
/// network. Dart starts the recognizer only after this says true; otherwise it
/// asks the user first. Nothing is recorded or logged here.
enum SpeechSupportRegistration {
  static let channelName = "zaghlol/speech"

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolSpeechSupport") else { return }
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "onDeviceSupport" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
        let locale = args["locale"] as? String, !locale.isEmpty
      else {
        result(FlutterError(code: "bad-args", message: "locale is required", details: nil))
        return
      }
      result(SpeechSupport.supportsOnDevice(localeId: locale))
    }
  }
}

enum SpeechSupport {
  /// `ar_EG` and `ar-EG` both work.
  static func supportsOnDevice(
    localeId: String,
    recognizer: (Locale) -> Bool = { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition ?? false }
  ) -> Bool {
    recognizer(Locale(identifier: localeId.replacingOccurrences(of: "-", with: "_")))
  }
}
