import Foundation

/// Swift port of `foldKey` / `foldKeyLines` from
/// `packages/zaghlol_parsing/lib/normalize/text_normalizer.dart` plus Dart's
/// `String.trim()` whitespace set (T-061; same rules as Kotlin `TextFold`).
///
/// Port rules, each pinned by the golden `fold` vectors: the loop runs over
/// UTF-16 code units exactly like Dart; the tables are copied from it; ASCII
/// `A...Z` is lowercased by `+ 0x20` only. Never `lowercased()`,
/// `precomposedStringWithCompatibilityMapping`, `Locale` or `CharacterSet`
/// (Turkish dotted I, the Kelvin sign and Greek look-alikes must stay as they
/// are). Comparisons of folded text use `[UInt16]`, never Swift `String ==`,
/// which applies canonical equivalence and Dart/Kotlin do not.
enum TextFold {
  private static let space: UInt16 = 0x20
  private static let lineFeed: UInt16 = 0x0A

  static func units(_ s: String) -> [UInt16] { Array(s.utf16) }

  static func string(_ units: [UInt16]) -> String { String(decoding: units, as: UTF16.self) }

  /// Digits, separators, invisible marks, tatweel/harakat, letter variants,
  /// ASCII lowercase, whitespace runs to one space, trimmed.
  static func foldKey(_ input: [UInt16]) -> [UInt16] { transform(input, lines: false) }

  /// `foldKey`, except a whitespace run that contains a line break becomes
  /// one `\n`. `foldKeyLines(x)` with `\n` replaced by a space equals
  /// `foldKey(x)` for every `x` (tested). Used only for the global drop
  /// patterns.
  static func foldKeyLines(_ input: [UInt16]) -> [UInt16] { transform(input, lines: true) }

  /// Dart's `String.trim()` on UTF-16 code units. Swift's trimming sets
  /// differ (they trim by Unicode property), so they are never used on a
  /// Guard source.
  static func dartTrim(_ input: [UInt16]) -> [UInt16] {
    var start = 0
    var end = input.count
    while start < end && isDartTrimWhitespace(input[start]) { start += 1 }
    while end > start && isDartTrimWhitespace(input[end - 1]) { end -= 1 }
    if start == 0 && end == input.count { return input }
    return Array(input[start..<end])
  }

  /// The code units Dart's `String.trim()` removes.
  static func isDartTrimWhitespace(_ u: UInt16) -> Bool {
    return (u >= 0x09 && u <= 0x0D) || u == 0x20 || u == 0x85 || u == 0xA0 || u == 0x1680
      || (u >= 0x2000 && u <= 0x200A) || u == 0x2028 || u == 0x2029 || u == 0x202F
      || u == 0x205F || u == 0x3000 || u == 0xFEFF
  }

  private static func transform(_ input: [UInt16], lines: Bool) -> [UInt16] {
    var out = [UInt16]()
    out.reserveCapacity(input.count)
    var pendingSpace = false
    var pendingBreak = false
    var wroteAny = false
    for c in input {
      if isSpace(c) {
        pendingSpace = true
        if lines && isLineBreak(c) { pendingBreak = true }
        continue
      }
      if isInvisible(c) || isMatchingMark(c) { continue }
      if pendingSpace && wroteAny { out.append(pendingBreak ? lineFeed : space) }
      pendingSpace = false
      pendingBreak = false
      wroteAny = true
      out.append(foldLetter(mapChar(c)))
    }
    return out
  }

  private static func isSpace(_ u: UInt16) -> Bool {
    return u == 0x20 || (u >= 0x09 && u <= 0x0D) || u == 0x85 || u == 0xA0 || u == 0x202F
      || u == 0x2009 || u == 0x2028 || u == 0x2029
  }

  /// LF, VT, FF, CR, NEL, LINE SEPARATOR, PARAGRAPH SEPARATOR. Tab is not one.
  private static func isLineBreak(_ u: UInt16) -> Bool {
    return (u >= 0x0A && u <= 0x0D) || u == 0x85 || u == 0x2028 || u == 0x2029
  }

  private static func isInvisible(_ u: UInt16) -> Bool {
    return (u >= 0x200B && u <= 0x200F) || (u >= 0x202A && u <= 0x202E)
      || (u >= 0x2066 && u <= 0x2069) || u == 0x061C || u == 0x2060 || u == 0x00AD || u == 0xFEFF
  }

  private static func isMatchingMark(_ u: UInt16) -> Bool {
    return u == 0x0640 || (u >= 0x064B && u <= 0x0652) || u == 0x0670
  }

  private static func mapChar(_ u: UInt16) -> UInt16 {
    if u >= 0x0660 && u <= 0x0669 { return 0x30 + (u - 0x0660) }
    if u >= 0x06F0 && u <= 0x06F9 { return 0x30 + (u - 0x06F0) }
    if u == 0x066B { return 0x2E }
    if u == 0x066C { return 0x2C }
    return u
  }

  private static func foldLetter(_ u: UInt16) -> UInt16 {
    if u == 0x0623 || u == 0x0625 || u == 0x0622 || u == 0x0671 { return 0x0627 }
    if u == 0x0649 { return 0x064A }
    if u == 0x0629 { return 0x0647 }
    if u >= 0x41 && u <= 0x5A { return u + 0x20 }
    return u
  }
}
