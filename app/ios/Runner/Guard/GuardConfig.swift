import Foundation

/// What went wrong reading a config part. Raw values are Dart's
/// `GuardConfigErrorCode` names verbatim, so a diag code means the same on
/// every platform.
enum GuardConfigErrorCode: String {
  case tooLarge
  case invalidUtf8
  case invalidJson
  case wrongType
  case unknownKey
  case missingKey
  case badValue
  case badVersion
  case badRegex
  case tooMany
}

/// A config error: a code and a JSON path built from fixed key names and
/// indexes only, never a value (the user part holds institution + last-4
/// pairs, which are financial data).
struct GuardConfigError: Error, CustomStringConvertible {
  let code: GuardConfigErrorCode
  let path: String

  var description: String { "GuardConfigError(\(code.rawValue) at \(path))" }
}

/// Which parts of the config the Guard runs with. Raw values equal Dart's
/// `GuardConfigMode.name`.
enum GuardConfigMode: String {
  /// Base and user parts.
  case full
  /// Base only: user part absent (fresh install) or unusable (PO Q1).
  case baseOnly
  /// Base part unusable: every message is dropped `config_invalid`.
  case invalid
}

/// One ignore rule `(inst, last4|nil, ch)`. `description` prints no value.
struct GuardIgnoreKey: Hashable, CustomStringConvertible {
  let inst: String
  let last4: String?
  let ch: GuardIgnoreChannel

  var description: String { "GuardIgnoreKey" }
}

/// A user sender `(channel, folded source key)`. `description` prints no value.
struct GuardUserSender: Hashable, CustomStringConvertible {
  let channel: String
  let key: [UInt16]

  var description: String { "GuardUserSender" }
}

/// A compiled pattern. Compiled with no options (portable subset,
/// platform-channels section 1.1): case-sensitive, `^`/`$` at the text ends.
/// Matching is a search (`firstMatch`), never a full match.
struct GuardRegex {
  let regex: NSRegularExpression

  func firstMatch(_ subject: GuardSubject) -> NSTextCheckingResult? {
    regex.firstMatch(in: subject.string, options: [], range: subject.range)
  }

  func hasMatch(_ subject: GuardSubject) -> Bool { firstMatch(subject) != nil }
}

/// A folded text plus its UTF-16 range, computed once per message.
struct GuardSubject {
  let string: String
  let range: NSRange

  init(units: [UInt16]) {
    string = String(decoding: units, as: UTF16.self)
    range = NSRange(location: 0, length: units.count)
  }

  /// The text of capture group `index` of `match`, nil if it did not participate.
  func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
    guard index < match.numberOfRanges else { return nil }
    let r = match.range(at: index)
    if r.location == NSNotFound { return nil }
    return (string as NSString).substring(with: r)
  }
}

/// A parsed, compiled Guard config; immutable. Swift port of
/// `packages/zaghlol_parsing/lib/guard/guard_config.dart` and Kotlin
/// `GuardConfig`: same schema, caps, error codes and modes.
final class GuardConfig: CustomStringConvertible {
  let registryVersion: Int
  /// Folded sender id to institution code.
  let exactSenders: [[UInt16]: String]
  let senderRegexes: [(GuardRegex, String)]
  /// Trimmed package name to institution code.
  let packages: [[UInt16]: String]
  /// Folded wallet card name and institution code, in file order.
  let wallet: [([UInt16], String)]
  let globalDrop: [GuardRegex]
  let dropByInst: [String: [GuardRegex]]
  let last4ByInst: [String: [GuardRegex]]
  let last4Any: [GuardRegex]
  let senderHints: [GuardRegex]
  let bodyHints: [GuardRegex]
  let alwaysCapture: Set<[UInt16]>
  let shortcutKeywords: [String]
  let perSenderPerMin: Int
  let ignore: Set<GuardIgnoreKey>
  let userSenders: Set<GuardUserSender>

