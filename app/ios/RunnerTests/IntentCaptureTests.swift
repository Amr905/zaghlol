import CryptoKit
import Flutter
import Security
import XCTest

@testable import Runner

/// T-063: the App Intents' work (Guard, encrypted spool write, then the
/// headless engine), the fixed dialogs, the per-intent run times, the
/// `writeGuardConfig` path into the intents' Guard, one shared spool key for
/// the Guard (FU-196) and the re-read before a delete on proof (062-1).
/// Synthetic text only.
final class IntentCaptureTests: XCTestCase {
  // MARK: Fakes

  private final class MemoryKeys: GuardKeyProvider {
    let key = SymmetricKey(size: .bits256)
    func existingKey() -> GuardKeyLookup { .found(key) }
    func keyCreatingIfNeeded() throws -> SymmetricKey { key }
  }

  /// One in-memory Keychain item, shared by every `SpoolKeychain` over it
  /// (as two processes share the real item).
  private final class FakeKeychain: SpoolKeychainClient {
    var item: [String: Any]?
    var copyStatus: OSStatus?
    var adds = 0
    var queries: [[String: Any]] = []
    func copyMatching(_ query: [String: Any]) -> (OSStatus, [String: Any]?) {
      queries.append(query)
      if let s = copyStatus { return (s, nil) }
      guard let item = item else { return (errSecItemNotFound, nil) }
      return (errSecSuccess, item)
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
      adds += 1
      queries.append(attributes)
      if item != nil { return errSecDuplicateItem }
      item = [
        kSecValueData as String: attributes[kSecValueData as String] as Any,
        kSecAttrCreationDate as String: Date(),
      ]
      return errSecSuccess
    }
    func delete(_ query: [String: Any]) -> OSStatus {
      item = nil
      return errSecSuccess
    }
  }

  private let group = "TEAM123.app.zaghlol.dev.shared"

  private func spoolKeychain(_ fake: FakeKeychain) -> SpoolKeychain {
    SpoolKeychain(client: fake, accessGroup: group, retryDelaysMs: [1, 1, 1], sleeper: { _ in })
  }

  // MARK: Setup

  private var root: URL!
  private var spool: SpoolRuntime!
  private var guardRuntime: GuardRuntime!
  private var runs: IntentRunLog!
  private var engineRuns = 0
  private var engineAnswer = false

  override func setUpWithError() throws {
    root = try makeTempDir()
    spool = makeSpool(files: DefaultSpoolFileOps())
    guardRuntime = GuardRuntime(
      loadBase: { try GuardFixtures.t1Base },
      store: GuardUserConfigStore(
        dir: root.appendingPathComponent("guard"), cipher: AesGcmGuardUserCipher(keys: MemoryKeys())),
      clockMs: { 0 })
    runs = IntentRunLog(
      file: root.appendingPathComponent("capture/intent_runs.bin"), cipher: TestCipher())
    engineRuns = 0
    engineAnswer = false
  }

  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

  private func makeSpool(files: SpoolFileOps, cipher: SpoolCipher = TestCipher()) -> SpoolRuntime {
    let status = CaptureStatusStore(
      file: root.appendingPathComponent("capture/status.bin"), cipher: cipher, sleeper: { _ in })
    let store = SpoolStore(
      dir: root.appendingPathComponent("spool"), cipher: cipher, status: status, sleeper: { _ in },
      files: files)
    return SpoolRuntime(store: store, status: status, cipher: KeychainSpoolCipher())
  }

  private func capture(_ runtime: SpoolRuntime? = nil) -> IntentCapture {
    let s = runtime ?? spool!
    return IntentCapture(
      guardRuntime: { self.guardRuntime }, spool: { s }, runs: { self.runs },
      headless: {
        self.engineRuns += 1
        return self.engineAnswer
      }, wallClockMs: { 1_700_000_000_000 })
  }

  private func spoolFiles() -> [String] {
    let dir = root.appendingPathComponent("spool")
    return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
  }

  private func onlyRecord() throws -> SpoolRecord {
    let ids = spool.store.pendingIds()
    XCTAssertEqual(ids.count, 1)
    guard case .ok(let r) = spool.store.read(try XCTUnwrap(ids.first)) else {
      throw XCTSkip("unreadable")
    }
    return r
  }

