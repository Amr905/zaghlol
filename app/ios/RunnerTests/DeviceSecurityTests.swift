import LocalAuthentication
import XCTest

@testable import Runner

/// T-103: the jailbreak heuristic, the secure-window switch and the passcode
/// check, with seams instead of a real jailbroken device or Face ID.
final class DeviceSecurityTests: XCTestCase {
  private func host(files: Set<String> = [], canWrite: Bool = false, simulator: Bool = false)
    -> DeviceSecurityHost
  {
    let h = DeviceSecurityHost()
    h.fileExists = { files.contains($0) }
    h.canWriteOutsideSandbox = { canWrite }
    h.isSimulator = simulator
    return h
  }

  func testCleanDeviceIsNotJailbroken() throws {
    XCTAssertFalse(try host().isDeviceRooted())
  }

  func testJailbreakPathOrSandboxEscapeIsJailbroken() throws {
    XCTAssertTrue(try host(files: ["/Applications/Cydia.app"]).isDeviceRooted())
    XCTAssertTrue(try host(canWrite: true).isDeviceRooted())
  }

  func testSimulatorIsNeverReported() throws {
    XCTAssertFalse(try host(files: ["/bin/bash"], canWrite: true, simulator: true).isDeviceRooted())
  }

  func testSecureWindowTogglesTheCover() throws {
    let h = host()
    try h.setSecureWindow(secure: true)
    XCTAssertTrue(PrivacyCover.shared.enabled)
    try h.setSecureWindow(secure: false)
    XCTAssertFalse(PrivacyCover.shared.enabled)
  }

  func testDeviceSecureFollowsThePasscodeCheck() throws {
    let h = host()
    h.passcodeSet = { true }
    XCTAssertTrue(try h.isDeviceSecure())
    h.passcodeSet = { false }
    XCTAssertFalse(try h.isDeviceSecure())
  }

  func testAuthenticateMapsPolicyResults() {
    XCTAssertEqual(DeviceSecurityHost.outcome(ok: true, error: nil), .success)
    XCTAssertEqual(DeviceSecurityHost.outcome(ok: false, error: nil), .failed)
    XCTAssertEqual(
      DeviceSecurityHost.outcome(ok: false, error: LAError(.userCancel)), .cancelled)
    XCTAssertEqual(
      DeviceSecurityHost.outcome(ok: false, error: LAError(.passcodeNotSet)), .notAvailable)
    XCTAssertEqual(
      DeviceSecurityHost.outcome(ok: false, error: LAError(.biometryLockout)), .lockedOut)
    XCTAssertEqual(
      DeviceSecurityHost.outcome(ok: false, error: LAError(.authenticationFailed)), .failed)
  }

  func testAuthenticateReportsThroughTheSeam() {
    let h = host()
    h.evaluate = { _, done in done(false, LAError(.userCancel)) }
    let exp = expectation(description: "completion")
    h.authenticate(reason: "why") { result in
      XCTAssertEqual(try? result.get(), .cancelled)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 2)
  }
}
