import XCTest

@testable import Runner

/// T-180. Synthetic readings only.
final class TrustedClockTests: XCTestCase {
  private final class Fake: ClockReadings {
    var wall: Int64
    var mono: Int64
    init(wall: Int64, mono: Int64) {
      self.wall = wall
      self.mono = mono
    }
    func wallMs() -> Int64 { wall }
    func monotonicMs() -> Int64 { mono }
  }

  func testSampleCarriesReadingsAndNoBootCount() throws {
    let s = try TrustedClockHost(readings: Fake(wall: 1_700_000_000_000, mono: 5_000)).sample()
    XCTAssertEqual(s.wallMs, 1_700_000_000_000)
    XCTAssertEqual(s.monotonicMs, 5_000)
    XCTAssertNil(s.bootCount)
  }

  func testWallClockChangeDoesNotMoveMonotonic() throws {
    let f = Fake(wall: 1_000, mono: 500)
    let host = TrustedClockHost(readings: f)
    let before = try host.sample()
    f.wall += 86_400_000
    let after = try host.sample()
    XCTAssertEqual(before.monotonicMs, after.monotonicMs)
  }

  func testRealMonotonicNeverGoesBackwards() throws {
    let host = TrustedClockHost()
    let a = try host.sample()
    let b = try host.sample()
    XCTAssertGreaterThanOrEqual(b.monotonicMs, a.monotonicMs)
    XCTAssertGreaterThan(a.monotonicMs, 0)
  }
}
