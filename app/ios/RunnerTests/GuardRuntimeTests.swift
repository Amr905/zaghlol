import CryptoKit
import XCTest

@testable import Runner

/// T-061: config reader errors and modes, the encrypted user part, the
/// runtime's caching and failure rules, Apple Pay card mapping, rate limit,
/// and the "never logs" source scan. Synthetic data only. The Keychain is
/// replaced by an in-memory key provider (the real item attributes are the
/// T-015 `DbKeyKeychain` ones, tested in SecretStoreTests).
final class GuardRuntimeTests: XCTestCase {
  // MARK: Fakes

  private final class MemoryKeys: GuardKeyProvider {
    var key: SymmetricKey? = SymmetricKey(size: .bits256)
    var unavailable = false
    func existingKey() -> GuardKeyLookup {
      if unavailable { return .unavailable }
      if let k = key { return .found(k) }
      return .missing
    }
    func keyCreatingIfNeeded() throws -> SymmetricKey {
      if unavailable { throw GuardCipherError.unavailable }
      if let k = key { return k }
      let k = SymmetricKey(size: .bits256)
      key = k
      return k
    }
  }

  /// Fails the chosen step; everything else is the real thing.
  private final class FaultyOps: GuardFileOps {
    private let real = DefaultGuardFileOps()
    var failWrite = false
    var failRename = false
    var failRead = false
    func readBounded(_ url: URL, max: Int) throws -> Data? {
      if failRead { throw GuardFileOpsError() }
      return try real.readBounded(url, max: max)
    }
    func ensureDir(_ url: URL) throws { try real.ensureDir(url) }
    func writeAndSync(_ url: URL, data: Data) throws {
      if failWrite { throw GuardFileOpsError() }
      try real.writeAndSync(url, data: data)
    }
    func atomicReplace(from: URL, to: URL) throws {
      if failRename { throw GuardFileOpsError() }
      try real.atomicReplace(from: from, to: to)
    }
    func syncDir(_ url: URL) { real.syncDir(url) }
    func delete(_ url: URL) { real.delete(url) }
  }

