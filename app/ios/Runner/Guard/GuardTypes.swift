import Foundation

// T-061: value types of the Swift Capture Guard. Swift port of
// `packages/zaghlol_parsing/lib/guard/guard_types.dart` (and the Kotlin
// `GuardTypes.kt`). Wire names are shared with Dart, Kotlin and the golden
// file. Nothing in this directory logs, prints or wraps message text.

/// A capture channel. Raw values are the wire names.
enum GuardChannel: String {
  case sms
  case notification
  case shortcutMessage = "shortcut_message"
  case applePay = "apple_pay"
  /// User-initiated share/paste: both platforms skip the Guard for it; the
  /// case exists so the Guard has an answer (`generic` keep).
  case share

  var wire: String { rawValue }
}

/// The only channels iOS capture passes to the native Guard: the Shortcuts
/// Message automation and the Wallet transaction automation. `share` skips
/// the Guard by design; iOS has no SMS or notification capture.
enum IosGuardChannel {
  case shortcutMessage
  case applePay

  var channel: GuardChannel {
    switch self {
    case .shortcutMessage: return .shortcutMessage
    case .applePay: return .applePay
    }
  }
}

/// Channels an ignore rule can name (database `ignore_rules.channel`).
enum GuardIgnoreChannel: String {
  case sms
  case notification
  case applePay = "apple_pay"
}

/// The ignore-rule channel a message on `channel` is checked against, or nil
/// when ignore rules do not apply (`share`). `shortcut_message` maps to `sms`
/// per `GuardPolicy.shortcutMessageUsesSmsToggle` (PO Q5).
func guardIgnoreChannel(_ channel: GuardChannel) -> GuardIgnoreChannel? {
  switch channel {
  case .sms: return .sms
  case .shortcutMessage: return GuardPolicy.shortcutMessageUsesSmsToggle ? .sms : nil
  case .notification: return .notification
  case .applePay: return .applePay
  case .share: return nil
  }
}

/// Why a message was not kept (Dart `GuardDropReason.wire`).
enum GuardDropReason: String {
  case unknownChannel = "unknown_channel"
  case emptyBody = "empty_body"
  case tooLong = "too_long"
  case notFinancial = "not_financial"
  case otpOrPromoInst = "otp_or_promo_inst"
  case otpOrPromoGlobal = "otp_or_promo_global"
  case ignoredInstitution = "ignored_institution"
  case ignoredCard = "ignored_card"
  case configInvalid = "config_invalid"
  case rateLimited = "rate_limited"
}

/// How a kept message was recognised (Dart `GuardKeepKind.wire`).
enum GuardKeepKind: String {
  /// Registry sender, package or wallet card name: `inst` is set.
  case registry
  /// A sender the user chose to capture.
  case user
  /// Always-capture list, a sender-less channel, or sender and body hints.
  case generic
}

/// The Guard's answer for one message. `description` never prints `last4`
/// (financial data).
enum GuardDecision: Equatable, CustomStringConvertible {
  case keep(kind: GuardKeepKind, inst: String?, last4: String?)
  case drop(GuardDropReason)

  var description: String {
    switch self {
    case .keep(let kind, _, _): return "GuardKeep(\(kind.rawValue))"
    case .drop(let reason): return "GuardDrop(\(reason.rawValue))"
    }
  }

  /// The golden `expect` shape as one comparable string:
  /// `drop|<reason>` or `keep|<kind>|<inst or ~>|<last4 or ~>`.
  var goldenForm: String {
    switch self {
    case .keep(let kind, let inst, let last4):
      return "keep|\(kind.rawValue)|\(inst ?? "~")|\(last4 ?? "~")"
    case .drop(let reason):
      return "drop|\(reason.rawValue)"
    }
  }
}

/// What the Guard does when the user part can not be used (PO Q1).
enum GuardUserConfigFailure {
  /// Keep messages with the bundled base rules only (`baseOnly`).
  case keepWithBase
  /// Drop everything until the app rewrites the config (`invalid`).
  case dropAll
}

/// Capture Guard policy decisions, mirroring Dart `guard_policy.dart` and
/// Kotlin `GuardPolicy`. Every value is a provisional default awaiting PO
/// confirmation; changing one means changing the Dart constant, the Kotlin
/// constant, this one and the golden cases that pin it, together.
enum GuardPolicy {
  /// PO Q1: an undecryptable, malformed or unknown-version user part keeps
  /// bank messages with the bundled rules (`baseOnly` + diag `CONFIG_INVALID`).
  static let userConfigFailure: GuardUserConfigFailure = .keepWithBase

  /// PO Q5: the per-card "SMS" toggle also governs `shortcut_message`.
  static let shortcutMessageUsesSmsToggle = true
}
