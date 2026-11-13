import XCTest

@testable import Runner

/// T-061 (AC1): the shared Guard golden file, read in place (never copied):
/// `packages/zaghlol_parsing/test/fixtures/guard/golden.json`, the same file
/// the Dart and Kotlin Guards run. Failure messages carry case ids only,
/// never a body. Synthetic data only.

enum GuardFixtures {
  /// `<repo>/packages/zaghlol_parsing/test/fixtures/guard`, found from this
  /// file's path (the simulator test host reads the checkout directly).
  static let dir: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { url = url.deletingLastPathComponent() }
    return url.appendingPathComponent(
      "packages/zaghlol_parsing/test/fixtures/guard", isDirectory: true)
  }()

  static func data(_ relative: String) throws -> Data {
    try Data(contentsOf: dir.appendingPathComponent(relative))
  }

  static var t1Base: Data { get throws { try data("configs/t1_base.json") } }
  static var t1User: Data { get throws { try data("configs/t1_user.json") } }
}

struct GoldenShapeError: Error {}

extension GuardJsonValue {
  func object() throws -> GuardJsonObject {
    if case .object(let o) = self { return o }
    throw GoldenShapeError()
  }
  func array() throws -> [GuardJsonValue] {
    if case .array(let a) = self { return a }
    throw GoldenShapeError()
  }
  func string() throws -> String {
    if case .string(let s) = self { return s }
    throw GoldenShapeError()
  }
  func int() throws -> Int {
    if case .int(let n) = self { return Int(n) }
    throw GoldenShapeError()
  }
  /// A string, or nil for JSON null.
  func optString() throws -> String? {
    if case .null = self { return nil }
    return try string()
  }
}

extension GuardJsonObject {
  func req(_ key: String) throws -> GuardJsonValue {
    guard let v = values[key] else { throw GoldenShapeError() }
    return v
  }
}

/// Runs the golden file against the Swift Guard. `decide` is a seam so a test
/// can prove the runner goes red when the Guard disagrees.
final class GuardGoldenRunner {
  typealias Decide = (CaptureGuard, _ channel: String, _ source: String, _ body: String) ->
    GuardDecision

  struct Result {
    let fold: Int
    let cases: Int
    let rate: Int
    let modes: Int
    let count: Int
    let failures: [String]
    var total: Int { fold + cases + rate + modes }
  }

  static let topLevelKeys: Set<String> = [
    "format", "synthetic", "note", "count", "configs", "fold", "cases", "rate", "modes",
  ]

  private let load: (String) throws -> Data
  private let decide: Decide
  private(set) var golden = GuardJsonObject()
  private var failures: [String] = []
  private var guards: [String: CaptureGuard] = [:]

  init(
    load: @escaping (String) throws -> Data = { try GuardFixtures.data($0) },
    decide: @escaping Decide = { $0.decide(channel: $1, source: $2, body: $3) }
  ) throws {
    self.load = load
    self.decide = decide
    let text = String(decoding: try load("golden.json"), as: UTF8.self)
    golden = try StrictJson.parse(Array(text.utf16)).object()
  }

  func entries(_ key: String) throws -> [GuardJsonObject] {
    try golden.req(key).array().map { try $0.object() }
  }

  private func guardFor(_ id: String) throws -> CaptureGuard {
    if let g = guards[id] { return g }
    let c = try golden.req("configs").object().req(id).object()
    let base = try load(try c.req("base").string())
    let user = try c.req("user").optString().map { try load($0) }
    let result = GuardConfig.parse(base: base, user: user)
    guard let config = result.config else {
      failures.append("config \(id) does not load: \(result)")
      throw GoldenShapeError()
    }
    let g = CaptureGuard(config: config)
    guards[id] = g
    return g
  }

  func runAll() throws -> Result {
    failures = []
    if case .int(let f)? = golden.values["format"], f == 1 {} else { failures.append("format is not 1") }
    if case .bool(true)? = golden.values["synthetic"] {} else {
      failures.append("synthetic is not true")
    }
    let unknown = Set(golden.keys).subtracting(GuardGoldenRunner.topLevelKeys)
    if !unknown.isEmpty { failures.append("unknown top-level keys: \(unknown.sorted())") }

    let fold = try entries("fold")
    let cases = try entries("cases")
    let rate = try entries("rate")
    let modes = try entries("modes")
    for f in fold { try runFold(f) }
    for c in cases { try runCase(c) }
    for r in rate { try runRate(r) }
    for m in modes { try runMode(m) }
    let count = try golden.req("count").int()
    let total = fold.count + cases.count + rate.count + modes.count
    if total != count { failures.append("count: file says \(count), read \(total)") }
    return Result(
      fold: fold.count, cases: cases.count, rate: rate.count, modes: modes.count, count: count,
      failures: failures)
  }

