import Foundation

/// Reads the bundled Guard base part `assets/guard/guard_base.json`
/// (Flutter asset, generated from the registry by T-036) without a Flutter
/// engine. Plaintext public registry data, protected by the app signature.
///
/// The app reads it from its own bundle; the extensions (T-062/T-063) read
/// the copy the app mirrors into the App Group container
/// (`<container>/Library/Application Support/guard/guard_base.json`), because
/// an extension's bundle does not hold the Flutter assets.
enum GuardBaseSource {
  /// Where Flutter packs the asset inside the app bundle.
  static let bundleRelativePath =
    "Frameworks/App.framework/flutter_assets/assets/guard/guard_base.json"
  static let mirrorFileName = "guard_base.json"

  struct Missing: Error {}

  /// The bundled base inside `bundleURL` (the app bundle), at most
  /// `GuardConfig.maxBaseBytes + 1` bytes (a larger file is cut there, so the
  /// reader reports `tooLarge`). Throws when it is missing or unreadable;
  /// the runtime maps that to mode `invalid` and retries on the next load.
  static func read(bundleURL: URL) throws -> Data {
    try readBounded(bundleURL.appendingPathComponent(bundleRelativePath))
  }

  /// The mirror in an App Group guard directory (see `GuardUserConfigStore.dir`).
  static func readMirror(guardDir: URL) throws -> Data {
    try readBounded(guardDir.appendingPathComponent(mirrorFileName))
  }

  /// Copies `base` to the mirror when it differs (atomic; the directory is
  /// backup-excluded). Returns whether it wrote. Never throws: a failed
  /// mirror leaves the extensions on the previous copy.
  @discardableResult
  static func mirror(_ base: Data, intoGuardDir dir: URL) -> Bool {
    do {
      try ZaghlolDirectories.ensureExcluded(dir)
      let target = dir.appendingPathComponent(mirrorFileName)
      if let existing = try? readBounded(target), existing == base { return false }
      let tmp = dir.appendingPathComponent(mirrorFileName + ".tmp")
      try base.write(to: tmp, options: [.atomic])
      if rename(tmp.path, target.path) != 0 {
        try? FileManager.default.removeItem(at: tmp)
        return false
      }
      return true
    } catch {
      return false
    }
  }

  static func readBounded(_ url: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    return try handle.read(upToCount: GuardConfig.maxBaseBytes + 1) ?? Data()
  }
}
