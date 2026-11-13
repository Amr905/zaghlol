import CryptoKit
import XCTest

@testable import Runner

/// T-151: the iCloud backup file work on a plain directory standing in for
/// the ubiquity container (the simulator has no iCloud account). The
/// NSMetadataQuery listing and the download wait need a signed device with
/// iCloud: manual steps in docs/04-tasks/tasks/T-151.md.
private final class DirEnvironment: ICloudEnvironment {
  var root: URL?
  init(root: URL?) { self.root = root }

  func containerURL() -> URL? { root }

  func listItems(in dir: URL) throws -> [BackupMeta] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: dir.path) else { return [] }
    return try fm.contentsOfDirectory(atPath: dir.path).map { name in
      let attrs = try fm.attributesOfItem(atPath: dir.appendingPathComponent(name).path)
      return BackupMeta(
        name: name, sizeBytes: (attrs[.size] as? NSNumber)?.int64Value,
        createdAtMs: (attrs[.creationDate] as? Date).map { Int64($0.timeIntervalSince1970 * 1000) },
        isUploaded: true, isDownloaded: true, quotaExceeded: false, uploadFailed: false)
    }
  }

  func ensureDownloaded(_ url: URL, timeout: TimeInterval) throws {
    if !FileManager.default.fileExists(atPath: url.path) { throw ICloudBackupError.notFound }
  }
}

final class ICloudBackupTests: XCTestCase {
  private var base: URL!
  private var container: URL!
  private var temp: URL!
  private var env: DirEnvironment!
  private var files: ICloudBackupFiles!
  private let name = "zaghlol-backup-7-1731500000000.zaghlol.enc"

