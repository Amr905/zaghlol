import Foundation

/// The Capture Guard (platform-channels section 1.2): decides whether a
/// message may be written anywhere. Swift port of
/// `packages/zaghlol_parsing/lib/guard/capture_guard.dart` (and Kotlin
/// `CaptureGuard`); parity is proven by the shared golden file.
///
/// Pure: no I/O, no logging, no mutable state; safe from any thread. A nil
/// `config` (mode `invalid`) drops everything as `config_invalid`. Nothing
/// from the input is kept, printed or reported.
final class CaptureGuard {
  /// Longest raw body (UTF-16 code units) the Guard looks at.
  static let maxBodyLength = 4000
  /// Longest raw source (Dart `kGuardMaxSourceLength`).
  static let maxSourceLength = 256

  let config: GuardConfig?

  init(config: GuardConfig?) { self.config = config }

  /// Decides one message. Total: never throws, never traps on input.
  func decide(channel channelWire: String, source: String, body: String) -> GuardDecision {
    guard let cfg = config else { return .drop(.configInvalid) }
    // Step 0: cheap checks before any fold or regex. Lengths are UTF-16 code units.
    guard let channel = GuardChannel(rawValue: channelWire) else {
      return .drop(.unknownChannel)
    }
    if body.utf16.count > CaptureGuard.maxBodyLength
      || source.utf16.count > CaptureGuard.maxSourceLength
    {
      return .drop(.tooLong)
    }
    // One fold that keeps line breaks for the global drop patterns; every
    // other pattern runs on the same text with each `\n` as a space.
    let linesUnits = TextFold.foldKeyLines(TextFold.units(body))
    let foldedUnits = linesUnits.map { $0 == 0x0A ? 0x20 : $0 }
    if foldedUnits.isEmpty { return .drop(.emptyBody) }
    let lines = GuardSubject(units: linesUnits)
    let folded = GuardSubject(units: foldedUnits)

    // Step 1: resolve the source.
    let sourceKey = GuardConfig.sourceKey(channel, source)
    let inst = resolve(cfg, channel, sourceKey)
    let kind: GuardKeepKind
    if inst != nil {
      kind = .registry
    } else if !sourceKey.isEmpty
      && cfg.userSenders.contains(GuardUserSender(channel: channel.wire, key: sourceKey))
    {
      // FU-109 / FU-121: a user-added SMS sender that looks like a phone
      // number is captured only when the body looks financial (the generic
      // `bodyHints`); otherwise dropped here. Alphanumeric user senders keep
      // their behaviour. iOS has no SMS channel, so this is dead on iOS
      // today but kept so the decisions equal Dart and Kotlin for the same
      // config (the golden file pins it).
      if false && channel == .sms && CaptureGuard.isPhoneNumberShape(sourceKey)
        && !cfg.bodyHints.contains(where: { $0.hasMatch(folded) })
      {
        return .drop(.notFinancial)
      }
      kind = .user
    } else if isGeneric(cfg, channel, sourceKey, folded) {
      kind = .generic
    } else {
      kind = .generic  // MUTATION A: keep what is not financial
    }

    // Step 2: OTP / promo. Institution patterns on `folded`, global ones on `lines`.
    if let i = inst, let patterns = cfg.dropByInst[i], patterns.contains(where: { $0.hasMatch(folded) }) {
      return .drop(.otpOrPromoInst)
    }
    if cfg.globalDrop.contains(where: { $0.hasMatch(lines) }) {
      return .drop(.otpOrPromoGlobal)
    }
    guard let instCode = inst else { return .keep(kind: kind, inst: nil, last4: nil) }

    // Step 3: institution-level ignore.
    let ignoreCh = guardIgnoreChannel(channel)
    if let ch = ignoreCh, cfg.ignore.contains(GuardIgnoreKey(inst: instCode, last4: nil, ch: ch)) {
      return .drop(.ignoredInstitution)
    }

    // Step 4: card-level ignore, always keyed by institution (EC-59).
    let last4 = guardLast4(cfg, instCode, folded)
    if let ch = ignoreCh, let l = last4,
      cfg.ignore.contains(GuardIgnoreKey(inst: instCode, last4: l, ch: ch))
    {
      return .drop(.ignoredCard)
    }

    // Step 5.
    return .keep(kind: kind, inst: instCode, last4: last4)
  }

