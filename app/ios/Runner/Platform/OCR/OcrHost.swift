import CoreGraphics
import CryptoKit
import Flutter
import Foundation
import Vision

/// T-160: the Pigeon `OcrHostApi` on iOS (platform-channels section 4, ADR-009).
///
/// Images and recognized text are financial data: everything stays on the
/// device, nothing here logs, and every error is code-only (no message, no
/// details, never a path, text or byte count). The image is decrypted in
/// memory only; the encrypted file is deleted in a `defer` whatever happens.
/// Minimum OS: iOS 17 (ADR-019); `VNRecognizeTextRequestRevision3` (iOS 16+)
/// is the revision that can list Arabic, and the list is read at runtime.

// MARK: - Seams

/// One recognized line, in Vision's coordinates (normalized, origin bottom-left).
struct RecognizedLine: Equatable {
  var text: String
  var confidence: Float
  var boundingBox: CGRect
}

/// The recognition engine. `VisionTextRecognizer` in production, a fake in tests.
protocol TextRecognizing {
  /// BCP-47 tags the engine lists on this device (e.g. "en-US", "ar-SA").
  func supportedRecognitionLanguages() throws -> [String]
  /// `languages` are already resolved tags; an empty list means engine default.
  func recognize(imageData: Data, languages: [String]) throws -> [RecognizedLine]
}

/// Opens the encrypted image file and returns its plain bytes (memory only).
protocol OcrImageSource {
  func readImage(atPath path: String) throws -> Data
}

/// The key that protects spool files (`spool/files/`, security-model: spool AES-GCM).
protocol SpoolFileKeyProvider {
  /// 32 bytes, or nil when no spool key exists on this device.
  func spoolKey() -> Data?
}

/// No iOS spool key is provisioned yet (the Share Extension owner adds it), so
/// the default provider reports NOT_AVAILABLE rather than guessing a key.
struct UnprovisionedSpoolKeyProvider: SpoolFileKeyProvider {
  func spoolKey() -> Data? { nil }
}

/// Vision cannot be used for this request. Code only.
enum OcrFailure: Error, Equatable {
  case ocrFailed
  case ioError
  case spoolDecryptFailed
  case notAvailable

  var code: String {
    switch self {
    case .ocrFailed: return "OCR_FAILED"
    case .ioError: return "IO_ERROR"
    case .spoolDecryptFailed: return "SPOOL_DECRYPT_FAILED"
    case .notAvailable: return "NOT_AVAILABLE"
    }
  }
}

// MARK: - Pure helpers

enum OcrLanguages {
  /// Latin recognition used when none of the requested languages is listed.
  static let latinFallback = "en"

  /// Maps requested ISO 639-1 codes to the engine's listed tags. A code is
  /// kept only if the engine lists it, so Arabic is used only when supported.
  /// If nothing requested is supported, falls back to Latin-only (English),
  /// and to the engine default (empty list) if even that is not listed.
  static func resolve(requested: [String], supported: [String]) -> [String] {
    var out: [String] = []
    for code in requested.map(primary) where !code.isEmpty {
      if let tag = supported.first(where: { primary($0) == code }), !out.contains(tag) {
        out.append(tag)
      }
    }
    if out.isEmpty, let tag = supported.first(where: { primary($0) == latinFallback }) {
      out.append(tag)
    }
    return out
  }

  /// ISO 639-1 codes of the supported tags, deduplicated, in listed order.
  static func codes(supported: [String]) -> [String] {
    var out: [String] = []
    for tag in supported {
      let code = primary(tag)
      if !code.isEmpty, !out.contains(code) { out.append(code) }
    }
    return out
  }

  static func primary(_ tag: String) -> String {
    let lower = tag.lowercased()
    return String(lower.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
  }
}

enum OcrPaths {
  /// True when `path` (after `..` and symlink resolution) is inside `home`.
  static func isInside(path: String, home: URL) -> Bool {
    let root = home.resolvingSymlinksInPath().standardizedFileURL.path
    let file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    return file.hasPrefix(root + "/")
  }
}

enum OcrMapping {
  /// Contract box: x, y, width, height, normalized, origin TOP-LEFT. Vision's
  /// origin is bottom-left, so y is flipped. Values are clamped to 0...1.
  static func box(from rect: CGRect) -> [Double] {
    func clamp(_ v: Double) -> Double { v.isFinite ? min(1, max(0, v)) : 0 }
    let x = clamp(Double(rect.minX))
    let w = clamp(Double(rect.width))
    let h = clamp(Double(rect.height))
    let y = clamp(1 - Double(rect.minY) - Double(rect.height))
    return [x, y, w, h]
  }

  /// Blank lines are dropped; lines are ordered top to bottom (then by x).
  static func result(from lines: [RecognizedLine]) -> OcrResult {
    let mapped: [OcrLine] = lines.compactMap { line in
      guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
      let c = Double(line.confidence)
      return OcrLine(
        text: line.text, confidence: c.isFinite ? min(1, max(0, c)) : 0,
        box: box(from: line.boundingBox))
    }
    let sorted = mapped.enumerated().sorted { a, b in
      if a.element.box[1] != b.element.box[1] { return a.element.box[1] < b.element.box[1] }
      if a.element.box[0] != b.element.box[0] { return a.element.box[0] < b.element.box[0] }
      return a.offset < b.offset
    }
    return OcrResult(lines: sorted.map { $0.element })
  }
}

// MARK: - Production seams

/// Spool file: nonce(12) || ciphertext || tag(16), AES-GCM, AAD
/// `zaghlol.spool.v1|file|<file name>` (so a file cannot be renamed or swapped).
struct SpoolFileImageSource: OcrImageSource {
  static let maxBytes = 25 * 1024 * 1024
  let keys: SpoolFileKeyProvider
  let home: URL

