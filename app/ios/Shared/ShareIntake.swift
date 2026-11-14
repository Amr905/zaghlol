import Foundation
import ImageIO

/// T-065: validation and intake of one share (text, image or PDF), shared by
/// the Share Extension and the tests. Never parses or shows amounts, never
/// logs, and leaves nothing on disk for a refused or failed share.
enum ShareLimits {
  static let maxTextChars = 100_000
  static let maxImageBytes = 15 * 1024 * 1024
  static let maxPdfBytes = 20 * 1024 * 1024
  static let maxImagePixels = 64_000_000
  /// The largest file the intake will even open.
  static let maxFileBytes = 20 * 1024 * 1024
}

enum ShareClassifier {
  /// Kind and MIME type from the leading bytes only (never from the file name
  /// or the sender's declared type). nil means unsupported.
  static func classify(head: Data) -> (kind: ShareFileKind, mime: String)? {
    let b = [UInt8](head.prefix(16))
    if b.count >= 5, b[0] == 0x25, b[1] == 0x50, b[2] == 0x44, b[3] == 0x46, b[4] == 0x2D {
      return (.pdf, "application/pdf")
    }
    if b.count >= 8, Array(b[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
      return (.image, "image/png")
    }
    if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return (.image, "image/jpeg") }
    if b.count >= 12, Array(b[0..<4]) == Array("RIFF".utf8), Array(b[8..<12]) == Array("WEBP".utf8) {
      return (.image, "image/webp")
    }
    if b.count >= 12, Array(b[4..<8]) == Array("ftyp".utf8) {
      let brand = String(decoding: b[8..<12], as: UTF8.self)
      if ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1", "heif"].contains(brand) {
        return (.image, "image/heic")
      }
    }
    return nil
  }

  /// Decoded pixel count from the image header (ImageIO reads no pixels), or
  /// nil when the bounds cannot be read.
  static func pixelCount(of data: Data) -> Int? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
      let w = props[kCGImagePropertyPixelWidth] as? Int,
      let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0
    else { return nil }
    return w.multipliedReportingOverflow(by: h).overflow ? Int.max : w * h
  }
}

/// What the extension hands over: shared text, or a file the system made
/// readable for the duration of the call (its own temporary copy).
enum ShareInput {
  case text(String)
  case file(URL)
  /// The sender offered nothing this app accepts.
  case unsupported
}

enum ShareOutcome: Equatable {
  case accepted(id: String)
  case rejected(ShareRejection)
}

final class ShareIntake {
  private let store: ShareStore

  init(store: ShareStore) { self.store = store }

  /// Validates, encrypts and stores. A refusal is recorded in the store's
  /// rejection slot (a reason code only). Nothing of a refused or failed
  /// share stays on disk.
  func ingest(_ input: ShareInput) -> ShareOutcome {
    let result = run(input)
    if case .rejected(let reason) = result { store.setRejection(reason) }
    return result
  }

  private func run(_ input: ShareInput) -> ShareOutcome {
    switch input {
    case .unsupported:
      return .rejected(.unsupportedType)
    case .text(let text):
      if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .rejected(.empty) }
      if text.utf16.count > ShareLimits.maxTextChars { return .rejected(.tooLarge) }
      var payload = Data(text.utf8)
      return save(.text, "text/plain", &payload)
    case .file(let url):
      return file(url)
    }
  }

  private func file(_ url: URL) -> ShareOutcome {
    guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
      return .rejected(.unreadable)
    }
    if size == 0 { return .rejected(.empty) }
    if size > ShareLimits.maxFileBytes { return .rejected(.tooLarge) }
    guard var data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
      return .rejected(.unreadable)
    }
    defer { data.resetBytes(in: 0..<data.count) }
    guard let found = ShareClassifier.classify(head: data) else { return .rejected(.unsupportedType) }
    switch found.kind {
    case .image:
      if data.count > ShareLimits.maxImageBytes { return .rejected(.tooLarge) }
      guard let px = ShareClassifier.pixelCount(of: data) else { return .rejected(.unsupportedType) }
      if px > ShareLimits.maxImagePixels { return .rejected(.tooLarge) }
    case .pdf:
      if data.count > ShareLimits.maxPdfBytes { return .rejected(.tooLarge) }
    case .text:
      return .rejected(.unsupportedType)
    }
    var payload = Data(data)
    return save(found.kind, found.mime, &payload)
  }

  private func save(_ kind: ShareFileKind, _ mime: String, _ payload: inout Data) -> ShareOutcome {
    do {
      return .accepted(id: try store.add(kind: kind, mimeType: mime, payload: &payload).id)
    } catch ShareStoreError.tooLarge {
      return .rejected(.tooLarge)
    } catch {
      return .rejected(.unreadable)
    }
  }
}
