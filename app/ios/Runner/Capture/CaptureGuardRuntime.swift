import Foundation

/// T-063: the process-wide Capture Guard of the app process (the App Intents
/// and the Pigeon `writeGuardConfig` host use the same instance, so a
/// rewritten user part reaches the next intent at once; a later process
/// reads the file).
///
/// - Base part: the app bundle's Flutter asset (`GuardBaseSource.read`).
///   Extensions read the copy `mirrorBase()` puts in the App Group.
/// - User part: `<App Group>/Library/Application Support/guard/guard.user.enc`,
///   encrypted with the **shared** spool key (`KeychainSpoolKeyProvider` over
///   `SpoolKeychain`, FU-196).
///
/// Nil without an App Group container (capture then answers `NOT_AVAILABLE`).
enum CaptureGuardRuntime {
  static let shared: GuardRuntime? = make()

  static func make(
    container: URL? = SpoolLocation.containerURL(), bundleURL: URL = Bundle.main.bundleURL,
    keys: GuardKeyProvider = KeychainSpoolKeyProvider()
  ) -> GuardRuntime? {
    guard let container = container else { return nil }
    let store = GuardUserConfigStore(
      dir: GuardUserConfigStore.dir(inAppGroupContainer: container),
      cipher: AesGcmGuardUserCipher(keys: keys))
    return GuardRuntime(loadBase: { try GuardBaseSource.read(bundleURL: bundleURL) }, store: store)
  }

  /// 061-2: copies the bundled base into the App Group for the extensions,
  /// off the main thread. Never throws; a failure keeps the previous copy.
  static func mirrorBaseInBackground(
    container: URL? = SpoolLocation.containerURL(), bundleURL: URL = Bundle.main.bundleURL
  ) {
    guard let container = container else { return }
    DispatchQueue.global(qos: .utility).async {
      guard let base = try? GuardBaseSource.read(bundleURL: bundleURL),
        base.count <= GuardConfig.maxBaseBytes
      else { return }
      GuardBaseSource.mirror(base, intoGuardDir: GuardUserConfigStore.dir(inAppGroupContainer: container))
    }
  }

  /// The Pigeon `GuardConfigState` of `runtime` now (loads on first use).
  static func state(of runtime: GuardRuntime?) -> GuardConfigState {
    guard let snap = runtime?.state() else { return .unknown }
    switch snap.mode {
    case .invalid: return .baseInvalid
    case .full: return .full
    case .baseOnly:
      switch snap.userState {
      case .unreadable: return .userUnreadable
      case .retry: return .unknown
      case .absent, .ok: return .baseOnly
      }
    }
  }
}