  // MARK: AC1 - an intent run creates a spool entry without the app UI

  func testMessageIntentWritesAnEncryptedEntryThenTriesTheEngine() async throws {
    let body = "synthetic purchase EGP 12.50 card **1234 \(spoolCanary)"
    let dialog = await capture().logMessage(message: body, sender: "  NBE ")
    XCTAssertEqual(dialog, .savedForLater, "the engine did not finish: saved for later")
    XCTAssertEqual(engineRuns, 1)
    let r = try onlyRecord()
    XCTAssertEqual(r.channel, "shortcut_message")
    XCTAssertEqual(r.source, "NBE")
    XCTAssertEqual(r.body, body)
    XCTAssertEqual(r.guardInst, "nbe")
    XCTAssertEqual(r.guardLast4, "1234")
    let file = root.appendingPathComponent("spool/\(spool.store.pendingIds()[0]).bin")
    let raw = try Data(contentsOf: file)
    XCTAssertNil(raw.range(of: Data(spoolCanary.utf8)), "the entry is encrypted")

    engineAnswer = true
    let second = await capture().logMessage(message: "another \(spoolCanary) EGP 3.00", sender: nil)
    XCTAssertEqual(second, .saved)
    XCTAssertEqual(spool.store.pendingIds().count, 2, "the fake engine acks nothing")
    let sources = spool.store.pendingIds().compactMap { id -> String? in
      if case .ok(let rec) = spool.store.read(id) { return rec.source }
      return nil
    }
    XCTAssertTrue(sources.contains(IntentCapture.noSender))
  }

  // MARK: Negative proof 1 - a non-financial message leaves nothing

  func testANonFinancialMessageLeavesNoSpoolEntryAndStartsNoEngine() async throws {
    for body in ["Your OTP is 482913 \(spoolCanary)", "   "] {
      let dialog = await capture().logMessage(message: body, sender: "NBE")
      XCTAssertEqual(dialog, .notFinancial)
    }
    XCTAssertEqual(spoolFiles(), [], "no entry, no .tmp")
    XCTAssertEqual(engineRuns, 0)
    XCTAssertNotNil(runs.read().messageAtMs, "the run itself is still recorded for the checker")
  }

  // MARK: Negative proof 2 - a failed write starts no engine and leaves no partial entry

  func testASpoolWriteFailureStartsNoEngineAndLeavesNoPartialEntry() async throws {
    for step in [FaultyOps.Step.create, .move] {
      let ops = FaultyOps()
      ops.failAt = step
      let dialog = await capture(makeSpool(files: ops)).logMessage(
        message: "synthetic purchase EGP 12.50 \(spoolCanary)", sender: "NBE")
      XCTAssertEqual(dialog, .notSaved)
    }
    let locked = TestCipher()
    locked.failWith = .unavailable
    let dialog = await capture(makeSpool(files: DefaultSpoolFileOps(), cipher: locked)).logWallet(
      amount: "EGP 450.00", merchant: "Synthetic Shop", card: "CIB Visa")
    XCTAssertEqual(dialog, .notSaved)
    XCTAssertEqual(spoolFiles(), [], "no .bin and no .tmp left behind")
    XCTAssertEqual(engineRuns, 0)
  }

  // MARK: writeGuardConfig reaches the intents' Guard