  fileprivate init(
    registryVersion: Int, exactSenders: [[UInt16]: String],
    senderRegexes: [(GuardRegex, String)], packages: [[UInt16]: String],
    wallet: [([UInt16], String)], globalDrop: [GuardRegex], dropByInst: [String: [GuardRegex]],
    last4ByInst: [String: [GuardRegex]], last4Any: [GuardRegex], senderHints: [GuardRegex],
    bodyHints: [GuardRegex], alwaysCapture: Set<[UInt16]>, shortcutKeywords: [String],
    perSenderPerMin: Int, ignore: Set<GuardIgnoreKey>, userSenders: Set<GuardUserSender>
  ) {
    self.registryVersion = registryVersion
    self.exactSenders = exactSenders
    self.senderRegexes = senderRegexes
    self.packages = packages
    self.wallet = wallet
    self.globalDrop = globalDrop
    self.dropByInst = dropByInst
    self.last4ByInst = last4ByInst
    self.last4Any = last4Any
    self.senderHints = senderHints
    self.bodyHints = bodyHints
    self.alwaysCapture = alwaysCapture
    self.shortcutKeywords = shortcutKeywords
    self.perSenderPerMin = perSenderPerMin
    self.ignore = ignore
    self.userSenders = userSenders
  }

  var description: String { "GuardConfig" }

  fileprivate func withUser(_ user: UserPart) -> GuardConfig {
    GuardConfig(
      registryVersion: registryVersion, exactSenders: exactSenders, senderRegexes: senderRegexes,
      packages: packages, wallet: wallet, globalDrop: globalDrop, dropByInst: dropByInst,
      last4ByInst: last4ByInst, last4Any: last4Any, senderHints: senderHints,
      bodyHints: bodyHints, alwaysCapture: alwaysCapture, shortcutKeywords: shortcutKeywords,
      perSenderPerMin: perSenderPerMin, ignore: user.ignore, userSenders: user.senders)
  }

  fileprivate struct UserPart {
    let ignore: Set<GuardIgnoreKey>
    let senders: Set<GuardUserSender>
  }

  // MARK: Constants

  /// Base schema version (Dart `guardConfigVersion`).
  static let baseVersion = 4
  /// User schema version (Dart `guardUserConfigVersion`).
  static let userVersion = 1
  static let maxBaseBytes = 200 * 1024
  static let maxUserBytes = 64 * 1024
  static let maxIgnoreRules = 1000
  static let maxUserSenders = 200
  static let maxBaseListLength = 5000
  static let maxPatternLength = 600
  static let maxValueLength = 256

  /// Channels a user sender may name (Dart `guardUserSenderChannels`).
  private static let userSenderChannels: Set<GuardChannel> = [
    .sms, .notification, .shortcutMessage, .applePay,
  ]

  // MARK: Parse

  /// Parses the base part and the optional user part (raw bytes as read /
  /// decrypted). Never throws.
  ///
  /// - base unusable -> `.invalid`;
  /// - `user` nil and not `userUnreadable` -> `.baseOnly`;
  /// - user unusable (`userUnreadable`: the file failed authentication; or
  ///   the bytes do not parse) -> per `GuardPolicy.userConfigFailure`
  ///   (PO Q1): `.baseOnly` with `userFailed`, or `.invalid`.
  static func parse(base: Data, user: Data?, userUnreadable: Bool = false) -> GuardConfigLoad {
    let baseConfig: GuardConfig
    do {
      baseConfig = try parseBase(base)
    } catch let e as GuardConfigError {
      return GuardConfigLoad(mode: .invalid, config: nil, baseError: e)
    } catch {
      return GuardConfigLoad(
        mode: .invalid, config: nil, baseError: GuardConfigError(code: .badValue, path: "$"))
    }
    if user == nil && !userUnreadable {
      return GuardConfigLoad(mode: .baseOnly, config: baseConfig)
    }
    var userError: GuardConfigError?
    if let user = user, !userUnreadable {
      do {
        return GuardConfigLoad(mode: .full, config: baseConfig.withUser(try parseUser(user)))
      } catch let e as GuardConfigError {
        userError = e
      } catch {
        userError = GuardConfigError(code: .badValue, path: "$")
      }
    }
    switch GuardPolicy.userConfigFailure {
    case .keepWithBase:
      return GuardConfigLoad(
        mode: .baseOnly, config: baseConfig, userError: userError, userUnreadable: userUnreadable)
    case .dropAll:
      return GuardConfigLoad(
        mode: .invalid, config: nil, userError: userError, userUnreadable: userUnreadable)
    }
  }

  /// Validates a user part on its own (the writer's check before anything is
  /// written). Nil when valid.
  static func validateUser(_ user: Data) -> GuardConfigError? {
    do {
      _ = try parseUser(user)
      return nil
    } catch let e as GuardConfigError {
      return e
    } catch {
      return GuardConfigError(code: .badValue, path: "$")
    }
  }

