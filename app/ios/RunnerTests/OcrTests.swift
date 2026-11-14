import CryptoKit
import UIKit
import XCTest

@testable import Runner

/// T-160: language resolution, result mapping, file handling and the code-only
/// errors of the OCR host. Vision is behind a fake; the images are synthetic
/// bytes, never real receipts.
final class OcrTests: XCTestCase {

  // MARK: Language resolution

  func testArabicIsUsedOnlyWhenListed() {
    let withArabic = ["en-US", "fr-FR", "ar-SA"]
    XCTAssertEqual(OcrLanguages.resolve(requested: ["ar", "en"], supported: withArabic), ["ar-SA", "en-US"])
    let without = ["en-US", "fr-FR"]
    XCTAssertEqual(OcrLanguages.resolve(requested: ["ar", "en"], supported: without), ["en-US"])
  }

  func testNothingRequestedIsSupportedFallsBackToLatin() {
    XCTAssertEqual(OcrLanguages.resolve(requested: ["ar"], supported: ["en-US", "de-DE"]), ["en-US"])
    XCTAssertEqual(OcrLanguages.resolve(requested: ["ar"], supported: ["ar-SA"]), ["ar-SA"])
    XCTAssertEqual(OcrLanguages.resolve(requested: ["ar"], supported: ["de-DE"]), [])
    XCTAssertEqual(OcrLanguages.resolve(requested: [], supported: ["en-US"]), ["en-US"])
  }

  func testCodesAreDeduplicatedPrimarySubtags() {
    XCTAssertEqual(
      OcrLanguages.codes(supported: ["en-US", "ar-SA", "zh-Hans", "en-GB"]), ["en", "ar", "zh"])
  }

  // MARK: Mapping

  func testBoxFlipsToTopLeftOrigin() {
    // A line at the very top in Vision coordinates (bottom-left origin).
    let box = OcrMapping.box(from: CGRect(x: 0.1, y: 0.9, width: 0.5, height: 0.1))
    XCTAssertEqual(box[0], 0.1, accuracy: 1e-9)
    XCTAssertEqual(box[1], 0.0, accuracy: 1e-9)
    XCTAssertEqual(box[2], 0.5, accuracy: 1e-9)
    XCTAssertEqual(box[3], 0.1, accuracy: 1e-9)
  }

