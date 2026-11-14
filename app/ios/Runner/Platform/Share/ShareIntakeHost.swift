import Flutter
import Foundation

/// T-065: the Pigeon `ShareIntakeHostApi` on iOS (platform-channels.md 2.1).
/// The Share Extension wrote the shares encrypted into the App Group
/// (`ShareStore`); this host lists them, decrypts one in memory for Dart and
/// deletes it on `discardShare`. Shared content is financial data: nothing
/// logs, and every error is code-only (no message, no details).
final class ShareIntakeHost: ShareIntakeHostApi {
  private let store: ShareStore?

  init(store: ShareStore?) { self.store = store }

  private static func error(_ code: String) -> ShareIntakeApiError {
    ShareIntakeApiError(code: code, message: nil, details: nil)
  }

  private static func descriptor(_ m: ShareMeta) -> ShareDescriptor {
    let kind: ShareKind
    switch m.kind {
    case .text: kind = .text
    case .image: kind = .image
    case .pdf: kind = .pdf
    }
    return ShareDescriptor(
      id: m.id, kind: kind, mimeType: m.mimeType, sizeBytes: m.sizeBytes,
      receivedAtMs: m.receivedAtMs)
  }

  func listPendingShares() throws -> [ShareDescriptor] {
    (store?.list() ?? []).map(Self.descriptor)
  }

  func readShare(id: String) throws -> ShareContent {
    guard let store = store else { throw Self.error("IO_ERROR") }
    do {
      var read = try store.read(id)
      defer { read.payload.resetBytes(in: 0..<read.payload.count) }
      let d = Self.descriptor(read.meta)
      if read.meta.kind == .text {
        return ShareContent(descriptor: d, text: String(decoding: read.payload, as: UTF8.self), bytes: nil)
      }
      return ShareContent(descriptor: d, text: nil, bytes: FlutterStandardTypedData(bytes: read.payload))
    } catch ShareStoreError.notAuthentic {
      throw Self.error("SPOOL_DECRYPT_FAILED")
    } catch {
      throw Self.error("IO_ERROR")
    }
  }

  func discardShare(id: String) throws { store?.discard(id) }

  func takePendingRejection() throws -> ShareRejectReason? {
    switch store?.takeRejection() {
    case .tooLarge?: return .tooLarge
    case .unsupportedType?: return .unsupportedType
    case .unreadable?: return .unreadable
    case .empty?: return .empty
    case nil: return nil
    }
  }
}

enum ShareIntakeRegistration {
  static let host: ShareIntakeHost = {
    let store = SpoolLocation.containerURL().flatMap { SpoolRuntime.shared?.shareStore(container: $0) }
    return ShareIntakeHost(store: store)
  }()

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolShareIntake") else { return }
    ShareIntakeHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: host)
  }
}
