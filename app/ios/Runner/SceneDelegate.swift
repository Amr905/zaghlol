import Flutter
import UIKit

/// T-224: the user's theme choice (light / dark / system, nothing else), kept in
/// a file under Application Support (a directory excluded from backup, T-165;
/// never UserDefaults, see ZaghlolDirectories).
enum LaunchTheme {
  static let allowed: Set<String> = ["light", "dark", "system"]

  static func fileURL(fileManager: FileManager = .default) -> URL? {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("launch_theme")
  }

  static func read(from url: URL? = fileURL()) -> String {
    guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return "system" }
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return allowed.contains(value) ? value : "system"
  }

  @discardableResult
  static func write(_ value: String?, to url: URL? = fileURL()) -> Bool {
    guard let value, allowed.contains(value), let url else { return false }
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try value.write(to: url, atomically: true, encoding: .utf8)
      return true
    } catch {
      return false
    }
  }

  static func style(for value: String) -> UIUserInterfaceStyle {
    switch value {
    case "dark": return .dark
    case "light": return .light
    default: return .unspecified
    }
  }
}

class SceneDelegate: FlutterSceneDelegate {
  // T-224: the window resolves the LaunchBackground colour and the root view
  // background in the chosen theme from its first frame. The system-drawn
  // launch screen itself is rendered before any app code runs and still
  // follows the system theme.
  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let window = (scene as? UIWindowScene)?.windows.first ?? self.window {
      window.overrideUserInterfaceStyle = LaunchTheme.style(for: LaunchTheme.read())
    }
  }
}