  private func runFold(_ f: GuardJsonObject) throws {
    let id = try f.req("id").string()
    let input = TextFold.units(try f.req("in").string())
    let out = TextFold.units(try f.req("out").string())
    let lines = try f.values["lines"].map { TextFold.units(try $0.string()) } ?? out
    if TextFold.foldKey(input) != out { failures.append("fold \(id): foldKey differs") }
    if TextFold.foldKeyLines(input) != lines { failures.append("fold \(id): foldKeyLines differs") }
  }

  /// The golden `expect` shape as `GuardDecision.goldenForm`.
  static func expectedForm(_ expect: GuardJsonObject) throws -> String {
    if try expect.req("decision").string() == "drop" {
      return "drop|\(try expect.req("reason").string())"
    }
    let inst = try expect.req("inst").optString() ?? "~"
    let last4 = try expect.req("last4").optString() ?? "~"
    return "keep|\(try expect.req("kind").string())|\(inst)|\(last4)"
  }

  private func runCase(_ c: GuardJsonObject) throws {
    let id = try c.req("id").string()
    let guardRules = try guardFor(try c.req("config").string())
    let actual = decide(
      guardRules, try c.req("channel").string(), try c.req("source").string(),
      try c.req("body").string()
    ).goldenForm
    let expected = try GuardGoldenRunner.expectedForm(try c.req("expect").object())
    if actual != expected { failures.append("case \(id): expected \(expected), got \(actual)") }
  }

  private func runRate(_ r: GuardJsonObject) throws {
    let id = try r.req("id").string()
    let guardRules = try guardFor(try r.req("config").string())
    let limiter = SenderRateLimiter(perSenderPerMin: guardRules.config!.perSenderPerMin)
    var kept = 0
    var limited = 0
    var dropped = 0
    for e in try r.req("events").array().map({ try $0.object() }) {
      let channel = try e.req("channel").string()
      let source = try e.req("source").string()
      let body = try e.req("body").string()
      let tMs = Int64(try e.req("tMs").int())
      for _ in 0..<(try e.req("n").int()) {
        let d = limiter.apply(
          decide(guardRules, channel, source, body), channel: channel, source: source, nowMs: tMs)
        switch d {
        case .keep: kept += 1
        case .drop(.rateLimited): limited += 1
        case .drop: dropped += 1
        }
      }
    }
    let expect = try r.req("expect").object()
    let want = [
      try expect.req("kept").int(), try expect.req("rateLimited").int(),
      try expect.req("dropped").int(),
    ]
    if [kept, limited, dropped] != want {
      failures.append("rate \(id): expected \(want), got \([kept, limited, dropped])")
    }
  }

  private func runMode(_ m: GuardJsonObject) throws {
    let id = try m.req("id").string()
    let base = try load(try m.req("base").string())
    let user = try m.req("user").optString().map { try load($0) }
    let result = GuardConfig.parse(base: base, user: user)
    let expectMode = try m.req("expect").string()
    if result.mode.rawValue != expectMode {
      failures.append("mode \(id): expected \(expectMode), got \(result.mode.rawValue)")
    }
    var userErrorWanted = false
    if case .bool(let b)? = m.values["userError"] { userErrorWanted = b }
    if result.userFailed != userErrorWanted { failures.append("mode \(id): userError differs") }
    if result.mode == .invalid {
      if result.config != nil { failures.append("mode \(id): invalid with a config") }
      let d = CaptureGuard(config: result.config).decide(
        channel: "sms", source: "NBE", body: "Purchase EGP 10.00")
      if d != .drop(.configInvalid) {
        failures.append("mode \(id): invalid config did not drop config_invalid")
      }
    }
  }
}

final class GuardGoldenTests: XCTestCase {
  func testAllGoldenEntriesPass() throws {
    let result = try GuardGoldenRunner().runAll()
    XCTAssertTrue(result.failures.isEmpty, result.failures.joined(separator: "\n"))
    XCTAssertEqual(result.count, result.total)
    // Floor: the T-035 golden (207), the T-038 additions (30) and FU-121 (3).
    XCTAssertGreaterThanOrEqual(result.total, 240, "golden shrank")
    XCTAssertTrue(
      result.cases >= 60 && result.fold >= 15 && result.rate >= 3 && result.modes >= 4)
  }

