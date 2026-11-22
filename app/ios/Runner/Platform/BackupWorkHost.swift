import BackgroundTasks
import Flutter
import Foundation

/// FU-168e: the periodic backup wake-up on iOS (platform-channels.md 4d). A
/// `BGProcessingTask` 'app.zaghlol.backup' that needs network and runs no Dart:
/// when it fires it leaves an empty "due" file; the app reads it (`takeDue`)
/// and runs the Dart BackupScheduleService. The system decides when (and
/// whether) it runs; the app's own checks on launch/resume remain the
/// guarantee. Info.plist: `BGTaskSchedulerPermittedIdentifiers` has
/// app.zaghlol.backup and `UIBackgroundModes` has `processing`.
final class BackupDueMark {
  private let url: URL

  init(url: URL = BackupDueMark.defaultURL) { self.url = url }

  static var defaultURL: URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return base.appendingPathComponent("backupwork", isDirectory: true)
      .appendingPathComponent("due")
  }

  func set() {
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: Data())
    }
  }

  /// True once per `set`; the mark is cleared.
  func take() -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    try? FileManager.default.removeItem(at: url)
    return true
  }

  func clear() { try? FileManager.default.removeItem(at: url) }
}

final class BackupWorkHost: BackupWorkHostApi {
  static let identifier = "app.zaghlol.backup"
  static let allowedDays: Set<Int64> = [1, 7, 30]

  struct SubmitFailure: Error {}
  struct BadPeriod: Error {}

  private let mark: BackupDueMark
  private let submit: (BGTaskRequest) throws -> Void
  private let cancelRequest: (String) -> Void

  init(
    mark: BackupDueMark = BackupDueMark(),
    submit: @escaping (BGTaskRequest) throws -> Void = { try BGTaskScheduler.shared.submit($0) },
    cancelRequest: @escaping (String) -> Void = { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: $0) }
  ) {
    self.mark = mark
    self.submit = submit
    self.cancelRequest = cancelRequest
  }

  /// The request for a period: network needed, no external power demanded
  /// (a backup is small and the system already defers processing work on low
  /// battery), earliest start after the period.
  static func request(periodDays: Int64) -> BGProcessingTaskRequest {
    let request = BGProcessingTaskRequest(identifier: identifier)
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = false
    request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(periodDays) * 86_400)
    return request
  }

  func schedule(periodDays: Int64) throws {
    guard Self.allowedDays.contains(periodDays) else { throw BadPeriod() }
    cancelRequest(Self.identifier)
    do { try submit(Self.request(periodDays: periodDays)) } catch { throw SubmitFailure() }
  }

  func cancel() throws {
    cancelRequest(Self.identifier)
    mark.clear()
  }

  func takeDue() throws -> Bool { mark.take() }

  /// Before the app finishes launching. The handler leaves the mark and ends;
  /// the next period is requested by Dart (`schedule`) once it runs the backup.
  static func registerLaunchHandler(mark: BackupDueMark = BackupDueMark()) {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      mark.set()
      task.setTaskCompleted(success: true)
    }
  }
}

enum BackupWorkRegistration {
  static let host = BackupWorkHost()

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolBackupWork") else { return }
    BackupWorkHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
  }
}
