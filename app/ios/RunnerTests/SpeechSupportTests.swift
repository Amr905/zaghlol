import XCTest

@testable import Runner

/// T-120: the on-device check passes the locale through and defaults to false.
final class SpeechSupportTests: XCTestCase {
  func testSupportedLocaleIsReported() {
    var seen: String?
    let ok = SpeechSupport.supportsOnDevice(localeId: "ar-EG") { l in
      seen = l.identifier
      return true
    }
    XCTAssertTrue(ok)
    XCTAssertEqual(seen, "ar_EG")
  }

  func testUnsupportedLocaleIsNotReported() {
    XCTAssertFalse(SpeechSupport.supportsOnDevice(localeId: "en_US") { _ in false })
  }
}
