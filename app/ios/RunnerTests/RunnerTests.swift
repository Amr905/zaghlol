import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  /// Placeholder proving the XCTest lane runs in CI. Capture Guard and App Intents
  /// tests arrive with the native tasks.
  func testHostBundleIsTheZaghlolApp() {
    XCTAssertTrue(Bundle.main.bundleIdentifier?.hasPrefix("app.zaghlol") == true)
  }

  /// Overdue reminder action: the button opens its own route, a plain tap the
  /// notification's route, and a malformed route opens nothing.
  func testNotificationActionRouting() {
    let info: [AnyHashable: Any] = [
      NotificationsHost.routeKey: "/recurring/a1",
      NotificationsHost.actionRouteKey: "/recurring/a1/paid/2026-11-10",
    ]
    XCTAssertEqual(
      NotificationsHost.routeFor(actionIdentifier: NotificationsHost.actionId, userInfo: info),
      "/recurring/a1/paid/2026-11-10")
    XCTAssertEqual(
      NotificationsHost.routeFor(
        actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier", userInfo: info),
      "/recurring/a1")
    XCTAssertNil(
      NotificationsHost.routeFor(
        actionIdentifier: NotificationsHost.actionId,
        userInfo: [NotificationsHost.actionRouteKey: "https://evil"]))
  }

}
