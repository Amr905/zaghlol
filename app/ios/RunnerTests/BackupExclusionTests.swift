import XCTest

@testable import Runner

/// T-165 (FR-SEC-05). RunnerTests is hosted by Runner (TEST_HOST), so
/// `AppDelegate.application(_:didFinishLaunchingWithOptions:)` has already
/// run. These tests deliberately do not call `applyAll()` before checking the
/// sandbox roots: they prove the launch path excluded them.
final class BackupExclusionTests: XCTestCase {

  private var scratch: URL!

  override func setUpWithError() throws {
    scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("t165-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: scratch)
  }

  private func isExcluded(_ url: URL) throws -> Bool {
    // Fresh URL so no cached resource value is read.
    let fresh = URL(fileURLWithPath: url.path, isDirectory: true)
    return try fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
      == true
  }

  // 1. Every sandbox root exists and is excluded after launch.
  func testAppContainerDirectoriesAreExcludedAtLaunch() throws {
    let urls = ZaghlolDirectories.appContainerDirectories()
    XCTAssertEqual(urls.count, 4, "Application Support, Documents, Caches, tmp")
    for url in urls {
      var isDirectory: ObjCBool = false
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        "\(url.lastPathComponent) missing")
      XCTAssertTrue(isDirectory.boolValue, "\(url.lastPathComponent) is not a directory")
      XCTAssertTrue(try isExcluded(url), "\(url.lastPathComponent) is not excluded from backup")
    }
  }

  func testDirectorySetCoversTheFlutterDataRoots() throws {
    let paths = ZaghlolDirectories.appContainerDirectories().map {
      $0.standardizedFileURL.resolvingSymlinksInPath().path
    }
    let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
    for expected in ["Library/Application Support", "Documents", "Library/Caches", "tmp"] {
      XCTAssertTrue(
        paths.contains { $0.hasPrefix(home) && $0.hasSuffix(expected) },
        "\(expected) is not in the exclusion set")
    }
  }

  // Sanity: a new directory is NOT excluded by default, so the reads above
  // cannot pass trivially.
  func testFreshDirectoryIsNotExcludedByDefault() throws {
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    XCTAssertFalse(try isExcluded(scratch))
  }

  // 2. ensureExcluded creates, excludes, is idempotent and survives
  // delete-and-recreate.
  func testEnsureExcludedCreatesAndExcludes() throws {
    let nested = scratch.appendingPathComponent("a/b", isDirectory: true)
    XCTAssertNoThrow(try ZaghlolDirectories.ensureExcluded(nested))
    XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    XCTAssertTrue(try isExcluded(nested))
  }

  func testEnsureExcludedIsIdempotent() throws {
    try ZaghlolDirectories.ensureExcluded(scratch)
    XCTAssertNoThrow(try ZaghlolDirectories.ensureExcluded(scratch))
    XCTAssertNoThrow(try ZaghlolDirectories.ensureExcluded(scratch))
    XCTAssertTrue(try isExcluded(scratch))
  }

  func testEnsureExcludedSurvivesDeleteAndRecreate() throws {
    try ZaghlolDirectories.ensureExcluded(scratch)
    try FileManager.default.removeItem(at: scratch)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    // A plain re-create loses the flag; that is why every creation goes
    // through ensureExcluded and "Delete everything" calls applyAll().
    XCTAssertFalse(try isExcluded(scratch))
    try ZaghlolDirectories.ensureExcluded(scratch)
    XCTAssertTrue(try isExcluded(scratch))
  }

  // applyAll() is the launch path, so no test calls it on the real roots:
  // testAppContainerDirectoriesAreExcludedAtLaunch must prove AppDelegate did.
  func testExcludeMarksEveryDirectory() throws {
    let dirs = ["x", "y/z"].map { scratch.appendingPathComponent($0, isDirectory: true) }
    XCTAssertTrue(ZaghlolDirectories.exclude(dirs))
    for dir in dirs {
      XCTAssertTrue(try isExcluded(dir))
    }
  }

  func testExcludeReportsFailureWithoutStoppingOrCrashing() throws {
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let file = scratch.appendingPathComponent("plain-file")
    try Data([0x00]).write(to: file)
    // A directory cannot be created below a regular file.
    let impossible = file.appendingPathComponent("sub", isDirectory: true)
    let fine = scratch.appendingPathComponent("fine", isDirectory: true)
    XCTAssertFalse(ZaghlolDirectories.exclude([impossible, fine]))
    XCTAssertTrue(try isExcluded(fine), "a failure must not stop the remaining directories")
  }