  init(keys: SpoolFileKeyProvider = UnprovisionedSpoolKeyProvider(), home: URL = URL(fileURLWithPath: NSHomeDirectory())) {
    self.keys = keys
    self.home = home
  }

  func readImage(atPath path: String) throws -> Data {
    guard OcrPaths.isInside(path: path, home: home) else { throw OcrFailure.ioError }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    guard let size = size, size > 28, size <= Self.maxBytes else { throw OcrFailure.ioError }
    guard let blob = try? Data(contentsOf: url, options: .mappedIfSafe) else {
      throw OcrFailure.ioError
    }
    guard let keyBytes = keys.spoolKey(), keyBytes.count == 32 else {
      throw OcrFailure.notAvailable
    }
    do {
      let box = try AES.GCM.SealedBox(combined: blob)
      let aad = Data("zaghlol.spool.v1|file|\(url.lastPathComponent)".utf8)
      return try AES.GCM.open(box, using: SymmetricKey(data: keyBytes), authenticating: aad)
    } catch {
      throw OcrFailure.spoolDecryptFailed
    }
  }
}

/// Apple Vision, `.accurate`, revision 3 (the revision with Arabic).
struct VisionTextRecognizer: TextRecognizing {
  private func makeRequest() -> VNRecognizeTextRequest {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.revision = VNRecognizeTextRequestRevision3
    request.usesLanguageCorrection = true
    return request
  }

  func supportedRecognitionLanguages() throws -> [String] {
    do { return try makeRequest().supportedRecognitionLanguages() } catch { throw OcrFailure.ocrFailed }
  }

  func recognize(imageData: Data, languages: [String]) throws -> [RecognizedLine] {
    let request = makeRequest()
    if !languages.isEmpty { request.recognitionLanguages = languages }
    do {
      try VNImageRequestHandler(data: imageData, options: [:]).perform([request])
    } catch {
      throw OcrFailure.ocrFailed
    }
    return (request.results ?? []).compactMap { obs in
      guard let top = obs.topCandidates(1).first else { return nil }
      return RecognizedLine(text: top.string, confidence: top.confidence, boundingBox: obs.boundingBox)
    }
  }
}

// MARK: - Host

final class OcrHost: OcrHostApi {
  private let recognizer: TextRecognizing
  private let source: OcrImageSource
  private let fileManager: FileManager
  private let home: URL
  private let queue = DispatchQueue(label: "app.zaghlol.ocr", qos: .userInitiated)

  init(
    recognizer: TextRecognizing = VisionTextRecognizer(),
    source: OcrImageSource = SpoolFileImageSource(),
    fileManager: FileManager = .default,
    home: URL = URL(fileURLWithPath: NSHomeDirectory())
  ) {
    self.home = home
    self.recognizer = recognizer
    self.source = source
    self.fileManager = fileManager
  }

  private static func error(_ failure: OcrFailure) -> OcrApiError {
    OcrApiError(code: failure.code, message: nil, details: nil)
  }

  /// Synchronous core, used by `recognize` and by tests.
  func recognizeNow(path: String, languages: [String]) throws -> OcrResult {
    // Only files inside this app's container are touched, never deleted.
    guard OcrPaths.isInside(path: path, home: home) else { throw Self.error(.ioError) }
    var keyMissing = false
    // No spool key: nothing was processed, so the file stays for a retry.
    // Otherwise the file is deleted whatever happens (FR-SEC-03).
    defer {
      if !keyMissing { try? fileManager.removeItem(atPath: path) }
    }
    do {
      var image = try source.readImage(atPath: path)
      defer { image.resetBytes(in: 0..<image.count) }
      let supported = try recognizer.supportedRecognitionLanguages()
      let resolved = OcrLanguages.resolve(requested: languages, supported: supported)
      let lines = try recognizer.recognize(imageData: image, languages: resolved)
      return OcrMapping.result(from: lines)
    } catch let failure as OcrFailure {
      if failure == .notAvailable { keyMissing = true }
      throw Self.error(failure)
    } catch {
      throw Self.error(.ocrFailed)
    }
  }

  func recognize(
    encryptedImagePath: String, languages: [String],
    completion: @escaping (Result<OcrResult, Error>) -> Void
  ) {
    queue.async {
      do {
        completion(.success(try self.recognizeNow(path: encryptedImagePath, languages: languages)))
      } catch {
        completion(.failure(error))
      }
    }
  }

  func supportedLanguages() throws -> [String] {
    do {
      return OcrLanguages.codes(supported: try recognizer.supportedRecognitionLanguages())
    } catch {
      throw Self.error(.ocrFailed)
    }
  }
}

/// Registers the OCR host on the UI engine (OCR runs in the foreground).
enum OcrRegistration {
  static let host = OcrHost()

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolOcr") else { return }
    OcrHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
  }
}
