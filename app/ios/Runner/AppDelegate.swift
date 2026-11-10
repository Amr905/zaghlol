import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // FR-SEC-05 / T-165: must run before super, so before the Flutter engine
    // and plugins create any file. Runs on every launch (idempotent), also on
    // background cold launches by App Intents.
    ZaghlolDirectories.applyAll()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // T-015: the database key store (every engine that opens the database).
    SecretStoreRegistration.register(with: engineBridge.pluginRegistry)
  }
}