  // 3. Files created later (including atomic writes, as SQLite/restore do)
  // live under an excluded directory, and the directory stays excluded.
  func testFilesCreatedLaterStayUnderAnExcludedDirectory() throws {
    let support = try XCTUnwrap(
      ZaghlolDirectories.appContainerDirectories().first, "Application Support")
    let dir = support.appendingPathComponent("t165-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("zaghlol.db-wal")
    try Data([0x01, 0x02]).write(to: file, options: .atomic)
    try Data([0x03]).write(to: file, options: .atomic)

    let supportPath = support.resolvingSymlinksInPath().path
    XCTAssertTrue(file.resolvingSymlinksInPath().path.hasPrefix(supportPath + "/"))
    XCTAssertTrue(try isExcluded(support), "Application Support lost its exclusion")
  }

  // 4. App Group directories: enabled by T-062 together with the entitlement.
  func testAppGroupDirectoriesAreExcluded() throws {
    // T-062: the App Group entitlement exists; CI requires this test to run (no skip).
    let groupID = try XCTUnwrap(
      ZaghlolDirectories.appGroupIdentifier, "ZaghlolAppGroup missing from Info.plist")
    if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil {
      // Signed build (device, or a simulator build that carries the entitlement):
      // the launch path excluded the real App Group directories.
      let urls = ZaghlolDirectories.appGroupDirectories()
      XCTAssertEqual(urls.count, 3)
      for url in urls {
        XCTAssertTrue(try isExcluded(url), "App Group \(url.lastPathComponent) is not excluded")
      }
    } else {
      // The unsigned CI simulator build has no entitlement, so no container. The spool
      // falls back to a folder in Application Support there; the same three
      // directories must come out excluded through the same code path.
      let container = try XCTUnwrap(SpoolLocation.containerURL(), "no container and no fallback")
      let dirs = [
        SpoolLocation.spoolDirectory(in: container),
        container.appendingPathComponent("Library/Application Support", isDirectory: true),
        container.appendingPathComponent("Library/Caches", isDirectory: true),
      ]
      XCTAssertTrue(ZaghlolDirectories.exclude(dirs))
      for url in dirs {
        XCTAssertTrue(try isExcluded(url), "\(url.lastPathComponent) is not excluded")
      }
    }
  }

  func testAppGroupDirectoriesAreSkippedWithoutAContainer() {
    XCTAssertEqual(ZaghlolDirectories.appGroupDirectories(appGroupIdentifier: nil), [])
    XCTAssertEqual(
      ZaghlolDirectories.appGroupDirectories(appGroupIdentifier: "group.app.zaghlol.t165.none"), [])
  }

  // T-166 (T-165 F4): "Delete everything" clears the contents of the roots,
  // never the roots, and the roots are excluded again before the
  // first-launch database is created.
  func testDeleteEverythingKeepsRootsExcluded() throws {
    let a = scratch.appendingPathComponent("support", isDirectory: true)
    let b = scratch.appendingPathComponent("group-spool", isDirectory: true)
    try ZaghlolDirectories.ensureExcluded(a)
    try ZaghlolDirectories.ensureExcluded(b)
    let nested = a.appendingPathComponent("db", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data([1, 2, 3]).write(to: nested.appendingPathComponent("zaghlol.db"))
    try Data([4]).write(to: b.appendingPathComponent("01HX.bin"))

    XCTAssertTrue(LocalDataWiper.wipeFiles(roots: [a, b]))

    for root in [a, b] {
      var isDirectory: ObjCBool = false
      XCTAssertTrue(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
      XCTAssertTrue(isDirectory.boolValue)
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
      XCTAssertTrue(try isExcluded(root), "\(root.lastPathComponent) lost its exclusion")
    }
  }

  // T-166: the seat keys are the only Keychain service the wipe keeps (D-55).
  func testDeleteEverythingKeepsOnlyTheSeatKeyService() {
    XCTAssertFalse(LocalDataWiper.shouldDelete(service: SeatKeyStore.service))
    XCTAssertTrue(LocalDataWiper.shouldDelete(service: "app.zaghlol.attest"))
    XCTAssertTrue(LocalDataWiper.shouldDelete(service: "app.zaghlol.spool"))
    XCTAssertTrue(LocalDataWiper.shouldDelete(service: nil))
  }
}