  /// The source key the Guard compares on `channel` (Dart `guardSourceKey`):
  /// trimmed for a notification package, folded otherwise.
  static func sourceKey(_ channel: GuardChannel, _ source: String) -> [UInt16] {
    let units = TextFold.units(source)
    return channel == .notification ? TextFold.dartTrim(units) : TextFold.foldKey(units)
  }

  // MARK: Reading helpers

  private static func fail(_ code: GuardConfigErrorCode, _ path: String) -> GuardConfigError {
    GuardConfigError(code: code, path: path)
  }

  private static func decode(_ bytes: Data, maxBytes: Int) throws -> GuardJsonObject {
    if bytes.count > maxBytes { throw fail(.tooLarge, "$") }
    var body = bytes
    // Dart's Utf8Decoder drops one leading byte-order mark.
    if body.count >= 3 && body[body.startIndex] == 0xEF && body[body.startIndex + 1] == 0xBB
      && body[body.startIndex + 2] == 0xBF
    {
      body = body.dropFirst(3)
    }
    guard let text = String(data: body, encoding: .utf8) else { throw fail(.invalidUtf8, "$") }
    let json: GuardJsonValue
    do {
      json = try StrictJson.parse(Array(text.utf16))
    } catch {
      throw fail(.invalidJson, "$")
    }
    guard case .object(let obj) = json else { throw fail(.wrongType, "$") }
    return obj
  }

  private static func compile(_ text: String, _ path: String) throws -> GuardRegex {
    do {
      return GuardRegex(regex: try NSRegularExpression(pattern: text, options: []))
    } catch {
      throw fail(.badRegex, path)
    }
  }

