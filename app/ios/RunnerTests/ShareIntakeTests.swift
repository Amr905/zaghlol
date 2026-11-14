import CryptoKit
import UIKit
import XCTest

@testable import Runner

/// T-065: intake rules, the two core negative proofs, the OCR hand-off and
/// the extension's plist values. Synthetic content only.
final class ShareIntakeTests: XCTestCase {
  private var root: URL!
  private var dir: URL!
  private var inbox: URL!  // stands in for the system's temporary copy

  override func setUpWithError() throws {
    root = try makeTempDir()
    dir = root.appendingPathComponent("files", isDirectory: true)
    inbox = root.appendingPathComponent("inbox", isDirectory: true)
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

  private func listing() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
  }

  private func intake(cipher: SpoolCipher = TestCipher(), ops: SpoolFileOps = DefaultSpoolFileOps())
    -> (ShareIntake, ShareStore)
  {
    let store = ShareStore(dir: dir, cipher: cipher, files: ops)
    return (ShareIntake(store: store), store)
  }

  private func file(_ name: String, _ bytes: Data) throws -> URL {
    let url = inbox.appendingPathComponent(name)
    try bytes.write(to: url)
    return url
  }

  private func png() -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1  // 8 x 8 pixels whatever the device scale
    return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).pngData { ctx in
      UIColor.red.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
  }

  // MARK: Negative proof 1: an unsupported type leaves nothing

  func testUnsupportedTypeLeavesNothing() throws {
    let (intake, store) = intake()
    let zip = try file("a.zip", Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 1, count: 64))
    XCTAssertEqual(intake.ingest(.file(zip)), .rejected(.unsupportedType))
    XCTAssertEqual(intake.ingest(.unsupported), .rejected(.unsupportedType))
    XCTAssertEqual(store.list(), [])
    // Only the one-byte reason slot exists: no body, meta or tmp file.
    XCTAssertEqual(listing(), [ShareStore.rejectionName])
    XCTAssertEqual(store.takeRejection(), .unsupportedType)
    XCTAssertEqual(listing(), [])
  }

  // MARK: Negative proof 2: a spool write failure leaves no partial file

  private final class FailNth: SpoolFileOps {
    var calls = 0
    let failAt: Int
    init(failAt: Int) { self.failAt = failAt }
    struct Boom: Error {}
    private let real = DefaultSpoolFileOps()
    func create(_ url: URL, contents: Data) throws {
      calls += 1
      if calls == failAt { throw Boom() }
      try real.create(url, contents: contents)
    }
    func move(_ from: URL, _ to: URL) throws {
      calls += 1
      if calls == failAt { throw Boom() }
      try real.move(from, to)
    }
    func syncDir(_ dir: URL) { real.syncDir(dir) }
  }

  func testWriteFailureAtEveryStepLeavesNoFile() throws {
    for step in 1...4 {  // body create, body move, meta create, meta move
      try? FileManager.default.removeItem(at: dir)
      let (intake, store) = intake(ops: FailNth(failAt: step))
      XCTAssertEqual(intake.ingest(.text("synthetic \(spoolCanary)")), .rejected(.unreadable), "step \(step)")
      XCTAssertEqual(store.list(), [], "step \(step)")
      XCTAssertEqual(listing().filter { $0 != ShareStore.rejectionName }, [], "partial file at step \(step)")
    }
  }

  // MARK: Acceptance

  func testImageIsStoredEncryptedAndOcrCanReadItInPlace() throws {
    let cipher = TestCipher()
    let (intake, store) = intake(cipher: cipher)
    let image = png()
    let url = try file("shot.png", image)
    guard case .accepted(let id) = intake.ingest(.file(url)) else { return XCTFail("rejected") }
    let meta = try XCTUnwrap(store.list().first)
    XCTAssertEqual(meta.kind, .image)
    XCTAssertEqual(meta.mimeType, "image/png")
    let path = dir.appendingPathComponent("\(id).bin")
    XCTAssertNil(try Data(contentsOf: path).range(of: image.prefix(8)), "plaintext image on disk")

    // The OCR host's decrypt path (FU-198): shared key, spool/files path allowed.
    let keyBytes = cipher.key.withUnsafeBytes { Data($0) }
    struct Fixed: SpoolFileKeyProvider { let key: Data; func spoolKey() -> Data? { key } }
    let source = SpoolFileImageSource(keys: Fixed(key: keyBytes), home: dir)
    XCTAssertEqual(try source.readImage(atPath: path.path), image)
    // A path outside the spool files directory is still refused.
    let outside = try file("other.bin", Data(repeating: 1, count: 64))
    XCTAssertThrowsError(try source.readImage(atPath: outside.path))
  }

  func testPdfAndTextAreAccepted() throws {
    let (intake, store) = intake()
    let pdf = try file("s.pdf", Data("%PDF-1.4 synthetic".utf8))
    guard case .accepted = intake.ingest(.file(pdf)) else { return XCTFail("pdf rejected") }
    guard case .accepted = intake.ingest(.text("synthetic message")) else { return XCTFail("text rejected") }
    XCTAssertEqual(store.list().map(\.kind), [.pdf, .text])
  }

  func testEmptyAndOversizedAreRefused() throws {
    let (intake, _) = intake()
    XCTAssertEqual(intake.ingest(.text("  \n ")), .rejected(.empty))
    XCTAssertEqual(
      intake.ingest(.text(String(repeating: "a", count: ShareLimits.maxTextChars + 1))),
      .rejected(.tooLarge))
    XCTAssertEqual(intake.ingest(.file(try file("e.png", Data()))), .rejected(.empty))
  }

  func testClassifierUsesMagicBytesNotNames() {
    XCTAssertEqual(ShareClassifier.classify(head: Data([0xFF, 0xD8, 0xFF, 0xE0]))?.mime, "image/jpeg")
    XCTAssertEqual(ShareClassifier.classify(head: Data("%PDF-1".utf8))?.kind, .pdf)
    XCTAssertNil(ShareClassifier.classify(head: Data("<html>".utf8)))
    XCTAssertEqual(ShareClassifier.pixelCount(of: png()), 64)
  }

  // MARK: Extension plist and entitlements carry the app's values

  func testExtensionPlistAndEntitlementsMatchTheApp() throws {
    let ios = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    func plist(_ path: String) throws -> [String: Any] {
      let d = try Data(contentsOf: ios.appendingPathComponent(path))
      return try XCTUnwrap(
        try PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any])
    }
    let ext = try plist("ShareExtension/Info.plist")
    let app = try plist("Runner/Info.plist")
    let norm = { (s: String?) in
      s?.replacingOccurrences(of: "$(ZAGHLOL_APP_BUNDLE_ID)", with: "$(PRODUCT_BUNDLE_IDENTIFIER)")
    }
    XCTAssertEqual(norm(ext["ZaghlolAppGroup"] as? String), app["ZaghlolAppGroup"] as? String)
    XCTAssertEqual(
      norm(ext["ZaghlolSharedKeychainSuffix"] as? String), app["ZaghlolSharedKeychainSuffix"] as? String)
    let ent = try plist("ShareExtension/ShareExtension.entitlements")
    XCTAssertEqual(
      ent["com.apple.security.application-groups"] as? [String], ["group.$(ZAGHLOL_APP_BUNDLE_ID)"])
    let appEnt = try plist("Runner/Runner.entitlements")
    let appKeychain = try XCTUnwrap(appEnt["keychain-access-groups"] as? [String])
    XCTAssertTrue(appKeychain.contains("$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER).shared"))
    XCTAssertEqual(
      ent["keychain-access-groups"] as? [String], ["$(AppIdentifierPrefix)$(ZAGHLOL_APP_BUNDLE_ID).shared"])
  }

  func testShareSourcesNeverLog() throws {
    let ios = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    for p in [
      "Shared/ShareStore.swift", "Shared/ShareIntake.swift", "ShareExtension/ShareViewController.swift",
      "Runner/Platform/Share/ShareIntakeHost.swift",
    ] {
      let text = try String(contentsOf: ios.appendingPathComponent(p), encoding: .utf8)
      for bad in ["print(", "NSLog", "os_log", "Logger(", "debugPrint(", "dump("] {
        XCTAssertFalse(text.contains(bad), "\(bad) in \(p)")
      }
    }
  }
}