  private var dir: URL!
  private let keys = MemoryKeys()

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "guard-test-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  private func makeStore(ops: GuardFileOps = DefaultGuardFileOps()) -> GuardUserConfigStore {
    GuardUserConfigStore(dir: dir, cipher: AesGcmGuardUserCipher(keys: keys), ops: ops)
  }

  private func makeRuntime(
    store: GuardUserConfigStore? = nil, base: @escaping () throws -> Data = { try GuardFixtures.t1Base },
    clock: @escaping () -> Int64 = { 0 }
  ) -> GuardRuntime {
    GuardRuntime(loadBase: base, store: store ?? makeStore(), clockMs: clock)
  }

  private func userJSON(ignore: String = "", senders: String = "") -> Data {
    Data("{\"v\":1,\"baseRegistryVersion\":3,\"ignore\":[\(ignore)],\"userSenders\":[\(senders)]}".utf8)
  }

  private func form(_ d: GuardDecision) -> String { d.goldenForm }

  // MARK: Reader

  private func baseText() throws -> String { String(decoding: try GuardFixtures.t1Base, as: UTF8.self) }

  func testEveryReaderErrorCodeIsReportedWithAPathOnly() throws {
    let base = try baseText()
    func code(_ text: String) -> GuardConfigErrorCode? {
      GuardConfig.parse(base: Data(text.utf8), user: nil).baseError?.code
    }
    XCTAssertEqual(code("{\"v\":3}"), .badVersion)
    XCTAssertEqual(code("[]"), .wrongType)
    XCTAssertEqual(code("{\"v\":4"), .invalidJson)
    XCTAssertEqual(code("{\"v\":4}"), .missingKey)
    XCTAssertEqual(code(base.replacingOccurrences(of: "\"registryVersion\": 3,", with: "\"registryVersion\": 3, \"extra\": 1,")), .unknownKey)
    XCTAssertEqual(code(base.replacingOccurrences(of: "\"registryVersion\": 3", with: "\"registryVersion\": \"3\"")), .wrongType)
    XCTAssertEqual(code(base.replacingOccurrences(of: "\"^cib-(?:egy|alert)$\"", with: "\"(\"")), .badRegex)
    XCTAssertEqual(code(base.replacingOccurrences(of: "\"perSenderPerMin\": 20", with: "\"perSenderPerMin\": 0")), .badValue)
    let tooBig = GuardConfig.parse(base: Data(count: GuardConfig.maxBaseBytes + 1), user: nil)
    XCTAssertEqual(tooBig.baseError?.code, .tooLarge)
    let notUtf8 = GuardConfig.parse(base: Data([0xFF, 0xFE, 0x7B]), user: nil)
    XCTAssertEqual(notUtf8.baseError?.code, .invalidUtf8)
    XCTAssertEqual(notUtf8.mode, .invalid)
    // The error text never contains a value.
    let bad = GuardConfig.parse(base: Data("{\"v\":4,\"registryVersion\":\"ZG_CANARY_7731\"}".utf8), user: nil)
    XCTAssertFalse("\(bad)".contains("ZG_CANARY_7731"))
  }

  func testUserPartErrorsFallBackToBaseOnlyAndTooManyIsReported() throws {
    let base = try GuardFixtures.t1Base
    let badChannel = userJSON(senders: "{\"value\":\"x1\",\"ch\":\"share\"}")
    let r = GuardConfig.parse(base: base, user: badChannel)
    XCTAssertEqual(r.mode, .baseOnly)
    XCTAssertTrue(r.userFailed)
    XCTAssertEqual(r.userError?.code, .badValue)
    let rule = "{\"inst\":\"cib\",\"last4\":null,\"ch\":\"sms\"}"
    let many = userJSON(ignore: Array(repeating: rule, count: GuardConfig.maxIgnoreRules + 1).joined(separator: ","))
    XCTAssertEqual(GuardConfig.validateUser(many)?.code, .tooMany)
    XCTAssertNil(GuardConfig.validateUser(userJSON(ignore: rule)))
    let unreadable = GuardConfig.parse(base: base, user: nil, userUnreadable: true)
    XCTAssertEqual(unreadable.mode, .baseOnly)
    XCTAssertTrue(unreadable.userFailed)
  }

  func testStrictJsonRejectsWhatDartRejects() {
    for bad in ["{\"v\":1,}", "{'v':1}", "{\"v\":01}", "{\"v\":NaN}", "{\"v\":1} x", "{\"a\":\"\u{01}\"}", "// c\n{}"] {
      XCTAssertThrowsError(try StrictJson.parse(Array(bad.utf16)), "case rejected")
    }
    let deep = String(repeating: "[", count: 17) + String(repeating: "]", count: 17)
    XCTAssertThrowsError(try StrictJson.parse(Array(deep.utf16)))
    // Duplicate key: last value wins, first position kept.
    let v = try? StrictJson.parse(Array("{\"a\":1,\"b\":2,\"a\":3}".utf16)).object()
    XCTAssertEqual(v?.keys, ["a", "b"])
    if case .int(let n)? = v?.values["a"] { XCTAssertEqual(n, 3) } else { XCTFail("a is not an int") }
    // A number with a fraction is a double, so an integer field rejects it.
    if case .double? = try? StrictJson.parse(Array("4.0".utf16)) {} else { XCTFail("4.0 is not a double") }
  }

  // MARK: User part on disk

  func testUserPartRoundTripsAndTheFileHoldsNoPlaintext() throws {
    let rt = makeRuntime()
    let json = userJSON(ignore: "{\"inst\":\"nbe\",\"last4\":\"7731\",\"ch\":\"sms\"}", senders: "{\"value\":\"zgcanary\",\"ch\":\"sms\"}")
    try rt.writeUser(json)
    XCTAssertEqual(rt.state().mode, .full)
    XCTAssertEqual(rt.state().userState, .ok)
    // The card is now ignored, the registry card next to it is not.
    XCTAssertEqual(form(rt.decide(channel: .shortcutMessage, source: "NBE", body: "Purchase EGP 10.00 card **7731")), "drop|ignored_card")
    // A fresh runtime over the same directory reads the file back.
    let again = makeRuntime()
    XCTAssertEqual(again.state().userState, .ok)
    // Ciphertext on disk: no institution code, last-4 or JSON key in UTF-8 or UTF-16.
    let onDisk = try Data(contentsOf: dir.appendingPathComponent(GuardUserConfigStore.fileName))
    for needle in ["7731", "nbe", "ignore", "zgcanary", "userSenders"] {
      XCTAssertNil(onDisk.range(of: Data(needle.utf8)))
      XCTAssertNil(onDisk.range(of: Data(needle.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })))
    }
    // The directory is excluded from backup and holds no temp file.
    let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
    XCTAssertEqual(values.isExcludedFromBackup, true)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [GuardUserConfigStore.fileName])
  }

  func testTamperedFileIsBaseOnlyUnreadableAndKept() throws {
    try makeRuntime().writeUser(userJSON(ignore: "{\"inst\":\"bm\",\"last4\":null,\"ch\":\"sms\"}"))
    let file = dir.appendingPathComponent(GuardUserConfigStore.fileName)
    var bytes = try Data(contentsOf: file)
    bytes[bytes.count - 1] ^= 0x01
    try bytes.write(to: file)
    let rt = makeRuntime()
    XCTAssertEqual(rt.state().mode, .baseOnly)
    XCTAssertEqual(rt.state().userState, .unreadable)
    // Registry senders are still kept (NFR-REL-01).
    XCTAssertEqual(form(rt.decide(channel: .shortcutMessage, source: "banquemisr", body: "Purchase EGP 10.00")).hasPrefix("keep|registry|bm"), true)
    // Kept, never deleted.
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    // The next successful write heals it.
    try rt.writeUser(userJSON())
    XCTAssertEqual(rt.state().userState, .ok)
  }

  func testAFileWrittenWithAnotherAadOrKeyIsUnreadable() throws {
    try makeRuntime().writeUser(userJSON())
    keys.key = SymmetricKey(size: .bits256)  // a different key now
    XCTAssertEqual(makeRuntime().state().userState, .unreadable)
    // Wrong AAD with the right key.
    let cipher = AesGcmGuardUserCipher(keys: keys)
    let wrong = try cipher.encrypt(userJSON(), aad: Data("zaghlol.guard.v1|base".utf8))
    try wrong.write(to: dir.appendingPathComponent(GuardUserConfigStore.fileName))
    XCTAssertEqual(makeRuntime().state().userState, .unreadable)
  }

  func testAKeyThatNoLongerExistsMeansUnreadableNotAMintedKey() throws {
    try makeRuntime().writeUser(userJSON())
    keys.key = nil
    XCTAssertEqual(makeRuntime().state().userState, .unreadable)
    XCTAssertNil(keys.key, "a read must never create a key")
  }

  func testATransientKeychainErrorIsNotCachedAndHeals() throws {
    try makeRuntime().writeUser(userJSON(ignore: "{\"inst\":\"cib\",\"last4\":null,\"ch\":\"sms\"}"))
    keys.unavailable = true
    let rt = makeRuntime()
    XCTAssertEqual(rt.state().userState, .retry)
    XCTAssertEqual(rt.state().mode, .baseOnly)
    keys.unavailable = false
    XCTAssertEqual(rt.state().userState, .ok)
    XCTAssertEqual(rt.state().mode, .full)
  }

  func testAnInvalidWriteKeepsTheOldFileAndTheOldRules() throws {
    let rt = makeRuntime()
    try rt.writeUser(userJSON(ignore: "{\"inst\":\"cib\",\"last4\":null,\"ch\":\"sms\"}"))
    let file = dir.appendingPathComponent(GuardUserConfigStore.fileName)
    let before = try Data(contentsOf: file)
    XCTAssertThrowsError(try rt.writeUser(Data("{\"v\":1}".utf8))) { e in
      XCTAssertEqual((e as? GuardConfigWriteError)?.code, .configInvalid)
    }
    XCTAssertThrowsError(try rt.writeUser(Data(count: GuardConfig.maxUserBytes + 1))) { e in
      XCTAssertEqual((e as? GuardConfigWriteError)?.detail?.code, .tooLarge)
    }
    XCTAssertEqual(try Data(contentsOf: file), before)
    XCTAssertEqual(form(rt.decide(channel: .shortcutMessage, source: "CIB", body: "Purchase EGP 10.00")), "drop|ignored_institution")
  }

  func testAFailureAtEachWriteStepKeepsTheOldFileAndLeavesNoTemp() throws {
    let ops = FaultyOps()
    let rt = makeRuntime(store: makeStore(ops: ops))
    try rt.writeUser(userJSON(ignore: "{\"inst\":\"cib\",\"last4\":null,\"ch\":\"sms\"}"))
    let file = dir.appendingPathComponent(GuardUserConfigStore.fileName)
    let before = try Data(contentsOf: file)
    for step in 0..<2 {
      ops.failWrite = step == 0
      ops.failRename = step == 1
      XCTAssertThrowsError(try rt.writeUser(userJSON())) { e in
        XCTAssertEqual((e as? GuardConfigWriteError)?.code, .ioError)
      }
      XCTAssertEqual(try Data(contentsOf: file), before)
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [GuardUserConfigStore.fileName])
    }
    XCTAssertEqual(rt.state().userState, .ok)
    XCTAssertEqual(form(rt.decide(channel: .shortcutMessage, source: "CIB", body: "Purchase EGP 10.00")), "drop|ignored_institution")
  }

  func testAReadFailureIsTransientNotUnreadable() throws {
    try makeRuntime().writeUser(userJSON())
    let ops = FaultyOps()
    ops.failRead = true
    let rt = makeRuntime(store: makeStore(ops: ops))
    XCTAssertEqual(rt.state().userState, .retry)
    ops.failRead = false
    XCTAssertEqual(rt.state().userState, .ok)
  }

  // MARK: Base part

  func testAnInvalidBaseDropsEverythingAndIsRetriedOnTheNextMessage() throws {
    var calls = 0
    var good = false
    let rt = makeRuntime(base: {
      calls += 1
      if good { return try GuardFixtures.t1Base }
      throw GuardBaseSource.Missing()
    })
    XCTAssertEqual(rt.state().mode, .invalid)
    XCTAssertEqual(form(rt.decide(channel: .shortcutMessage, source: "NBE", body: "Purchase EGP 10.00")), "drop|config_invalid")
    good = true
    XCTAssertEqual(form(rt.decide(channel: .shortcutMessage, source: "NBE", body: "Purchase EGP 10.00")), "keep|registry|nbe|~")
    XCTAssertGreaterThanOrEqual(calls, 2)
    let callsAfterGood = calls
    _ = rt.decide(channel: .shortcutMessage, source: "NBE", body: "Purchase EGP 10.00")
    XCTAssertEqual(calls, callsAfterGood, "a valid base is cached")
  }

  func testAnOversizedBaseIsCutAtTheCapAndReportedTooLarge() throws {
    let big = dir.appendingPathComponent("big.json")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data(repeating: 0x20, count: GuardConfig.maxBaseBytes + 5000).write(to: big)
    let read = try GuardBaseSource.readBounded(big)
    XCTAssertEqual(read.count, GuardConfig.maxBaseBytes + 1)
    XCTAssertEqual(GuardConfig.parse(base: read, user: nil).baseError?.code, .tooLarge)
  }

  func testTheBaseMirrorIsWrittenOnlyWhenItDiffersAndReadsBack() throws {
    let base = try GuardFixtures.t1Base
    XCTAssertTrue(GuardBaseSource.mirror(base, intoGuardDir: dir))
    XCTAssertFalse(GuardBaseSource.mirror(base, intoGuardDir: dir))
    XCTAssertEqual(try GuardBaseSource.readMirror(guardDir: dir), base)
    XCTAssertTrue(GuardBaseSource.mirror(base + Data(" ".utf8), intoGuardDir: dir))
  }

  // MARK: Decisions

  /// Negative proof: a message from a sender the registry and the user do not
  /// know, and a personal number, leave nothing: a drop, and no file or
  /// directory is created by the decision.
  func testANonRegistryPersonalMessageLeavesNothing() throws {
    let rt = makeRuntime()
    try rt.writeUser(userJSON(senders: "{\"value\":\"+201000000009\",\"ch\":\"sms\"}"))
    let before = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    let d = GuardConfig.parse(base: try GuardFixtures.t1Base, user: userJSON(senders: "{\"value\":\"+201000000009\",\"ch\":\"sms\"}"))
    let g = CaptureGuard(config: d.config)
    XCTAssertEqual(g.decide(channel: "sms", source: "+201000000009", body: "تعالى بكرة الساعة ٥"), .drop(.notFinancial))
    XCTAssertEqual(g.decide(channel: "sms", source: "+201000000001", body: "see you at 5"), .drop(.notFinancial))
    XCTAssertEqual(g.decide(channel: "sms", source: "SOMESHOP", body: "50% off today"), .drop(.notFinancial))
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), before)
    // A financial-looking body from the user's own number is still kept.
    XCTAssertEqual(g.decide(channel: "sms", source: "+201000000009", body: "paid EGP 50.00 for lunch").goldenForm, "keep|user|~|~")
  }

  func testApplePayCardNamesMapToTheInstitutionAndKeepIsGenericOtherwise() throws {
    let rt = makeRuntime()
    XCTAssertTrue(form(rt.decide(channel: .applePay, source: "CIB Visa", body: "EGP 450.00 at Shop")).hasPrefix("keep|registry|cib"))
    XCTAssertTrue(form(rt.decide(channel: .applePay, source: "Banque Misr Gold", body: "EGP 10.00")).hasPrefix("keep|registry|bm"))
    XCTAssertTrue(form(rt.decide(channel: .applePay, source: "بنك مصر بلاتينيوم", body: "EGP 10.00")).hasPrefix("keep|registry|bm"))
    XCTAssertEqual(form(rt.decide(channel: .applePay, source: "My Card", body: "EGP 10.00")), "keep|generic|~|~")
  }

  func testRuntimeRateLimitsKeepsPerSenderAndNeverDrops() throws {
    var now: Int64 = 0
    let rt = makeRuntime(clock: { now })
    var limited = 0
    for _ in 0..<25 {
      if rt.decide(channel: .shortcutMessage, source: "NBE", body: "Purchase EGP 10.00") == .drop(.rateLimited) { limited += 1 }
    }
    XCTAssertEqual(limited, 5)
    now = 61_000
    XCTAssertEqual(form(rt.decide(channel: .shortcutMessage, source: "NBE", body: "Purchase EGP 10.00")), "keep|registry|nbe|~")
    // OTPs are drops and are not counted.
    XCTAssertTrue(form(rt.decide(channel: .shortcutMessage, source: "NBE", body: "Your OTP is 482913")).hasPrefix("drop|otp_or_promo"))
  }

  func testLimiterWindowBoundaryAndLRU() {
    let l = SenderRateLimiter(perSenderPerMin: 2, maxKeys: 2)
    let keep = GuardDecision.keep(kind: .generic, inst: nil, last4: nil)
    XCTAssertEqual(l.apply(keep, channel: "sms", source: "A", nowMs: 0), keep)
    XCTAssertEqual(l.apply(keep, channel: "sms", source: "a", nowMs: 1), keep)
    XCTAssertEqual(l.apply(keep, channel: "sms", source: "A", nowMs: 2), .drop(.rateLimited))
    // Exactly one window after the first keep, that keep has expired.
    XCTAssertEqual(l.apply(keep, channel: "sms", source: "A", nowMs: 60_000), keep)
    _ = l.apply(keep, channel: "sms", source: "B", nowMs: 60_001)
    _ = l.apply(keep, channel: "sms", source: "C", nowMs: 60_002)
    XCTAssertEqual(l.trackedKeys, 2)
  }

  // MARK: Spool key provider

  private final class FakeSlot: SecretSlotStore {
    var status: SecretStatusMsg = .notFound
    var value: Data?
    var created = 0
    func read() -> SlotRead { SlotRead(status: status, value: status == .found ? value : nil, attempts: 1) }
    func createIfAbsent(_ candidate: Data) throws -> Data {
      if status != .notFound { throw KeyStoreFailure() }
      created += 1
      status = .found
      value = candidate
      return candidate
    }
    func delete() throws { status = .notFound; value = nil }
  }

  func testSpoolKeyProviderMapsSlotStatesAndCreatesOnlyWhenMissing() throws {
    let slot = FakeSlot()
    let provider = KeychainSpoolKeyProvider(slot: slot)
    if case .missing = provider.existingKey() {} else { XCTFail("a new slot must be missing") }
    XCTAssertEqual(slot.created, 0, "a read never creates")
    let first = try provider.keyCreatingIfNeeded()
    let second = try provider.keyCreatingIfNeeded()
    XCTAssertEqual(slot.created, 1)
    XCTAssertEqual(first.withUnsafeBytes { Data($0) }, second.withUnsafeBytes { Data($0) })
    XCTAssertEqual(slot.value?.count, 32)
    for status in [SecretStatusMsg.unusable, .unavailable] {
      let bad = FakeSlot()
      bad.status = status
      let p = KeychainSpoolKeyProvider(slot: bad)
      if case .unavailable = p.existingKey() {} else { XCTFail("must not be treated as missing") }
      XCTAssertThrowsError(try p.keyCreatingIfNeeded())
      XCTAssertEqual(bad.created, 0, "an unusable or unknown key is never overwritten")
    }
    XCTAssertEqual(KeychainSpoolKeyProvider.account, "spool_key_v1")
  }

  // MARK: Never logs

  func testDescriptionsAndErrorsNeverCarryMessageContent() throws {
    let canary = "ZG_CANARY_7731"
    let cfg = GuardConfig.parse(base: try GuardFixtures.t1Base, user: userJSON(ignore: "{\"inst\":\"nbe\",\"last4\":\"7731\",\"ch\":\"sms\"}"))
    let d = CaptureGuard(config: cfg.config).decide(channel: "sms", source: "NBE", body: "\(canary) purchase EGP 10.00 card **4567")
    let texts = ["\(d)", "\(cfg)", "\(String(describing: cfg.config))", "\(CaptureGuard(config: cfg.config))",
      "\(GuardDecision.keep(kind: .registry, inst: "nbe", last4: "7731"))", "\(GuardIgnoreKey(inst: "nbe", last4: "7731", ch: .sms))"]
    for t in texts {
      XCTAssertFalse(t.contains(canary) || t.contains("7731") || t.contains("4567"))
    }
  }

  func testGuardSourcesNeverPrintOrLog() throws {
    var url = URL(fileURLWithPath: #filePath)
    url = url.deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Runner/Guard", isDirectory: true)
    let names = try FileManager.default.contentsOfDirectory(atPath: url.path).filter { $0.hasSuffix(".swift") }
    XCTAssertGreaterThanOrEqual(names.count, 9)
    let forbidden = ["print(", "debugPrint(", "NSLog(", "os_log(", "Logger(", "dump(", "OSLog", "fputs(", "FileHandle.standardError"]
    for name in names {
      let text = try String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
      for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
        for f in forbidden { XCTAssertFalse(line.contains(f), "\(name) uses \(f)") }
      }
    }
  }
}