  /// `^[a-z][a-z0-9_]{1,31}$` as a loop (no regex `$` semantics to worry about).
  private static func isInstShape(_ v: String) -> Bool {
    let u = Array(v.utf16)
    if u.count < 2 || u.count > 32 { return false }
    if !(u[0] >= 0x61 && u[0] <= 0x7A) { return false }
    for c in u.dropFirst() {
      let ok = (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x5F
      if !ok { return false }
    }
    return true
  }

  private static func isLast4Shape(_ v: String) -> Bool {
    let u = Array(v.utf16)
    return u.count == 4 && u.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
  }

  private static func inst(_ o: Obj, _ key: String) throws -> String {
    let v = try o.string(key)
    if !isInstShape(v) { throw fail(.badValue, "\(o.path).\(key)") }
    return v
  }

  private static func stringAt(_ v: GuardJsonValue, _ path: String, _ maxLength: Int) throws
    -> String
  {
    guard case .string(let s) = v else { throw fail(.wrongType, path) }
    if s.isEmpty || s.utf16.count > maxLength { throw fail(.badValue, path) }
    return s
  }

  private static func objAt(_ v: GuardJsonValue, _ path: String) throws -> Obj {
    guard case .object(let o) = v else { throw fail(.wrongType, path) }
    return Obj(path: path, object: o)
  }

  /// Strict object reader: every key must be read, unknown keys fail (Dart `_Obj`).
  private final class Obj {
    let path: String
    let object: GuardJsonObject
    private var read = Set<String>()

    init(path: String, object: GuardJsonObject) {
      self.path = path
      self.object = object
    }

    func get(_ key: String) throws -> GuardJsonValue {
      read.insert(key)
      guard let v = object.values[key] else {
        throw GuardConfigError(code: .missingKey, path: "\(path).\(key)")
      }
      return v
    }

    func integer(_ key: String, min: Int64 = 0, max: Int64 = 1 << 30) throws -> Int {
      guard case .int(let v) = try get(key) else {
        throw GuardConfigError(code: .wrongType, path: "\(path).\(key)")
      }
      if v < min || v > max { throw GuardConfigError(code: .badValue, path: "\(path).\(key)") }
      return Int(v)
    }

    func string(_ key: String, maxLength: Int = GuardConfig.maxValueLength) throws -> String {
      guard case .string(let v) = try get(key) else {
        throw GuardConfigError(code: .wrongType, path: "\(path).\(key)")
      }
      if v.isEmpty || v.utf16.count > maxLength {
        throw GuardConfigError(code: .badValue, path: "\(path).\(key)")
      }
      return v
    }

    func nullableString(_ key: String) throws -> String? {
      switch try get(key) {
      case .null: return nil
      case .string(let v): return v
      default: throw GuardConfigError(code: .wrongType, path: "\(path).\(key)")
      }
    }

    func list(_ key: String, maxLength: Int) throws -> [GuardJsonValue] {
      guard case .array(let v) = try get(key) else {
        throw GuardConfigError(code: .wrongType, path: "\(path).\(key)")
      }
      if v.count > maxLength { throw GuardConfigError(code: .tooMany, path: "\(path).\(key)") }
      return v
    }

    func obj(_ key: String) throws -> Obj {
      guard case .object(let v) = try get(key) else {
        throw GuardConfigError(code: .wrongType, path: "\(path).\(key)")
      }
      return Obj(path: "\(path).\(key)", object: v)
    }

    func strings(_ key: String, maxLength: Int = GuardConfig.maxValueLength) throws -> [String] {
      let raw = try list(key, maxLength: GuardConfig.maxBaseListLength)
      var out: [String] = []
      for (i, v) in raw.enumerated() {
        out.append(try GuardConfig.stringAt(v, "\(path).\(key)[\(i)]", maxLength))
      }
      return out
    }

    func patterns(_ key: String) throws -> [GuardRegex] {
      let texts = try strings(key, maxLength: GuardConfig.maxPatternLength)
      var out: [GuardRegex] = []
      for (i, t) in texts.enumerated() {
        out.append(try GuardConfig.compile(t, "\(path).\(key)[\(i)]"))
      }
      return out
    }

    func finish() throws {
      for key in object.keys where !read.contains(key) {
        // The key name itself is not echoed: it may be anything.
        throw GuardConfigError(code: .unknownKey, path: path)
      }
    }
  }

  // MARK: Base part

  private static func parseBase(_ bytes: Data) throws -> GuardConfig {
    let r = Obj(path: "$", object: try decode(bytes, maxBytes: maxBaseBytes))
    if try r.integer("v") != baseVersion { throw fail(.badVersion, "$.v") }
    let registryVersion = try r.integer("registryVersion")

    var exact: [[UInt16]: String] = [:]
    var regexes: [(GuardRegex, String)] = []
    let senders = try r.list("senders", maxLength: maxBaseListLength)
    for i in 0..<senders.count {
      let o = try objAt(senders[i], "$.senders[\(i)]")
      let match = try o.string("match")
      let instCode = try inst(o, "inst")
      switch match {
      case "exact":
        let key = TextFold.foldKey(TextFold.units(try o.string("value")))
        if key.isEmpty { throw fail(.badValue, "\(o.path).value") }
        if exact[key] == nil { exact[key] = instCode }
      case "regex":
        let text = try o.string("value", maxLength: maxPatternLength)
        regexes.append((try compile(text, "\(o.path).value"), instCode))
      default:
        throw fail(.badValue, "\(o.path).match")
      }
      try o.finish()
    }

    var packages: [[UInt16]: String] = [:]
    let pkgs = try r.list("packages", maxLength: maxBaseListLength)
    for i in 0..<pkgs.count {
      let o = try objAt(pkgs[i], "$.packages[\(i)]")
      let key = TextFold.dartTrim(TextFold.units(try o.string("value")))
      // Dart `putIfAbsent(key, () => _inst(o, 'inst'))`: for a duplicate
      // package `inst` is never read, so `finish()` fails with `unknownKey`
      // and the whole base is invalid. Mirrored for parity.
      if packages[key] == nil { packages[key] = try inst(o, "inst") }
      try o.finish()
    }

    var wallet: [([UInt16], String)] = []
    let cards = try r.list("wallet", maxLength: maxBaseListLength)
    for i in 0..<cards.count {
      let o = try objAt(cards[i], "$.wallet[\(i)]")
      let name = TextFold.foldKey(TextFold.units(try o.string("name")))
      if name.isEmpty { throw fail(.badValue, "\(o.path).name") }
      wallet.append((name, try inst(o, "inst")))
      try o.finish()
    }

    let drop = try r.obj("drop")
    let globalDrop = try drop.patterns("global")
    let byInstObj = try drop.obj("byInst")
    var dropByInst: [String: [GuardRegex]] = [:]
    for key in byInstObj.object.keys {
      if !isInstShape(key) { throw fail(.badValue, byInstObj.path) }
      dropByInst[key] = try byInstObj.patterns(key)
    }
    try byInstObj.finish()
    try drop.finish()

    let last4Obj = try r.obj("last4")
    var last4ByInst: [String: [GuardRegex]] = [:]
    var last4Any: [GuardRegex] = []
    for key in last4Obj.object.keys {
      if key == "*" {
        last4Any = try last4Obj.patterns(key)
      } else if isInstShape(key) {
        last4ByInst[key] = try last4Obj.patterns(key)
      } else {
        throw fail(.badValue, last4Obj.path)
      }
    }
    try last4Obj.finish()

    let generic = try r.obj("generic")
    let senderHints = try generic.patterns("senderHints")
    let bodyHints = try generic.patterns("bodyHints")
    var always = Set<[UInt16]>()
    for a in try generic.strings("alwaysCapture") { always.insert(TextFold.foldKey(TextFold.units(a))) }
    always.remove([])
    try generic.finish()

    let keywords = try r.strings("shortcutKeywords")
    let rate = try r.obj("rate")
    let perMin = try rate.integer("perSenderPerMin", min: 1, max: 10000)
    try rate.finish()
    try r.finish()

    return GuardConfig(
      registryVersion: registryVersion, exactSenders: exact, senderRegexes: regexes,
      packages: packages, wallet: wallet, globalDrop: globalDrop, dropByInst: dropByInst,
      last4ByInst: last4ByInst, last4Any: last4Any, senderHints: senderHints,
      bodyHints: bodyHints, alwaysCapture: always, shortcutKeywords: keywords,
      perSenderPerMin: perMin, ignore: [], userSenders: [])
  }

  // MARK: User part

  private static func parseUser(_ bytes: Data) throws -> UserPart {
    let r = Obj(path: "$", object: try decode(bytes, maxBytes: maxUserBytes))
    if try r.integer("v") != userVersion { throw fail(.badVersion, "$.v") }
    _ = try r.integer("baseRegistryVersion")
    var ignore = Set<GuardIgnoreKey>()
    let rules = try r.list("ignore", maxLength: maxIgnoreRules)
    for i in 0..<rules.count {
      let o = try objAt(rules[i], "$.ignore[\(i)]")
      let instCode = try inst(o, "inst")
      let last4 = try o.nullableString("last4")
      if let l = last4, !isLast4Shape(l) { throw fail(.badValue, "\(o.path).last4") }
      guard let ch = GuardIgnoreChannel(rawValue: try o.string("ch")) else {
        throw fail(.badValue, "\(o.path).ch")
      }
      try o.finish()
      ignore.insert(GuardIgnoreKey(inst: instCode, last4: last4, ch: ch))
    }
    var senders = Set<GuardUserSender>()
    let list = try r.list("userSenders", maxLength: maxUserSenders)
    for i in 0..<list.count {
      let o = try objAt(list[i], "$.userSenders[\(i)]")
      let value = try o.string("value")
      guard let ch = GuardChannel(rawValue: try o.string("ch")), userSenderChannels.contains(ch)
      else { throw fail(.badValue, "\(o.path).ch") }
      try o.finish()
      let key = sourceKey(ch, value)
      if key.isEmpty { throw fail(.badValue, "\(o.path).value") }
      senders.insert(GuardUserSender(channel: ch.wire, key: key))
    }
    try r.finish()
    return UserPart(ignore: ignore, senders: senders)
  }
}

/// The outcome of `GuardConfig.parse`. `description` prints the mode and
/// error codes only.
struct GuardConfigLoad: CustomStringConvertible {
  let mode: GuardConfigMode
  /// Nil exactly when `mode` is `.invalid`.
  let config: GuardConfig?
  var baseError: GuardConfigError?
  /// Set when user bytes were given but did not parse.
  var userError: GuardConfigError?
  /// The user file failed authentication (caller-reported).
  var userUnreadable: Bool

  init(
    mode: GuardConfigMode, config: GuardConfig?, baseError: GuardConfigError? = nil,
    userError: GuardConfigError? = nil, userUnreadable: Bool = false
  ) {
    self.mode = mode
    self.config = config
    self.baseError = baseError
    self.userError = userError
    self.userUnreadable = userUnreadable
  }

  /// A user part was present but can not be used (diag `CONFIG_INVALID`).
  var userFailed: Bool { userError != nil || userUnreadable }

  var description: String {
    "GuardConfigLoad(\(mode.rawValue), base=\(baseError?.code.rawValue ?? "-"), "
      + "user=\(userError?.code.rawValue ?? "-"), unreadable=\(userUnreadable))"
  }
}