  func testBoxIsClampedAndNonFiniteBecomesZero() {
    let box = OcrMapping.box(from: CGRect(x: -0.2, y: 0.95, width: 1.4, height: 0.2))
    for v in box { XCTAssertTrue(v >= 0 && v <= 1) }
    XCTAssertEqual(OcrMapping.box(from: CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1))[0], 0)
  }

  func testResultDropsBlankLinesAndSortsTopToBottom() {
    let lines = [
      RecognizedLine(text: "low", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.1, width: 1, height: 0.1)),
      RecognizedLine(text: "   ", confidence: 0.9, boundingBox: CGRect(x: 0, y: 0.5, width: 1, height: 0.1)),
      RecognizedLine(text: "مرحبا", confidence: 1.7, boundingBox: CGRect(x: 0, y: 0.8, width: 1, height: 0.1)),
    ]
    let result = OcrMapping.result(from: lines)
    XCTAssertEqual(result.lines.map { $0.text }, ["مرحبا", "low"])
    XCTAssertEqual(result.lines[0].confidence, 1.0, accuracy: 1e-9)
  }

  // MARK: Host

  private final class FakeRecognizer: TextRecognizing {
    var supported = ["en-US", "ar-SA"]
    var lines: [RecognizedLine] = []
    var error: Error?
    var requestedLanguages: [[String]] = []
    func supportedRecognitionLanguages() throws -> [String] { supported }
    func recognize(imageData: Data, languages: [String]) throws -> [RecognizedLine] {
      requestedLanguages.append(languages)
      if let error = error { throw error }
      return lines
    }
  }

  private struct FakeSource: OcrImageSource {
    var result: Result<Data, OcrFailure>
    func readImage(atPath path: String) throws -> Data { try result.get() }
  }

  private struct FixedKey: SpoolFileKeyProvider {
    var key: Data?
    func spoolKey() -> Data? { key }
  }

  private var home: URL!

  override func setUpWithError() throws {
    home = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ocr-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }

  private func makeFile(_ name: String = "a.bin", bytes: Data = Data(repeating: 7, count: 64)) -> String {
    let url = home.appendingPathComponent(name)
    try! bytes.write(to: url)
    return url.path
  }

  private func host(
    _ recognizer: FakeRecognizer, source: OcrImageSource
  ) -> OcrHost {
    OcrHost(recognizer: recognizer, source: source, home: home)
  }

  private func code(_ block: () throws -> Any) -> String? {
    do { _ = try block(); return nil } catch let e as OcrApiError { return e.code } catch { return "other" }
  }

  func testSuccessDeletesFileAndPassesResolvedLanguages() throws {
    let rec = FakeRecognizer()
    rec.lines = [RecognizedLine(text: "Total", confidence: 0.8, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1))]
    let path = makeFile()
    let result = try host(rec, source: FakeSource(result: .success(Data([1, 2, 3]))))
      .recognizeNow(path: path, languages: ["ar", "en"])
    XCTAssertEqual(result.lines.count, 1)
    XCTAssertEqual(rec.requestedLanguages, [["ar-SA", "en-US"]])
    XCTAssertFalse(FileManager.default.fileExists(atPath: path))
  }

  func testEngineFailureIsCodeOnlyAndFileIsStillDeleted() {
    let rec = FakeRecognizer()
    rec.error = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "secret text"])
    let path = makeFile()
    do {
      _ = try host(rec, source: FakeSource(result: .success(Data([1])))).recognizeNow(path: path, languages: ["en"])
      XCTFail("expected failure")
    } catch let e as OcrApiError {
      XCTAssertEqual(e.code, "OCR_FAILED")
      XCTAssertNil(e.message)
      XCTAssertNil(e.details)
    } catch { XCTFail("wrong error") }
    XCTAssertFalse(FileManager.default.fileExists(atPath: path))
  }

  func testDecryptFailureIsReportedAndFileDeleted() {
    let path = makeFile()
    XCTAssertEqual(
      code { try host(FakeRecognizer(), source: FakeSource(result: .failure(.spoolDecryptFailed)))
        .recognizeNow(path: path, languages: ["en"]) },
      "SPOOL_DECRYPT_FAILED")
    XCTAssertFalse(FileManager.default.fileExists(atPath: path))
  }

  func testPathOutsideContainerIsRejectedAndNotDeleted() throws {
    let other = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).bin")
    try Data(repeating: 1, count: 64).write(to: other)
    defer { try? FileManager.default.removeItem(at: other) }
    XCTAssertEqual(
      code { try host(FakeRecognizer(), source: FakeSource(result: .success(Data([1]))))
        .recognizeNow(path: other.path, languages: ["en"]) },
      "IO_ERROR")
    XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
  }

  func testMissingSpoolKeyReportsNotAvailableAndKeepsFile() {
    let path = makeFile(bytes: Data(repeating: 3, count: 100))
    let source = SpoolFileImageSource(keys: FixedKey(key: nil), home: home)
    XCTAssertEqual(
      code { try host(FakeRecognizer(), source: source).recognizeNow(path: path, languages: ["en"]) },
      "NOT_AVAILABLE")
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
  }

  func testSpoolFileRoundTripAndAadBinding() throws {
    let keyBytes = Data((0..<32).map { UInt8($0 &* 5 &+ 1) })
    let key = SymmetricKey(data: keyBytes)
    let plain = Data("synthetic image bytes".utf8)
    let name = "ocr-1.bin"
    let aad = Data("zaghlol.spool.v1|file|\(name)".utf8)
    let sealed = try AES.GCM.seal(plain, using: key, authenticating: aad).combined!
    let path = makeFile(name, bytes: sealed)
    let source = SpoolFileImageSource(keys: FixedKey(key: keyBytes), home: home)
    XCTAssertEqual(try source.readImage(atPath: path), plain)

    // The same bytes under another file name fail (renamed or swapped file).
    let renamed = makeFile("ocr-2.bin", bytes: sealed)
    XCTAssertThrowsError(try source.readImage(atPath: renamed)) {
      XCTAssertEqual($0 as? OcrFailure, .spoolDecryptFailed)
    }
    // A flipped byte fails.
    var bad = sealed
    bad[20] ^= 0x01
    let tampered = makeFile(name + "x", bytes: bad)
    XCTAssertThrowsError(try source.readImage(atPath: tampered))
  }

  func testSupportedLanguagesAreCodes() throws {
    let rec = FakeRecognizer()
    rec.supported = ["en-US", "ar-SA", "en-GB"]
    XCTAssertEqual(try host(rec, source: FakeSource(result: .success(Data()))).supportedLanguages(), ["en", "ar"])
  }

  /// Runs the real Vision engine on a synthetic rendered image: the request
  /// must succeed and its supported list must include English.
  func testVisionEngineListsEnglishAndRunsOnSyntheticImage() throws {
    let engine = VisionTextRecognizer()
    let supported = try engine.supportedRecognitionLanguages()
    XCTAssertTrue(supported.contains { OcrLanguages.primary($0) == "en" })
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 120))
    let png = renderer.pngData { ctx in
      UIColor.white.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 120))
      ("TOTAL 125" as NSString).draw(
        at: CGPoint(x: 20, y: 30),
        withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.black])
    }
    let lines = try engine.recognize(
      imageData: png, languages: OcrLanguages.resolve(requested: ["en"], supported: supported))
    XCTAssertTrue(lines.contains { $0.text.uppercased().contains("TOTAL") })
  }
}
