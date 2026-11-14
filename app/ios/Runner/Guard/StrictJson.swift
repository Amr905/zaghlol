import Foundation

/// A parsed JSON object that keeps insertion order. A duplicate key keeps
/// its first position and takes the last value, like Dart's map.
struct GuardJsonObject {
  private(set) var keys: [String] = []
  private(set) var values: [String: GuardJsonValue] = [:]

  mutating func set(_ key: String, _ value: GuardJsonValue) {
    if values[key] == nil { keys.append(key) }
    values[key] = value
  }
}

enum GuardJsonValue {
  case null
  case bool(Bool)
  /// A number without fraction or exponent that fits in 64 bits.
  case int(Int64)
  /// Any other number (Dart: `4.0`, `1e2` and integers beyond 64 bits are
  /// `double`), so the reader's integer check rejects it.
  case double(Double)
  case string(String)
  case array([GuardJsonValue])
  case object(GuardJsonObject)
}

/// Malformed JSON. Carries nothing from the input.
struct StrictJsonError: Error {}

/// A strict RFC 8259 JSON reader for the Guard config (Swift port of Kotlin
/// `StrictJson`, T-038 design note section 3), matching Dart's `jsonDecode`
/// on everything the config reader can observe: no trailing commas, single
/// quotes, unquoted names, leading zeros, comments, raw control characters in
/// strings, `NaN`/`Infinity`; only space, tab, LF and CR are whitespace.
/// Nesting deeper than `maxDepth` is an error. `JSONSerialization` is not
/// used: it is lenient about duplicates and numbers.
///
/// Known, accepted difference: a lone surrogate escape (`"\ud800"`) is
/// accepted but becomes U+FFFD in a Swift `String`.
enum StrictJson {
  static let maxDepth = 16

  static func parse(_ text: [UInt16]) throws -> GuardJsonValue {
    var p = Parser(s: text)
    p.skipWs()
    let v = try p.value(0)
    p.skipWs()
    if p.pos != text.count { throw StrictJsonError() }
    return v
  }

  private struct Parser {
    let s: [UInt16]
    var pos = 0

    init(s: [UInt16]) { self.s = s }

    mutating func skipWs() {
      while pos < s.count {
        let c = s[pos]
        if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { pos += 1 } else { return }
      }
    }

    func peek() throws -> UInt16 {
      if pos < s.count { return s[pos] }
      throw StrictJsonError()
    }

    mutating func value(_ depth: Int) throws -> GuardJsonValue {
      if pos >= s.count { throw StrictJsonError() }
      let c = s[pos]
      switch c {
      case 0x7B: return try obj(depth + 1)  // {
      case 0x5B: return try arr(depth + 1)  // [
      case 0x22: return .string(try str())  // "
      case 0x74:  // t
        try literal("true")
        return .bool(true)
      case 0x66:  // f
        try literal("false")
        return .bool(false)
      case 0x6E:  // n
        try literal("null")
        return .null
      default:
        if c == 0x2D || (c >= 0x30 && c <= 0x39) { return try num() }
        throw StrictJsonError()
      }
    }

    mutating func literal(_ word: String) throws {
      let w = Array(word.utf16)
      if pos + w.count > s.count { throw StrictJsonError() }
      for i in 0..<w.count where s[pos + i] != w[i] { throw StrictJsonError() }
      pos += w.count
    }

    mutating func obj(_ depth: Int) throws -> GuardJsonValue {
      if depth > StrictJson.maxDepth { throw StrictJsonError() }
      pos += 1  // {
      var map = GuardJsonObject()
      skipWs()
      if try peek() == 0x7D {
        pos += 1
        return .object(map)
      }
      while true {
        skipWs()
        if try peek() != 0x22 { throw StrictJsonError() }
        let key = try str()
        skipWs()
        if try peek() != 0x3A { throw StrictJsonError() }
        pos += 1
        skipWs()
        map.set(key, try value(depth))
        skipWs()
        let c = try peek()
        if c == 0x2C {
          pos += 1
        } else if c == 0x7D {
          pos += 1
          return .object(map)
        } else {
          throw StrictJsonError()
        }
      }
    }

    mutating func arr(_ depth: Int) throws -> GuardJsonValue {
      if depth > StrictJson.maxDepth { throw StrictJsonError() }
      pos += 1  // [
      var list: [GuardJsonValue] = []
      skipWs()
      if try peek() == 0x5D {
        pos += 1
        return .array(list)
      }
      while true {
        skipWs()
        list.append(try value(depth))
        skipWs()
        let c = try peek()
        if c == 0x2C {
          pos += 1
        } else if c == 0x5D {
          pos += 1
          return .array(list)
        } else {
          throw StrictJsonError()
        }
      }
    }

    mutating func str() throws -> String {
      pos += 1  // opening quote
      var out = [UInt16]()
      while true {
        if pos >= s.count { throw StrictJsonError() }
        let c = s[pos]
        pos += 1
        if c == 0x22 { return String(decoding: out, as: UTF16.self) }
        if c == 0x5C {
          if pos >= s.count { throw StrictJsonError() }
          let e = s[pos]
          pos += 1
          switch e {
          case 0x22: out.append(0x22)
          case 0x5C: out.append(0x5C)
          case 0x2F: out.append(0x2F)
          case 0x62: out.append(0x08)  // b
          case 0x66: out.append(0x0C)  // f
          case 0x6E: out.append(0x0A)  // n
          case 0x72: out.append(0x0D)  // r
          case 0x74: out.append(0x09)  // t
          case 0x75: out.append(try hex4())  // u
          default: throw StrictJsonError()
          }
        } else if c < 0x20 {
          throw StrictJsonError()
        } else {
          out.append(c)
        }
      }
    }

    mutating func hex4() throws -> UInt16 {
      if pos + 4 > s.count { throw StrictJsonError() }
      var v: UInt16 = 0
      for i in 0..<4 {
        let c = s[pos + i]
        let d: UInt16
        if c >= 0x30 && c <= 0x39 {
          d = c - 0x30
        } else if c >= 0x61 && c <= 0x66 {
          d = c - 0x61 + 10
        } else if c >= 0x41 && c <= 0x46 {
          d = c - 0x41 + 10
        } else {
          throw StrictJsonError()
        }
        v = v &* 16 &+ d
      }
      pos += 4
      return v
    }

    mutating func num() throws -> GuardJsonValue {
      let start = pos
      if s[pos] == 0x2D { pos += 1 }
      if pos >= s.count { throw StrictJsonError() }
      if s[pos] == 0x30 {
        pos += 1
      } else if s[pos] >= 0x31 && s[pos] <= 0x39 {
        while pos < s.count && s[pos] >= 0x30 && s[pos] <= 0x39 { pos += 1 }
      } else {
        throw StrictJsonError()
      }
      var integral = true
      if pos < s.count && s[pos] == 0x2E {
        integral = false
        pos += 1
        try digits()
      }
      if pos < s.count && (s[pos] == 0x65 || s[pos] == 0x45) {
        integral = false
        pos += 1
        if pos < s.count && (s[pos] == 0x2B || s[pos] == 0x2D) { pos += 1 }
        try digits()
      }
      let text = String(decoding: s[start..<pos], as: UTF16.self)
      if integral, let n = Int64(text) { return .int(n) }
      guard let d = Double(text) else { throw StrictJsonError() }
      return .double(d)
    }

    mutating func digits() throws {
      let start = pos
      while pos < s.count && s[pos] >= 0x30 && s[pos] <= 0x39 { pos += 1 }
      if pos == start { throw StrictJsonError() }
    }
  }
}
