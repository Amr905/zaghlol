import Flutter
import Foundation
import UserNotifications

/// NOTIF-GW: the Pigeon `NotificationsHostApi` (platform-channels 4c). Local
/// notifications only: no `registerForRemoteNotifications`, no aps-environment
/// entitlement, no background push mode. The text arrives already redacted by
/// Dart; nothing here logs it. The payload is a route id kept in `userInfo`.
final class NotificationsHost: NotificationsHostApi {
  static let routeKey = "zaghlol.route"

  /// A route id is a short in-app path; anything else is dropped.
  static func cleanRoute(_ route: String?) -> String? {
    guard let r = route, !r.isEmpty, r.count <= 96, r.hasPrefix("/"),
      r.unicodeScalars.allSatisfy({ $0.value >= 0x21 && $0.value <= 0x7E })
    else { return nil }
    return r
  }

  /// The route of the tap that launched the app, until Dart takes it.
  private static let lock = NSLock()
  private static var launchRoute: String?
  static var events: NotificationsEventsApi?

  static func stash(_ route: String?) {
    lock.lock()
    launchRoute = cleanRoute(route)
    lock.unlock()
  }

  /// Called by the app delegate when the user taps a notification.
  static func didTap(route: String?) {
    guard let r = cleanRoute(route) else { return }
    guard let events = events else { return stash(r) }
    events.onTap(route: r) { result in
      if case .failure = result { stash(r) }  // Dart not listening yet (cold start)
    }
  }

  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func permissionStatus(completion: @escaping (Result<NotifPermissionMsg, Error>) -> Void) {
    center.getNotificationSettings { settings in
      let status: NotifPermissionMsg
      switch settings.authorizationStatus {
      case .notDetermined: status = .undetermined
      case .denied: status = .denied
      default: status = .granted
      }
      completion(.success(status))
    }
  }

  func requestPermission(completion: @escaping (Result<Bool, Error>) -> Void) {
    center.getNotificationSettings { [center] settings in
      switch settings.authorizationStatus {
      case .notDetermined:
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
          completion(.success(granted))
        }
      case .denied:
        completion(.success(false))  // iOS never prompts twice
      default:
        completion(.success(true))
      }
    }
  }

  func ensureChannels(channels: [NotifChannelMsg]) throws {}  // Android only

  func show(n: NotifMsg) throws {
    center.add(request(n, trigger: nil))
  }

  func schedule(n: NotifMsg, atEpochMs: Int64) throws {
    let seconds = max(1.0, Double(atEpochMs) / 1000.0 - Date().timeIntervalSince1970)
    center.add(request(n, trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
  }

  func cancelAll() throws {
    center.removeAllPendingNotificationRequests()
    center.removeAllDeliveredNotifications()
  }

  func takeLaunchRoute() throws -> String? {
    NotificationsHost.lock.lock()
    defer { NotificationsHost.lock.unlock() }
    let r = NotificationsHost.launchRoute
    NotificationsHost.launchRoute = nil
    return r
  }

  func openSystemSettings() throws {
    DispatchQueue.main.async {
      guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
      UIApplication.shared.open(url)
    }
  }

  private func request(_ n: NotifMsg, trigger: UNNotificationTrigger?) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = n.title
    content.body = n.body
    content.sound = .default
    if let r = NotificationsHost.cleanRoute(n.route) {
      content.userInfo = [NotificationsHost.routeKey: r]
    }
    return UNNotificationRequest(identifier: String(n.id), content: content, trigger: trigger)
  }
}

enum NotificationsRegistration {
  static let host = NotificationsHost()

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolNotifications") else { return }
    let messenger = registrar.messenger()
    NotificationsHostApiSetup.setUp(binaryMessenger: messenger, api: host)
    NotificationsHost.events = NotificationsEventsApi(binaryMessenger: messenger)
  }
}
