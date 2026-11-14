import Flutter
import UIKit

/// T-117 (S-73): `FlutterMethodChannel("zaghlol/share")` `shareImage({path})`.
///
/// Presents UIActivityViewController for one PNG the user chose to share. Dart
/// deletes its staging file when this call returns, but the receiving app reads
/// later, so the image is copied into the app's tmp directory and removed in
/// the sheet's completion handler. No permission is needed. The path is never
/// logged or put into an error.
enum ShareImageRegistration {
  static let channelName = "zaghlol/share"

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "ZaghlolShareImage") else { return }
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "shareImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
        let path = args["path"] as? String, !path.isEmpty
      else {
        result(FlutterError(code: "bad-args", message: "path is required", details: nil))
        return
      }
      DispatchQueue.main.async { present(path: path, result: result) }
    }
  }

  private static func present(path: String, result: @escaping FlutterResult) {
    let fm = FileManager.default
    let copy = fm.temporaryDirectory.appendingPathComponent("share_\(UUID().uuidString).png")
    do {
      try fm.copyItem(at: URL(fileURLWithPath: path), to: copy)
    } catch {
      result(FlutterError(code: "share-failed", message: "copy", details: nil))
      return
    }
    guard let top = topViewController() else {
      try? fm.removeItem(at: copy)
      result(FlutterError(code: "share-failed", message: "no-screen", details: nil))
      return
    }
    let sheet = UIActivityViewController(activityItems: [copy], applicationActivities: nil)
    sheet.completionWithItemsHandler = { _, _, _, _ in try? fm.removeItem(at: copy) }
    // iPad: a popover needs an anchor; the middle of the screen is fine.
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = top.view
      popover.sourceRect = CGRect(
        x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    top.present(sheet, animated: true) { result(nil) }
  }

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
