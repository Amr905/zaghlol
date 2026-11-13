import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // T-103 / FR-SEC-02: cover the app while it is not active so the app
  // switcher snapshot is blank. A no-op unless the app lock is on.
  override func sceneWillResignActive(_ scene: UIScene) {
    PrivacyCover.shared.show(in: scene)
    super.sceneWillResignActive(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    PrivacyCover.shared.remove()
  }
}
