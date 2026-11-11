import Foundation

/// FR-SEC-05 / T-165: keeps every Zaghlol data directory out of iCloud and
/// Finder backups and out of iPhone migration.
///
/// The exclusion is set on **directories**, never on files: SQLite `-wal`/`-shm`
/// files, rename-based restore swaps and atomic writes all replace files and
/// would drop a per-file flag, while a directory's flag covers everything
/// below it (Apple QA1719).
///
/// Compiled into Runner now; T-062/T-063 add this file to the Share Extension
/// and widget targets. Every native directory creation must go through
/// `ensureExcluded(_:)`.
///
/// Policy for later tasks: no app data in `UserDefaults` (standard or App
/// Group). `Library/Preferences` is backed up and cannot be excluded reliably.
enum ZaghlolDirectories {

  /// Diagnostic code recorded on failure. Never logged with a path.
  static let backupExclusionFailedCode = "BACKUP_EXCLUSION_FAILED"

  /// App Group identifier shared with the extensions. `nil` until T-062 adds
  /// the App Group entitlement; while nil, the App Group directories are skipped.
  static let appGroupIdentifier: String? = nil

  enum ExclusionError: Error {
    case notExcluded
  }

  /// Creates `url` (with intermediate directories) if needed, marks it
  /// excluded from backup, reads the flag back and throws unless it is `true`.
  /// Idempotent.
  static func ensureExcluded(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var target = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try target.setResourceValues(values)
    // Read the value from disk, not from the URL's cache.
    let check = URL(fileURLWithPath: url.path, isDirectory: true)
    guard try check.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    else {
      throw ExclusionError.notExcluded
    }
  }

  /// The sandbox roots that must never be backed up.
  static func appContainerDirectories(fileManager: FileManager = .default) -> [URL] {
    var urls: [URL] = []
    for directory in [
      FileManager.SearchPathDirectory.applicationSupportDirectory,
      .documentDirectory,
      .cachesDirectory,
    ] {
      if let url = fileManager.urls(for: directory, in: .userDomainMask).first {
        urls.append(url)
      }
    }
    urls.append(URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
    return urls
  }

  /// The App Group directories (spool, guard config, widget snapshot), or an
  /// empty list while the App Group container does not exist.
  static func appGroupDirectories(
    appGroupIdentifier: String? = ZaghlolDirectories.appGroupIdentifier,
    fileManager: FileManager = .default
  ) -> [URL] {
    guard let groupID = appGroupIdentifier,
      let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    else {
      return []
    }
    return [
      container.appendingPathComponent("spool", isDirectory: true),
      container.appendingPathComponent("Library/Application Support", isDirectory: true),
      container.appendingPathComponent("Library/Caches", isDirectory: true),
    ]
  }

  /// Applies `ensureExcluded` to every directory in the set. Never throws or
  /// crashes; returns `false` and records `BACKUP_EXCLUSION_FAILED` if any
  /// directory could not be excluded. Called first in
  /// `AppDelegate.application(_:didFinishLaunchingWithOptions:)` and again
  /// after "Delete everything" recreates the directories.
  @discardableResult
  static func applyAll(appGroupIdentifier: String? = ZaghlolDirectories.appGroupIdentifier) -> Bool {
    exclude(appContainerDirectories() + appGroupDirectories(appGroupIdentifier: appGroupIdentifier))
  }

  /// `ensureExcluded` on each URL; one failure does not stop the others.
  /// Returns `false` (and records the diagnostic code) if any URL failed.
  @discardableResult
  static func exclude(_ urls: [URL]) -> Bool {
    var allExcluded = true
    for url in urls {
      do {
        try ensureExcluded(url)
      } catch {
        allExcluded = false
      }
    }
    if !allExcluded {
      // Code only: no path, no error text (T-021 native diag hook).
      NativeDiagHook.report(backupExclusionFailedCode)
    }
    return allExcluded
  }
}

/// T-021: native side of the diagnostic log. Native code reports a fixed code
/// (an allow-listed `DiagCodes` value, never a path or error text). Nothing is
/// printed to the system log. The handler is `nil` until the platform-channel
/// bridge that writes into `diag_log` is installed (follow-up native task);
/// until then reports are dropped.
enum NativeDiagHook {
  static var handler: ((String) -> Void)?

  static func report(_ code: String) {
    handler?(code)
  }
}
