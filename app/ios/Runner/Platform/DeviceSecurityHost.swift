import Flutter
import Foundation
import LocalAuthentication
import UIKit

/// T-103: the Pigeon `DeviceSecurityHostApi` (platform-channels section 5).
/// Flips platform switches and reads two booleans; no app logic, nothing is
/// logged and nothing but a boolean is returned.
final class DeviceSecurityHost: DeviceSecurityHostApi {
  /// Seams so XCTest needs no jailbroken device or Face ID hardware.
  var fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
  var canWriteOutsideSandbox: () -> Bool = DeviceSecurityHost.probeWrite
  var passcodeSet: () -> Bool = {
    var error: NSError?
    return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
  }
  var isSimulator: Bool = {
    #if targetEnvironment(simulator)
      return true
    #else
      return false
    #endif
  }()

  static let jailbreakPaths = [
    "/Applications/Cydia.app",
    "/Applications/Sileo.app",
    "/Library/MobileSubstrate/MobileSubstrate.dylib",
    "/bin/bash",
    "/usr/sbin/sshd",
    "/etc/apt",
    "/private/var/lib/apt",
    "/var/jb",
  ]

  /// FR-SEC-07 heuristic: warns only, trivially bypassable.
  func isDeviceRooted() throws -> Bool {
    if isSimulator { return false }
    if DeviceSecurityHost.jailbreakPaths.contains(where: fileExists) { return true }
    return canWriteOutsideSandbox()
  }

  func setSecureWindow(secure: Bool) throws {
    PrivacyCover.shared.setEnabled(secure)
  }

  func isDeviceSecure() throws -> Bool { passcodeSet() }

  private static func probeWrite() -> Bool {
    let path = "/private/zaghlol_probe_\(UUID().uuidString)"
    do {
      try "x".write(toFile: path, atomically: true, encoding: .utf8)
      try? FileManager.default.removeItem(atPath: path)
      return true
    } catch {
      return false
    }
  }
}

/// A solid cover over the app while the scene is not active, so the app
/// switcher snapshot is blank (FR-SEC-02). Only active while the app lock is on.
final class PrivacyCover {
  static let shared = PrivacyCover()

  private(set) var enabled = false
  private var coverViews: [UIView] = []

  private var observers: [NSObjectProtocol] = []

  func setEnabled(_ on: Bool) {
    enabled = on
    if on {
      startObserving()
    } else {
      stopObserving()
      remove()
    }
  }

  /// Observes scene notifications instead of overriding `FlutterSceneDelegate`
  /// methods, so Flutter's own lifecycle forwarding is untouched.
  private func startObserving() {
    guard observers.isEmpty else { return }
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) {
        [weak self] note in
        if let scene = note.object as? UIScene { self?.show(in: scene) }
      })
    observers.append(
      center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) {
        [weak self] _ in self?.remove()
      })
  }

  private func stopObserving() {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
  }

  /// Called when the scene is about to deactivate.
  func show(in scene: UIScene) {
    guard enabled, coverViews.isEmpty, let windowScene = scene as? UIWindowScene else { return }
    for window in windowScene.windows {
      let cover = UIView(frame: window.bounds)
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      cover.backgroundColor = .systemBackground
      cover.isUserInteractionEnabled = false
      window.addSubview(cover)
      coverViews.append(cover)
    }
  }

  /// Called when the scene becomes active again.
  func remove() {
    coverViews.forEach { $0.removeFromSuperview() }
    coverViews.removeAll()
  }
}

enum DeviceSecurityRegistration {
  static let host = DeviceSecurityHost()

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolDeviceSecurity") else { return }
    DeviceSecurityHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
  }
}
