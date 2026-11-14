import UIKit
import UniformTypeIdentifiers

/// T-065 (FR-ING-I-04): the Share Extension. It has no UI: it takes the first
/// image, PDF or text the sender offers, validates it, stores it encrypted in
/// the App Group (`ShareIntake`) and closes. The app picks it up on its next
/// foreground and always shows it for confirmation (FR-ING-A-04). The
/// extension never parses or shows amounts, never logs, and does not touch the
/// Capture Guard.
final class ShareViewController: UIViewController {
  private var finished = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    let providers = ((extensionContext?.inputItems as? [NSExtensionItem]) ?? [])
      .flatMap { $0.attachments ?? [] }
    process(providers)
  }

  private func process(_ providers: [NSItemProvider]) {
    guard let intake = makeIntake() else {
      finish()
      return
    }
    // Priority: a screenshot or photo, then a PDF, then text.
    if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
      loadFile(p, UTType.image, intake)
    } else if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }) {
      loadFile(p, UTType.pdf, intake)
    } else if let p = providers.first(where: {
      $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
    }) {
      loadText(p, intake)
    } else {
      _ = intake.ingest(.unsupported)
      finish()
    }
  }

  private func makeIntake() -> ShareIntake? {
    guard let container = SpoolLocation.containerURL() else { return nil }
    let store = ShareStore(
      dir: SpoolLocation.filesDirectory(in: container), cipher: KeychainSpoolCipher())
    return ShareIntake(store: store)
  }

  /// The system's temporary copy is valid only inside the handler, so the
  /// intake runs there. The copy is the system's to delete; this code makes
  /// no plaintext file of its own.
  private func loadFile(_ provider: NSItemProvider, _ type: UTType, _ intake: ShareIntake) {
    provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, _ in
      if let url = url {
        _ = intake.ingest(.file(url))
      } else {
        _ = intake.ingest(.unsupported)
      }
      DispatchQueue.main.async { self?.finish() }
    }
  }

  private func loadText(_ provider: NSItemProvider, _ intake: ShareIntake) {
    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) {
      [weak self] item, _ in
      var text: String?
      if let s = item as? String {
        text = s
      } else if let d = item as? Data {
        text = String(data: d, encoding: .utf8)
      }
      if let text = text {
        _ = intake.ingest(.text(text))
      } else {
        _ = intake.ingest(.unsupported)
      }
      DispatchQueue.main.async { self?.finish() }
    }
  }

  private func finish() {
    guard !finished else { return }
    finished = true
    extensionContext?.completeRequest(returningItems: nil)
  }
}
