import Foundation

/// Where the spool and the capture status live (platform-channels.md 1.3):
/// the App Group container, so the app, the App Intents and the extensions
/// see the same files. Every directory goes through
/// `ZaghlolDirectories.ensureExcluded` before its first write.
///
/// Nothing is written at the container root (T-165 F5): the spool is
/// `spool/`, the status `Library/Application Support/capture/`.
enum SpoolLocation {
  /// The container root, or nil without the App Group entitlement. On a real
  /// device a missing container is a build defect and capture answers
  /// `NOT_AVAILABLE`; the Simulator and unsigned test builds may fall back
  /// to the app's own Application Support so development still runs.
  static func containerURL(
    appGroupIdentifier: String? = ZaghlolDirectories.appGroupIdentifier,
    fileManager: FileManager = .default
  ) -> URL? {
    if let id = appGroupIdentifier, let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: id) {
      return url
    }
    #if targetEnvironment(simulator)
      return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("zaghlol-appgroup-fallback", isDirectory: true)
    #else
      return nil
    #endif
  }

  static func spoolDirectory(in container: URL) -> URL {
    container.appendingPathComponent("spool", isDirectory: true)
  }

  /// T-065: shared files (the Share Extension's encrypted shares and the OCR
  /// host's input), `spool/files/`. Never at the container root.
  static func filesDirectory(in container: URL) -> URL {
    spoolDirectory(in: container).appendingPathComponent("files", isDirectory: true)
  }

  static func statusFile(in container: URL) -> URL {
    container.appendingPathComponent("Library/Application Support/capture/status.bin")
  }
}

/// The production spool for this process: one store and one status store
/// over the shared container and the shared Keychain key.
final class SpoolRuntime {
  let store: SpoolStore
  let status: CaptureStatusStore
  let cipher: KeychainSpoolCipher

  init(store: SpoolStore, status: CaptureStatusStore, cipher: KeychainSpoolCipher) {
    self.store = store
    self.status = status
    self.cipher = cipher
  }

  static let shared: SpoolRuntime? = make()

  /// T-065: the share store over the same container and the same cipher.
  func shareStore(container: URL) -> ShareStore {
    ShareStore(dir: SpoolLocation.filesDirectory(in: container), cipher: cipher)
  }

  static func make(container: URL? = SpoolLocation.containerURL()) -> SpoolRuntime? {
    guard let container = container else { return nil }
    let cipher = KeychainSpoolCipher()
    let status = CaptureStatusStore(file: SpoolLocation.statusFile(in: container), cipher: cipher)
    let store = SpoolStore(
      dir: SpoolLocation.spoolDirectory(in: container), cipher: cipher, status: status)
    return SpoolRuntime(store: store, status: status, cipher: cipher)
  }
}
