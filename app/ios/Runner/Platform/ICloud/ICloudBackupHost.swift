import Flutter
import Foundation

/// T-151: iCloud as the system reports it (task design note §1, §4, §6).
/// Nothing here logs.
final class SystemICloudEnvironment: ICloudEnvironment {
  private let containerIdentifier: String?
  private let listTimeout: TimeInterval

  init(containerIdentifier: String?, listTimeout: TimeInterval = 25) {
    self.containerIdentifier = containerIdentifier
    self.listTimeout = listTimeout
  }

  /// The container identifier from Info.plist (`ZaghlolICloudContainer`), or
  /// nil when it is missing or unexpanded (fail closed: iCloud unavailable).
  static func containerIdentifier(from bundle: Bundle) -> String? {
    guard let id = bundle.object(forInfoDictionaryKey: "ZaghlolICloudContainer") as? String,
      id.hasPrefix("iCloud."), !id.contains("$"), id.count <= 255
    else { return nil }
    return id
  }

  func containerURL() -> URL? {
    guard let id = containerIdentifier, FileManager.default.ubiquityIdentityToken != nil else {
      return nil
    }
    return FileManager.default.url(forUbiquityContainerIdentifier: id)
  }

  /// `NSMetadataQuery` sees items that are not downloaded (no `.icloud` stub
  /// parsing). Gathering must finish: a timeout or start failure throws, so a
  /// caller never takes a partial listing for a complete one.
  func listItems(in dir: URL) throws -> [BackupMeta] {
    final class Box {
      let lock = NSLock()
      var result: Result<[BackupMeta], ICloudBackupError>?
      var query: NSMetadataQuery?
      var observer: NSObjectProtocol?
      func set(_ r: Result<[BackupMeta], ICloudBackupError>) {
        lock.lock()
        if result == nil { result = r }
        lock.unlock()
      }
      func stopOnMain() {
        query?.stop()
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = nil
        query = nil
      }
    }
    let box = Box()
    let done = DispatchSemaphore(value: 0)
    let wantDir = Self.canonical(dir)
    DispatchQueue.main.async {
      let q = NSMetadataQuery()
      q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
      q.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemFSNameKey, "zaghlol-backup-")
      box.query = q
      box.observer = NotificationCenter.default.addObserver(
        forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main
      ) { _ in
        q.disableUpdates()
        var out: [BackupMeta] = []
        for i in 0..<q.resultCount {
          guard let item = q.result(at: i) as? NSMetadataItem,
            let meta = Self.meta(item, in: wantDir)
          else { continue }
          out.append(meta)
          if out.count >= ICloudBackupNames.maxListed { break }
        }
        box.stopOnMain()
        box.set(.success(out))
        done.signal()
      }
      if !q.start() {
        box.stopOnMain()
        box.set(.failure(.io))
        done.signal()
      }
    }
    if done.wait(timeout: .now() + listTimeout) == .timedOut {
      box.set(.failure(.timeout))
      DispatchQueue.main.async { box.stopOnMain() }
    }
    box.lock.lock()
    let r = box.result ?? .failure(.timeout)
    box.lock.unlock()
    return try r.get()
  }

  private static func canonical(_ url: URL) -> String {
    var p = url.standardizedFileURL.resolvingSymlinksInPath().path
    if p.hasPrefix("/private/") { p.removeFirst("/private".count) }
    while p.hasSuffix("/") && p.count > 1 { p.removeLast() }
    return p
  }

  private static func meta(_ item: NSMetadataItem, in dir: String) -> BackupMeta? {
    guard let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String,
      ICloudBackupNames.isOurs(name),
      let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
      canonical(url.deletingLastPathComponent()) == dir
    else { return nil }
    let size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value
    let created = (item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date).map {
      Int64($0.timeIntervalSince1970 * 1000)
    }
    let uploaded = (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool) ?? false
    let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
    let uploadError = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError
    let quota =
      uploadError?.domain == NSCocoaErrorDomain
      && uploadError?.code == CocoaError.ubiquitousFileNotUploadedDueToQuota.rawValue
    return BackupMeta(
      name: name, sizeBytes: size, createdAtMs: created, isUploaded: uploaded,
      isDownloaded: status == NSMetadataUbiquitousItemDownloadingStatusCurrent,
      quotaExceeded: quota, uploadFailed: uploadError != nil && !quota)
  }

  func ensureDownloaded(_ url: URL, timeout: TimeInterval) throws {
    let keys: Set<URLResourceKey> = [
      .ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey,
    ]
    do {
      try FileManager.default.startDownloadingUbiquitousItem(at: url)
    } catch let e as CocoaError where e.code == .fileReadNoSuchFile || e.code == .fileNoSuchFile {
      throw ICloudBackupError.notFound
    } catch {
      throw ICloudBackupError.io
    }
    let deadline = Date().addingTimeInterval(timeout)
    while true {
      var u = url
      u.removeAllCachedResourceValues()
      let v: URLResourceValues
      do {
        v = try u.resourceValues(forKeys: keys)
      } catch {
        throw ICloudBackupError.io
      }
      if v.ubiquitousItemDownloadingStatus == .current { return }
      if v.ubiquitousItemDownloadingError != nil { throw ICloudBackupError.io }
      if Date() >= deadline { throw ICloudBackupError.timeout }
      Thread.sleep(forTimeInterval: 0.5)
    }
  }
}

/// The Pigeon `ICloudBackupHostApi` (platform-channels §5). Every call runs
/// on one serial background queue, so a call Dart stopped waiting for still
/// finishes before the next one starts. Errors cross as code-only
/// `IcloudApiError`s.
final class ICloudBackupHost: ICloudBackupHostApi {
  private let files: ICloudBackupFiles
  private let queue = DispatchQueue(label: "app.zaghlol.icloud-backup", qos: .utility)

  init(files: ICloudBackupFiles) {
    self.files = files
  }

  static func apiError(_ e: Error) -> IcloudApiError {
    let code = (e as? ICloudBackupError)?.code ?? ICloudBackupError.io.code
    return IcloudApiError(code: code, message: nil, details: nil)
  }

  private func run<T>(_ completion: @escaping (Result<T, Error>) -> Void, _ body: @escaping () throws -> T) {
    queue.async {
      do {
        completion(.success(try body()))
      } catch {
        completion(.failure(Self.apiError(error)))
      }
    }
  }

  func isAvailable(completion: @escaping (Result<Bool, Error>) -> Void) {
    run(completion) { self.files.isAvailable() }
  }

  func upload(path: String, name: String, completion: @escaping (Result<BackupMeta, Error>) -> Void) {
    run(completion) { try self.files.upload(sourcePath: path, name: name) }
  }

  func list(completion: @escaping (Result<[BackupMeta], Error>) -> Void) {
    run(completion) { try self.files.list() }
  }

  func download(name: String, completion: @escaping (Result<String, Error>) -> Void) {
    run(completion) { try self.files.download(name: name) }
  }

  func delete(name: String, completion: @escaping (Result<Void, Error>) -> Void) {
    run(completion) { try self.files.delete(name: name) }
  }
}

/// Registers the iCloud backup host on the UI engine (backup and restore run
/// in the foreground; T-152 schedules decide later whether a background
/// engine needs it).
enum ICloudBackupRegistration {
  static let host = ICloudBackupHost(
    files: ICloudBackupFiles(
      env: SystemICloudEnvironment(
        containerIdentifier: SystemICloudEnvironment.containerIdentifier(from: .main)),
      tempRoot: FileManager.default.temporaryDirectory))

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolICloudBackup") else { return }
    ICloudBackupHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
  }
}