  func testWalletIntentMapsTheCardAndAWrittenIgnoreRuleReachesIt() async throws {
    let host = IosCaptureHost(
      runtime: { self.spool }, claim: SpoolClaim(), scheduleRefresh: {},
      guardRuntime: { self.guardRuntime })
    let before = await capture().logWallet(
      amount: " EGP 450.00 ", merchant: "Synthetic Shop", card: "NBE Visa")
    XCTAssertEqual(before, .savedForLater)
    let r = try onlyRecord()
    XCTAssertEqual(r.channel, "apple_pay")
    XCTAssertEqual(r.source, "NBE Visa")
    XCTAssertEqual(r.body, "EGP 450.00\nSynthetic Shop")
    XCTAssertEqual(r.guardInst, "nbe")

    // The user ignores NBE on Apple Pay (t1 user part): the next run drops it.
    try host.writeGuardConfig(userConfigJson: FlutterStandardTypedData(bytes: try GuardFixtures.t1User))
    XCTAssertEqual(try host.getSpoolStatus().guardState, .full)
    let after = await capture().logWallet(amount: "EGP 450.00", merchant: "Synthetic Shop", card: "NBE Visa")
    XCTAssertEqual(after, .notFinancial)
    XCTAssertEqual(spool.store.pendingIds().count, 1)

    XCTAssertThrowsError(
      try host.writeGuardConfig(userConfigJson: FlutterStandardTypedData(bytes: Data("{\(spoolCanary)".utf8)))
    ) {
      let e = $0 as? CaptureApiError
      XCTAssertEqual(e?.code, "CONFIG_INVALID")
      XCTAssertNil(e?.message)
    }
    let none = IosCaptureHost(runtime: { self.spool }, claim: SpoolClaim(), guardRuntime: { nil })
    XCTAssertThrowsError(try none.writeGuardConfig(userConfigJson: FlutterStandardTypedData(bytes: Data()))) {
      XCTAssertEqual(($0 as? CaptureApiError)?.code, "NOT_AVAILABLE")
    }
  }

  // MARK: AC2 - dialogs never contain amounts

  private static func catalog(_ name: String) throws -> [String: Any] {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    url.appendPathComponent("Runner/\(name)")
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    return try XCTUnwrap(json?["strings"] as? [String: Any])
  }

  private static func value(_ entry: Any?, _ lang: String) -> String? {
    let l = (entry as? [String: Any])?["localizations"] as? [String: Any]
    let unit = (l?[lang] as? [String: Any])?["stringUnit"] as? [String: Any]
    return unit?["value"] as? String
  }

