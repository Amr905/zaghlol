/// Capture Guard policy decisions (T-035).
///
/// Every value here is a **provisional default** from the T-035 design note,
/// awaiting PO confirmation (questions Q1 to Q6). Each question has exactly
/// one decision point, named below; changing a decision means changing that
/// one constant (or data list) and the golden cases that pin it.
library;

/// What the Guard does when the user part of the config can not be used
/// (undecryptable, malformed, unknown version). PO Q1.
enum GuardUserConfigFailure {
  /// Keep messages using the bundled base rules only (`baseOnly` mode).
  keepWithBase,

  /// Drop everything until the app rewrites the config (`invalid` mode).
  dropAll,
}

/// PO Q1 (provisional): keep bank messages using the bundled rules.
const GuardUserConfigFailure kGuardUserConfigFailure =
    GuardUserConfigFailure.keepWithBase;

/// Marker only, not read by code. PO Q2 (provisional): a message carrying
/// both a one-time code and a transaction is dropped. The decision point is
/// data, not code: the global `drop` patterns in the registry's
/// `shared.json` (keyword within a short sentence-bounded gap of a 4-8 digit
/// code, platform-channels §1.2). Recorded here so the decision is findable;
/// the golden cases `otp.en.with_transaction` and `otp.en.code_after_amount`
/// pin it.
const bool kGuardDropsOtpWithTransaction = true;

/// PO Q3 (provisional): more than this many kept messages from one
/// `(channel, sender)` within a sliding 60 s window are dropped as
/// `rate_limited`. Exported in the base config as `rate.perSenderPerMin`.
const int kGuardRatePerSenderPerMinute = 20;

/// PO Q4 (provisional): after Gold lapses, senders of the user's custom
/// templates are still captured (as user-sender messages, which always go to
/// review), not dropped. Read by `buildGuardUserConfig`.
const bool kCaptureCustomTemplateSendersWithoutGold = true;

/// PO Q5 (provisional): on iOS the per-card "SMS" capture toggle also
/// governs messages arriving through the Shortcuts Message automation, so a
/// `shortcut_message` is checked against `sms` ignore rules. Read by
/// `guardIgnoreChannel`.
const bool kShortcutMessageUsesSmsToggle = true;

/// Marker only, not read by code. PO Q6 (provisional): promotional
/// messages are dropped only by an institution's own `drop` patterns; there
/// is no global promo list (generic promo words collide with transaction
/// words: `خصم` is "debit"). This is a data rule for registry authors (a lint
/// can not tell a promo pattern from an OTP one); the golden case
/// `promo.no_inst_pattern_kept` pins it.
const bool kGuardPromoDropPerInstitutionOnly = true;
