import XCTest

@testable import Runner

/// T-062: the iOS spool (same contract as the Android SpoolStore). Synthetic
/// bodies only. Negative proofs (C4, at most 3): an entry cannot be renamed
/// or swapped (AAD); a write that fails before the rename leaves no entry;
/// a Keychain/cipher failure never deletes anything.
final class SpoolStoreTests: XCTestCase {
  private var dir: URL!
  private var root: URL!
  private var cipher: TestCipher!

  override func setUpWithError() throws {
    root = try makeTempDir()
    dir = root.appendingPathComponent("spool", isDirectory: true)
    cipher = TestCipher()
  }

  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

  private func store(
    limits: SpoolLimits = SpoolLimits(), files: SpoolFileOps = DefaultSpoolFileOps(),
    status: CaptureStatusStore? = nil, mono: @escaping () -> Int64 = { 1_000 }
  ) -> SpoolStore {
    SpoolStore(
      dir: dir, cipher: cipher, status: status, monoClockMs: mono, sleeper: { _ in },
      files: files, limits: limits)
  }

  @discardableResult
  private func put(_ s: SpoolStore, _ r: SpoolRecord = sampleRecord(), cls: SpoolAdmissionClass = .priority)
    throws -> String
  {
    guard case .written(let id) = try s.write(r, cls: cls) else {
      XCTFail("write was refused")
      return ""
    }
    return id
  }

  // AC: entries readable by the app after another writer wrote them; the record round-trips.
  func testEntryRoundTripsThroughASecondStoreOverTheSameDirectory() throws {
    let id = try put(store())
    let reader = store()  // another process's store: same directory, same key
    XCTAssertEqual(reader.pendingIds(), [id])
    guard case .ok(let rec) = reader.read(id) else { return XCTFail("not readable") }
    XCTAssertEqual(rec.body, "synthetic \(spoolCanary) EGP 12.50")
    XCTAssertEqual(rec.channel, "shortcut_message")
    XCTAssertEqual(rec.source, "SYNTH-BANK")
    XCTAssertEqual(rec.receivedAtMs, 1_700_000_000_000)
    XCTAssertNil(rec.simSlot)
  }

  // Encrypted at rest: neither the body, the sender nor the channel is in the file.
  func testEntryIsEncryptedAtRest() throws {
    let id = try put(store())
    let bytes = try Data(contentsOf: dir.appendingPathComponent("\(id).bin"))
    for needle in [spoolCanary, "SYNTH-BANK", "shortcut_message", "EGP"] {
      XCTAssertNil(bytes.range(of: Data(needle.utf8)), "plaintext \(needle) found on disk")
    }
    XCTAssertEqual(SpoolStore.isEntryName("\(id).bin"), true)
  }

  // AC: the container is excluded from backup (the writer excludes its own directory).
  func testSpoolDirectoryIsExcludedFromBackup() throws {
    try put(store())
    XCTAssertTrue(try isExcludedFromBackup(dir))
  }

  // Record format: Android parity and strict decoding.
  func testRecordCodecIsBigEndianVersionedAndStrict() throws {
    let r = SpoolRecord(
      channel: "wallet", source: "CIB Visa", body: "ب ٢٣", receivedAtMs: 5, simSlot: 1,
      guardInst: "cib", guardLast4: "4321", rxElapsedNs: 9, bootCount: 3)
    let data = try SpoolRecordCodec.encode(r)
    XCTAssertEqual(data.first, 1)
    XCTAssertEqual(data[1], 6)  // str8 channel length
    let back = try SpoolRecordCodec.decode(data)
    XCTAssertEqual(back.body, "ب ٢٣")
    XCTAssertEqual(back.simSlot, 1)
    XCTAssertEqual(back.guardInst, "cib")
    XCTAssertEqual(back.guardLast4, "4321")
    XCTAssertEqual(back.bootCount, 3)
    XCTAssertThrowsError(try SpoolRecordCodec.decode(data + Data([0])))  // trailing bytes
    var badVersion = data
    badVersion[0] = 2
    XCTAssertThrowsError(try SpoolRecordCodec.decode(badVersion))
    XCTAssertThrowsError(try SpoolRecordCodec.decode(data.dropLast()))
    let tooLong = sampleRecord(String(repeating: "x", count: 4_001))
    XCTAssertThrowsError(try SpoolRecordCodec.encode(tooLong))
    XCTAssertEqual("\(r)", "SpoolRecord(<redacted>)")
    XCTAssertFalse(String(reflecting: r).contains("CIB"))
  }