  func testDialogsAreFixedCatalogStringsWithoutDigitsOrArguments() throws {
    let strings = try Self.catalog("Localizable.xcstrings")
    let digits = CharacterSet(charactersIn: "0123456789٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹%@{}")
    for key in IntentDialogKey.allCases {
      XCTAssertEqual(key.resource.key, key.rawValue)
      for lang in ["ar", "en"] {
        let v = try XCTUnwrap(Self.value(strings[key.rawValue], lang), "\(key.rawValue) \(lang)")
        XCTAssertFalse(v.isEmpty)
        XCTAssertNil(v.rangeOfCharacter(from: digits), "\(key.rawValue) \(lang) must hold no number or argument")
      }
    }
    XCTAssertEqual(Self.value(strings[IntentDialogKey.saved.rawValue], "ar"), "زغلول سجلها ✓")
    // Every catalog key the intents name exists in both languages.
    var src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    src.appendPathComponent("Runner/Capture/CaptureIntents.swift")
    let text = try String(contentsOf: src, encoding: .utf8)
    let regex = try NSRegularExpression(pattern: "\"(native_ios_[A-Za-z]+)\"")
    let keys = Set(
      regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)).compactMap {
        Range($0.range(at: 1), in: text).map { String(text[$0]) }
      })
    XCTAssertGreaterThanOrEqual(keys.count, 15)
    for k in keys {
      XCTAssertNotNil(Self.value(strings[k], "ar"), k)
      XCTAssertNotNil(Self.value(strings[k], "en"), k)
    }
    let phrases = try Self.catalog("AppShortcuts.xcstrings")
    for (k, entry) in phrases {
      XCTAssertTrue(k.contains("${applicationName}"))
      XCTAssertTrue(Self.value(entry, "ar")?.contains("${applicationName}") == true)
    }
  }

  // MARK: Per-intent run times

  func testRunTimesArePerIntentAndStoredEncrypted() async throws {
    _ = await capture().logMessage(message: "synthetic EGP 1.00", sender: "NBE")
    XCTAssertEqual(runs.read(), IntentRunLog.Runs(messageAtMs: 1_700_000_000_000, walletAtMs: nil))
    _ = await capture().logWallet(amount: "EGP 2.00", merchant: "Synthetic", card: "CIB")
    XCTAssertEqual(runs.read(), IntentRunLog.Runs(messageAtMs: 1_700_000_000_000, walletAtMs: 1_700_000_000_000))
    let raw = try Data(contentsOf: runs.file)
    XCTAssertEqual(raw.count, IntentRunLog.plainBytes + 28, "nonce + ciphertext + tag")
    XCTAssertTrue(try isExcludedFromBackup(runs.file.deletingLastPathComponent()))
  }

  // MARK: FU-196 / 061-1 - one spool key

  func testGuardAndSpoolResolveTheSameKeychainItem() throws {
    let guardQuery = KeychainSpoolKeyProvider().keychain.query
    let spoolQuery = KeychainSpoolCipher().keychain.query
    for attr in [kSecAttrService, kSecAttrAccount, kSecAttrAccessGroup, kSecClass] {
      XCTAssertEqual(
        guardQuery[attr as String] as? String, spoolQuery[attr as String] as? String, "\(attr)")
    }
    XCTAssertEqual(guardQuery[kSecAttrService as String] as? String, SpoolKeychain.service)

    // A Guard read never creates; the spool's key is then the Guard's key.
    let fake = FakeKeychain()
    let provider = KeychainSpoolKeyProvider(keychain: spoolKeychain(fake))
    if case .missing = provider.existingKey() {} else { XCTFail("no item yet") }
    XCTAssertEqual(fake.adds, 0)
    let spoolKey = try spoolKeychain(fake).loadOrCreate().key
    guard case .found(let k) = provider.existingKey() else { return XCTFail("the shared key") }
    XCTAssertEqual(k.withUnsafeBytes { Data($0) }, spoolKey)
    fake.copyStatus = errSecInteractionNotAllowed
    if case .unavailable = provider.existingKey() {} else { XCTFail("locked is not missing") }
    XCTAssertEqual(fake.adds, 1)
  }

  // MARK: 062-1 - re-read the key before deleting

  func testAnEntryUnderAKeyAnotherProcessReplacedIsKeptAndRead() throws {
    let fake = FakeKeychain()
    let dir = root.appendingPathComponent("spool-062")
    let cipherA = KeychainSpoolCipher(keychain: spoolKeychain(fake))
    XCTAssertNotNil(cipherA.keyCreatedAtMs())  // this process caches K1
    // "Another process" replaces the item and writes under K2.
    _ = fake.delete([:])
    let cipherB = KeychainSpoolCipher(keychain: spoolKeychain(fake))
    let storeB = SpoolStore(dir: dir, cipher: cipherB, sleeper: { _ in })
    guard case .written(let id) = try storeB.write(sampleRecord(), cls: .priority) else {
      return XCTFail("refused")
    }
    let storeA = SpoolStore(dir: dir, cipher: cipherA, sleeper: { _ in })
    guard case .ok(let r) = storeA.read(id) else { return XCTFail("deleted under a stale key") }
    XCTAssertEqual(r.body, sampleRecord().body)

    // A tampered entry is still deleted on proof (the key is unchanged now)...
    let file = dir.appendingPathComponent("\(id).bin")
    var bytes = try Data(contentsOf: file)
    bytes[bytes.count - 1] ^= 0xFF
    try bytes.write(to: file)
    // ...but not while the Keychain can't confirm the current key.
    fake.copyStatus = errSecInteractionNotAllowed
    guard case .unavailable = storeA.read(id) else { return XCTFail("kept while locked") }
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    fake.copyStatus = nil
    XCTAssertEqual(storeA.read(id).isDeleted, true)
  }

  // MARK: Never logs

  func testCaptureSourcesNeverPrintOrLog() throws {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    url.appendPathComponent("Runner/Capture", isDirectory: true)
    let names = try FileManager.default.contentsOfDirectory(atPath: url.path).filter { $0.hasSuffix(".swift") }
    XCTAssertEqual(names.count, 4)
    let forbidden = ["print(", "debugPrint(", "NSLog(", "os_log(", "Logger(", "dump(", "OSLog", "fputs("]
    for name in names {
      let text = try String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
      for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
        for f in forbidden { XCTAssertFalse(line.contains(f), "\(name) uses \(f)") }
      }
    }
  }
}

extension SpoolReadResult {
  fileprivate var isDeleted: Bool {
    if case .deleted = self { return true }
    return false
  }
}