  /// Step 1, generic recognition: an always-capture id (never for a
  /// notification package), a sender-less channel, or a sender hint on the
  /// key together with a body hint on the folded body.
  private func isGeneric(
    _ cfg: GuardConfig, _ channel: GuardChannel, _ sourceKey: [UInt16], _ folded: GuardSubject
  ) -> Bool {
    if !sourceKey.isEmpty && channel != .notification && cfg.alwaysCapture.contains(sourceKey) {
      return true
    }
    if channel == .applePay || channel == .shortcutMessage || channel == .share { return true }
    if sourceKey.isEmpty { return false }
    if !matchesAnyUnits(cfg.senderHints, sourceKey) { return false }
    return cfg.bodyHints.contains(where: { $0.hasMatch(folded) })
  }

  /// A phone-number sender: optional `+`, then a digit, then at least five of
  /// digits, spaces, dashes or brackets (Dart `_phoneNumberShape`
  /// `^\+?[0-9][0-9 ()-]{5,}$`), as a loop on the folded key.
  static func isPhoneNumberShape(_ key: [UInt16]) -> Bool {
    var i = 0
    if i < key.count && key[i] == 0x2B { i += 1 }
    if i >= key.count || !(key[i] >= 0x30 && key[i] <= 0x39) { return false }
    i += 1
    if key.count - i < 5 { return false }
    for c in key[i...] {
      let ok = (c >= 0x30 && c <= 0x39) || c == 0x20 || c == 0x28 || c == 0x29 || c == 0x2D
      if !ok { return false }
    }
    return true
  }

  private func matchesAnyUnits(_ patterns: [GuardRegex], _ units: [UInt16]) -> Bool {
    let subject = GuardSubject(units: units)
    return patterns.contains(where: { $0.hasMatch(subject) })
  }

  private func resolve(_ cfg: GuardConfig, _ channel: GuardChannel, _ sourceKey: [UInt16])
    -> String?
  {
    if sourceKey.isEmpty { return nil }
    switch channel {
    case .notification:
      return cfg.packages[sourceKey]
    case .sms, .shortcutMessage:
      if let exact = cfg.exactSenders[sourceKey] { return exact }
      let subject = GuardSubject(units: sourceKey)
      for (regex, inst) in cfg.senderRegexes where regex.hasMatch(subject) { return inst }
      return nil
    case .applePay:
      // Longest card name contained in the folded source; a tie between two
      // institutions resolves to none.
      var best: String?
      var bestLength = 0
      var tie = false
      for (name, inst) in cfg.wallet {
        if !CaptureGuard.contains(sourceKey, name) { continue }
        if name.count > bestLength {
          best = inst
          bestLength = name.count
          tie = false
        } else if name.count == bestLength && inst != best {
          tie = true
        }
      }
      return tie ? nil : best
    case .share:
      return nil
    }
  }

  /// UTF-16 code unit substring test (never Swift `String.contains`, whose
  /// canonical equivalence differs from Dart and Kotlin).
  static func contains(_ haystack: [UInt16], _ needle: [UInt16]) -> Bool {
    if needle.isEmpty { return true }
    if needle.count > haystack.count { return false }
    var i = 0
    while i + needle.count <= haystack.count {
      var j = 0
      while j < needle.count && haystack[i + j] == needle[j] { j += 1 }
      if j == needle.count { return true }
      i += 1
    }
    return false
  }
}

/// The last-4 the Guard reads for `inst` from a folded body (Dart
/// `guardLast4`): institution patterns, then the `*` patterns; for each
/// pattern only its first match is looked at, and its group 1 is taken when
/// it is exactly four ASCII digits, otherwise the next pattern is tried.
func guardLast4(_ cfg: GuardConfig, _ inst: String, _ folded: GuardSubject) -> String? {
  func scan(_ patterns: [GuardRegex]?) -> String? {
    guard let patterns = patterns else { return nil }
    for p in patterns {
      guard let m = p.firstMatch(folded), m.numberOfRanges >= 2,
        let g = folded.group(m, 1)
      else { continue }
      let u = Array(g.utf16)
      if u.count == 4 && u.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) { return g }
    }
    return nil
  }
  return scan(cfg.last4ByInst[inst]) ?? scan(cfg.last4Any)
}
