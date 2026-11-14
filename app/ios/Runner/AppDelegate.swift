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
    // T-062: the BGAppRefreshTask launch handler must be registered before
    // launch ends; also runs on background launches by the system.
    IngestBackgroundRefresh.registerLaunchHandler()
    IosCaptureRegistration.prepareKey()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // T-015: the database key store (every engine that opens the database).
    SecretStoreRegistration.register(with: engineBridge.pluginRegistry)
    // T-148: NFC for the backup passphrase.
    TextNormalizationRegistration.register(with: engineBridge.pluginRegistry)
    // T-180: trusted clock sample for the Gold offline bound.
    TrustedClockRegistration.register(with: engineBridge.pluginRegistry)
    // T-103: jailbreak heuristic, app switcher cover, passcode check.
    DeviceSecurityRegistration.register(with: engineBridge.pluginRegistry)
    // T-178: App Attest for restore.
    AttestationRegistration.register(with: engineBridge.pluginRegistry)
    // T-179: Secure Enclave seat keys (iOS only, D-55).
    SeatKeyRegistration.register(with: engineBridge.pluginRegistry)
    // T-151: iCloud backup host.
    ICloudBackupRegistration.register(with: engineBridge.pluginRegistry)
    // T-160: on-device OCR (Vision).
    OcrRegistration.register(with: engineBridge.pluginRegistry)
    // T-062: encrypted spool drain / ack and the background refresh.
    IosCaptureRegistration.register(with: engineBridge.pluginRegistry)
    // T-065: shares from the Share Extension.
    ShareIntakeRegistration.register(with: engineBridge.pluginRegistry)
  }
}