  override func setUpWithError() throws {
    base = FileManager.default.temporaryDirectory
      .appendingPathComponent("t151-\(UUID().uuidString)", isDirectory: true)
    container = base.appendingPathComponent("container", isDirectory: true)
    temp = base.appendingPathComponent("tmp", isDirectory: true)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    env = DirEnvironment(root: container)
    files = ICloudBackupFiles(env: env, tempRoot: temp)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: base)
  }

  private var backups: URL {
    container.appendingPathComponent("Documents/Backups", isDirectory: true)
  }

  private func source(_ bytes: [UInt8]) throws -> URL {
    let url = temp.appendingPathComponent("src-\(UUID().uuidString).bin")
    try Data(bytes).write(to: url)
    return url
  }

  private func md5Hex(_ data: Data) -> String {
    Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func assertCode(_ expected: ICloudBackupError, _ body: () throws -> Void, line: UInt = #line) {
    XCTAssertThrowsError(try body(), line: line) { e in
      XCTAssertEqual(e as? ICloudBackupError, expected, line: line)
    }
  }

  func testUploadWritesTheFinalNameLeavesNoPartialAndReportsTheMd5() throws {
    let bytes = (0..<300_000).map { UInt8($0 % 251) }
    let meta = try files.upload(sourcePath: try source(bytes).path, name: name)
    let stored = try Data(contentsOf: backups.appendingPathComponent(name))
    XCTAssertEqual(stored, Data(bytes))
    XCTAssertEqual(meta.name, name)
    XCTAssertEqual(meta.sizeBytes, Int64(bytes.count))
    XCTAssertEqual(meta.md5, md5Hex(Data(bytes)))
    XCTAssertFalse(meta.isUploaded)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path), [name])
  }

  func testUploadNeverOverwritesAnExistingBackup() throws {
    try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
    let old = Data([1, 2, 3])
    try old.write(to: backups.appendingPathComponent(name))
    let src = try source([9, 9, 9, 9])
    assertCode(.alreadyExists) { _ = try files.upload(sourcePath: src.path, name: name) }
    XCTAssertEqual(try Data(contentsOf: backups.appendingPathComponent(name)), old)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path), [name])
  }

  func testUploadNeverOverwritesAnExistingPartial() throws {
    try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
    let other = Data([4, 4])
    try other.write(to: backups.appendingPathComponent(name + ".partial"))
    let src = try source([9, 9, 9, 9])
    assertCode(.alreadyExists) { _ = try files.upload(sourcePath: src.path, name: name) }
    XCTAssertEqual(try Data(contentsOf: backups.appendingPathComponent(name + ".partial")), other)
    XCTAssertFalse(FileManager.default.fileExists(atPath: backups.appendingPathComponent(name).path))
  }

  func testNamesThatAreNotOursAreRefusedEverywhere() throws {
    let src = try source([1])
    let foreign = [
      "../\(name)", "\(name)\n", "notes.txt", "zaghlol-backup-1-2.zaghlol.enc/x",
      "zaghlol-backup-\u{0661}-2.zaghlol.enc", "", name + ".partial",
    ]
    for n in foreign {
      assertCode(.invalidArgument) { _ = try files.upload(sourcePath: src.path, name: n) }
      assertCode(.invalidArgument) { _ = try files.download(name: n) }
    }
    for n in foreign where n != name + ".partial" {
      assertCode(.invalidArgument) { try files.delete(name: n) }
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent(name).path))
  }

  func testEmptyOrMissingSourcesAreRefused() throws {
    let empty = try source([])
    assertCode(.invalidArgument) { _ = try files.upload(sourcePath: empty.path, name: name) }
    assertCode(.invalidArgument) {
      _ = try files.upload(sourcePath: temp.appendingPathComponent("missing").path, name: name)
    }
    assertCode(.invalidArgument) { _ = try files.upload(sourcePath: temp.path, name: name) }
  }

  func testListReturnsOnlyOurNames() throws {
    try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
    for n in [name, name + ".partial", "notes.txt", "zaghlol-backup-x.zaghlol.enc"] {
      try Data([1]).write(to: backups.appendingPathComponent(n))
    }
    XCTAssertEqual(Set(try files.list().map(\.name)), [name, name + ".partial"])
  }

  func testDeleteRemovesOnlyTheNamedBackupAndReportsAbsence() throws {
    try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
    let other = "zaghlol-backup-8-1731500000001.zaghlol.enc"
    for n in [name, other, "notes.txt"] {
      try Data([1]).write(to: backups.appendingPathComponent(n))
    }
    try files.delete(name: name)
    XCTAssertEqual(
      Set(try FileManager.default.contentsOfDirectory(atPath: backups.path)), [other, "notes.txt"])
    assertCode(.notFound) { try files.delete(name: name) }
  }

  func testDownloadCopiesIntoTempAndKeepsTheBackup() throws {
    let bytes: [UInt8] = [5, 6, 7, 8, 9]
    _ = try files.upload(sourcePath: try source(bytes).path, name: name)
    let path = try files.download(name: name)
    XCTAssertTrue(path.hasPrefix(temp.appendingPathComponent("zaghlol_backup_download").path))
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data(bytes))
    XCTAssertTrue(FileManager.default.fileExists(atPath: backups.appendingPathComponent(name).path))
    assertCode(.notFound) { _ = try files.download(name: "zaghlol-backup-1-1.zaghlol.enc") }
  }

  func testICloudOffIsUnavailableForEveryCall() throws {
    env.root = nil
    let src = try source([1])
    XCTAssertFalse(files.isAvailable())
    assertCode(.unavailable) { _ = try files.upload(sourcePath: src.path, name: name) }
    assertCode(.unavailable) { _ = try files.list() }
    assertCode(.unavailable) { _ = try files.download(name: name) }
    assertCode(.unavailable) { try files.delete(name: name) }
    XCTAssertNil(SystemICloudEnvironment(containerIdentifier: nil).containerURL())
  }

  func testHostErrorsCarryACodeOnly() {
    env.root = nil
    let host = ICloudBackupHost(files: files)
    let done = expectation(description: "upload")
    host.upload(path: "/nope", name: name) { result in
      if case .failure(let e as IcloudApiError) = result {
        XCTAssertEqual(e.code, "ICLOUD_UNAVAILABLE")
        XCTAssertNil(e.message)
        XCTAssertNil(e.details)
      } else {
        XCTFail("expected a code-only error")
      }
      done.fulfill()
    }
    let avail = expectation(description: "isAvailable")
    host.isAvailable { result in
      XCTAssertEqual(try? result.get(), false)
      avail.fulfill()
    }
    wait(for: [done, avail], timeout: 10)
  }

  func testContainerIdentifierComesFromInfoPlistPerFlavor() {
    let id = SystemICloudEnvironment.containerIdentifier(from: .main)
    XCTAssertNotNil(id)
    XCTAssertTrue(id?.hasPrefix("iCloud.app.zaghlol") ?? false)
    XCTAssertFalse(id?.contains("$") ?? true)
  }
}