  /// Negative proof: a Swift Guard that disagrees with the golden file makes
  /// the run red (here: every keep is turned into a drop).
  func testSwiftGuardDisagreeingWithTheGoldenFileIsReported() throws {
    let runner = try GuardGoldenRunner(decide: { g, channel, source, body in
      switch g.decide(channel: channel, source: source, body: body) {
      case .keep: return .drop(.notFinancial)
      case .drop(let r): return .drop(r)
      }
    })
    let result = try runner.runAll()
    XCTAssertFalse(result.failures.isEmpty)
    XCTAssertTrue(result.failures.contains { $0.hasPrefix("case ") })
  }

  /// Negative proof for the FU-121 phone-number filter: a Guard that keeps
  /// every personal number disagrees with the golden `nf.personal_number`.
  func testGuardThatKeepsPersonalMessagesDisagreesWithGolden() throws {
    let runner = try GuardGoldenRunner(decide: { g, channel, source, body in
      let d = g.decide(channel: channel, source: source, body: body)
      if case .drop(.notFinancial) = d { return .keep(kind: .user, inst: nil, last4: nil) }
      return d
    })
    let failures = try runner.runAll().failures
    XCTAssertTrue(failures.contains { $0.hasPrefix("case nf.personal_number:") })
  }

  func testRunnerRejectsAnUnknownTopLevelKeyAFormatChangeAndAWrongCount() throws {
    let text = String(decoding: try GuardFixtures.data("golden.json"), as: UTF8.self)
    func run(_ edited: String) throws -> [String] {
      try GuardGoldenRunner(load: {
        $0 == "golden.json" ? Data(edited.utf8) : try GuardFixtures.data($0)
      }).runAll().failures
    }
    let extra = text.replacingOccurrences(of: "{", with: "{\"cases2\": [],", options: [], range: text.range(of: "{"))
    XCTAssertTrue(try run(extra).contains { $0.hasPrefix("unknown top-level keys") })
    let format = text.replacingOccurrences(of: "\"format\": 1", with: "\"format\": 2")
    XCTAssertTrue(try run(format).contains("format is not 1"))
    let count = try GuardGoldenRunner().golden.req("count").int()
    let wrong = text.replacingOccurrences(of: "\"count\": \(count)", with: "\"count\": \(count + 1)")
    XCTAssertTrue(try run(wrong).contains { $0.hasPrefix("count:") })
  }

  /// `foldKeyLines(x)` with `\n` as a space equals `foldKey(x)`, and a folded
  /// text never starts or ends with a space or a line break (ICU `$` also
  /// matches before a final line terminator, Dart's does not).
  func testFoldedGoldenTextNeverStartsOrEndsWithABreakOrSpace() throws {
    let runner = try GuardGoldenRunner()
    var inputs = try runner.entries("fold").map { try $0.req("in").string() }
    inputs += try runner.entries("cases").map { try $0.req("body").string() }
    for s in inputs {
      let u = TextFold.units(s)
      let key = TextFold.foldKey(u)
      let lines = TextFold.foldKeyLines(u)
      XCTAssertEqual(lines.map { $0 == 0x0A ? 0x20 : $0 }, key)
      for f in [key, lines] {
        XCTAssertFalse(f.first == 0x0A || f.first == 0x20 || f.last == 0x0A || f.last == 0x20)
      }
    }
  }

  /// Folded text is compared by UTF-16 code units: Swift `String ==` would
  /// treat a precomposed and a decomposed letter as equal, Dart and Kotlin do not.
  func testFoldedKeysAreCompared_ByCodeUnitsNotCanonicalEquivalence() {
    let composed = TextFold.foldKey(TextFold.units("\u{00E9}"))
    let decomposed = TextFold.foldKey(TextFold.units("e\u{0301}"))
    XCTAssertNotEqual(composed, decomposed)
    XCTAssertEqual(composed, [0x00E9])
  }

  func testAsciiOnlyLowercaseKeepsKelvinAndTurkishDottedI() {
    XCTAssertEqual(TextFold.foldKey(TextFold.units("\u{212A}\u{0130}NBE")), [0x212A, 0x0130, 0x6E, 0x62, 0x65])
  }
}
