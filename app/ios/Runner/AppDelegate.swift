import Flutter
import UIKit
import UserNotifications

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
    // T-063 (061-2): the Guard base copy the extensions read.
    CaptureGuardRuntime.mirrorBaseInBackground()
    // T-066 (T-062 minor 2): once per app launch, held entries go back to the
    // spool when the build changed (an update may fix the cause). Never deletes.
    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
      DispatchQueue.global(qos: .utility).async {
        _ = SpoolRuntime.shared?.store.releaseHeldIfVersionChanged(appVersion: version)
      }
    }
    // NOTIF-GW: taps on local notifications (no remote notifications).
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // NOTIF-GW: show alerts as a banner while the app is open.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  // NOTIF-GW: the payload is a route id, never data.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NotificationsHost.didTap(
      route: response.notification.request.content.userInfo[NotificationsHost.routeKey] as? String)
    completionHandler()
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // T-015: the database key store (every engine that opens the database).
    SecretStoreRegistration.register(with: engineBridge.pluginRegistry)
    // T-148: NFC for the backup passphrase.
    TextNormalizationRegistration.register(with: engineBridge.pluginRegistry)
    // T-118: home-screen widget snapshot.
    WidgetBridgeRegistration.register(with: engineBridge.pluginRegistry)
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
    // T-117: the system share sheet for the share-studio PNG.
    ShareImageRegistration.register(with: engineBridge.pluginRegistry)
    // NOTIF-GW: local notifications and the permission prompt.
    NotificationsRegistration.register(with: engineBridge.pluginRegistry)
  }
}