  // Negative proof 1: an entry can't be renamed or swapped (AAD binds the ULID).
  func testRenamedEntryIsNotAuthenticAndIsDeletedOnProof() throws {
    let s = store()
    let id = try put(s)
    let other = SpoolUlidGenerator().next()
    try FileManager.default.moveItem(
      at: dir.appendingPathComponent("\(id).bin"), to: dir.appendingPathComponent("\(other).bin"))
    let scope = SpoolDrainScope()
    guard case .deleted = s.read(other, scope: scope) else { return XCTFail("served a renamed entry") }
    XCTAssertEqual(scope.decryptDeleted, 1)
    XCTAssertEqual(s.pendingIds(), [])
  }

  // Negative proof 2: a write that fails before the rename leaves nothing readable
  // and no partial file; a young .tmp of another process is not swept.
  func testFailedWriteLeavesNoEntryAndSweepKeepsYoungTmp() throws {
    let ops = FaultyOps()
    let s = store(files: ops)
    ops.failAt = .move
    XCTAssertThrowsError(try s.write(sampleRecord(), cls: .priority))
    XCTAssertEqual(s.pendingIds(), [])
    XCTAssertEqual((try FileManager.default.contentsOfDirectory(atPath: dir.path)).count, 0)
    ops.failAt = .create
    XCTAssertThrowsError(try s.write(sampleRecord(), cls: .priority))
    XCTAssertEqual(s.pendingIds(), [])

    // A leftover of a killed write.
    let id = SpoolUlidGenerator().next()
    let tmp = dir.appendingPathComponent("\(id).bin.tmp")
    try Data([1, 2, 3]).write(to: tmp)
    XCTAssertEqual(s.sweepTmp(), 0, "a young tmp may be another process's write in flight")
    XCTAssertEqual(s.sweepTmp(now: Date().addingTimeInterval(3_600)), 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
  }

  // Negative proof 3: a Keychain/cipher failure never deletes an entry.
  func testCipherFailureNeverDeletes() throws {
    let s = store()
    let id = try put(s)
    cipher.failWith = .unavailable
    guard case .unavailable(let keyRelated) = s.read(id) else { return XCTFail("expected unavailable") }
    XCTAssertTrue(keyRelated)
    XCTAssertEqual(s.pendingIds(), [id])
    cipher.failWith = nil
    guard case .ok = s.read(id) else { return XCTFail("entry lost") }
  }

  func testTamperedEntryIsDeletedOnlyAfterTheRetryLadder() throws {
    var sleeps: [UInt32] = []
    let s = SpoolStore(dir: dir, cipher: cipher, sleeper: { sleeps.append($0) })
    let id = try put(s)
    let url = dir.appendingPathComponent("\(id).bin")
    var bytes = try Data(contentsOf: url)
    bytes[bytes.count - 1] ^= 0xFF
    try bytes.write(to: url)
    guard case .deleted = s.read(id) else { return XCTFail("tampered entry kept") }
    XCTAssertEqual(sleeps, [100, 300, 900])
  }

  func testEntryWrittenUnderAnEarlierKeyIsDeletedAtOnceAndRecorded() throws {
    let status = CaptureStatusStore(
      file: root.appendingPathComponent("status.bin"), cipher: cipher, sleeper: { _ in })
    let s = store(status: status)
    let id = try put(s)
    // A new key (different seed) created after the entry was written.
    let newCipher = TestCipher(seed: 99, createdAtMs: Int64(Date().timeIntervalSince1970 * 1000) + 60_000)
    var sleeps = 0
    let later = SpoolStore(dir: dir, cipher: newCipher, status: status, sleeper: { _ in sleeps += 1 })
    let scope = SpoolDrainScope()
    guard case .deleted = later.read(id, scope: scope) else { return XCTFail("kept") }
    XCTAssertEqual(sleeps, 0, "no ladder for a lost key")
    XCTAssertGreaterThanOrEqual(scope.keyInvalidatedAtMs, 0)
    status.recordDrain(scope)
    XCTAssertGreaterThanOrEqual(try status.read().keyInvalidatedAtMs, 0)
    XCTAssertEqual(try status.read().decryptDeleted, 1)
  }

  func testAckDeletesOnlyTheGivenIdsAndIsIdempotent() throws {
    let s = store()
    let a = try put(s)
    let b = try put(s)
    XCTAssertEqual(s.pendingIds(), [a, b].sorted())
    XCTAssertEqual(s.ack([a, "not-an-id", a]), 1)
    XCTAssertEqual(s.pendingIds(), [b])
    XCTAssertEqual(s.ack([a]), 0)
  }

  func testDrainOrderIsOldestFirst() throws {
    var t: Int64 = 1_700_000_000_000
    let gen = SpoolUlidGenerator(clock: { defer { t += 1 }; return t })
    let s = SpoolStore(dir: dir, cipher: cipher, ids: gen, sleeper: { _ in })
    let ids = try (0..<5).map { _ in try put(s) }
    XCTAssertEqual(s.pendingIds(), ids)
  }

  func testFullSpoolRefusesTheNewMessageAndEvictsNothing() throws {
    let status = CaptureStatusStore(
      file: root.appendingPathComponent("status.bin"), cipher: cipher, sleeper: { _ in })
    var limits = SpoolLimits()
    limits.maxEntries = 2
    let s = store(limits: limits, status: status)
    let a = try put(s)
    let b = try put(s)
    XCTAssertEqual(try s.write(sampleRecord(), cls: .priority), .refused(.full))
    XCTAssertEqual(s.pendingIds(), [a, b].sorted())
    XCTAssertEqual(try status.read().refusedFull, 1)
  }

  func testByteCapRefuses() throws {
    var limits = SpoolLimits()
    limits.maxBytes = 120
    let s = store(limits: limits)
    try put(s, sampleRecord("a"))
    XCTAssertEqual(try s.write(sampleRecord(String(repeating: "b", count: 200)), cls: .priority), .refused(.full))
  }

  func testSmsReserveKeepsRoomForOtherChannels() throws {
    var limits = SpoolLimits()
    limits.maxEntries = 5
    limits.smsMaxEntries = 2
    let s = store(limits: limits)
    try put(s, sampleRecord(channel: "sms"))
    try put(s, sampleRecord(channel: "sms"))
    XCTAssertEqual(try s.write(sampleRecord(channel: "sms"), cls: .priority), .refused(.smsReserve))
    XCTAssertNoThrow(try put(s, sampleRecord(channel: "wallet")))
  }

  func testGenericBudget() throws {
    var limits = SpoolLimits()
    limits.genericMaxEntries = 2
    let s = store(limits: limits)
    try put(s, cls: .generic)
    try put(s, cls: .generic)
    XCTAssertEqual(try s.write(sampleRecord(), cls: .generic), .refused(.genericBudget))
    XCTAssertNoThrow(try put(s, cls: .priority), "registry/user keeps use the full caps")
  }

  func testGenericRateIsPerWindow() throws {
    var limits = SpoolLimits()
    limits.genericPerWindow = 2
    var now: Int64 = 1_000
    let s = store(limits: limits, mono: { now })
    try put(s, cls: .generic)
    try put(s, cls: .generic)
    XCTAssertEqual(try s.write(sampleRecord(), cls: .generic), .refused(.genericRate))
    now += 61_000
    XCTAssertNoThrow(try put(s, cls: .generic))
  }

  func testHoldMovesAnEntryAsideAndReleaseOnANewVersion() throws {
    let s = store()
    let id = try put(s)
    XCTAssertTrue(try s.hold(id))
    XCTAssertEqual(s.pendingIds(), [])
    XCTAssertEqual(s.heldCount(), 1)
    XCTAssertFalse(try s.hold(id), "already moved")
    // Held entries still count towards the caps.
    var limits = SpoolLimits()
    limits.maxEntries = 1
    XCTAssertEqual(try store(limits: limits).write(sampleRecord(), cls: .priority), .refused(.full))
    // First start of the version records it; same version releases nothing.
    XCTAssertEqual(s.releaseHeldIfVersionChanged(appVersion: "10"), 1)  // no version file yet: release
    XCTAssertEqual(s.pendingIds(), [id])
    XCTAssertTrue(try s.hold(id))
    XCTAssertEqual(s.releaseHeldIfVersionChanged(appVersion: "10"), 0)
    XCTAssertEqual(s.releaseHeldIfVersionChanged(appVersion: "11"), 1)
    guard case .ok = s.read(id) else { return XCTFail("released entry unreadable (AAD must still match)") }
  }

  func testHeldAreCappedAtFifty() throws {
    let s = store()
    var limits = SpoolLimits()
    limits.maxHeld = 1
    let capped = store(limits: limits)
    let a = try put(s)
    let b = try put(s)
    XCTAssertTrue(try capped.hold(a))
    XCTAssertFalse(try capped.hold(b), "beyond the held cap the entry stays pending")
    XCTAssertEqual(capped.pendingIds(), [b])
  }

  func testForeignFilesAreIgnored() throws {
    let s = store()
    let id = try put(s)
    try Data([0]).write(to: dir.appendingPathComponent("notes.txt"))
    try Data([0]).write(to: dir.appendingPathComponent(".DS_Store"))
    XCTAssertEqual(s.pendingIds(), [id])
    XCTAssertEqual(s.pendingCountOrNil(), 1)
  }

  func testUlidIsMonotonicAndStrictlyValidated() {
    let g = SpoolUlidGenerator(clock: { 42 })
    let a = g.next(), b = g.next(), c = g.next()
    XCTAssertTrue(a < b && b < c)
    XCTAssertTrue(SpoolUlidGenerator.isValid(a))
    XCTAssertFalse(SpoolUlidGenerator.isValid("../../etc/passwd"))
    XCTAssertFalse(SpoolUlidGenerator.isValid(String(repeating: "I", count: 26)))  // I is not Crockford
    XCTAssertEqual(SpoolUlidGenerator.timeMs(a), 42)
  }
}
