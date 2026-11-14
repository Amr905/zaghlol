import Foundation

/// What one App Intent run did. Never carries content.
enum IntentCaptureOutcome: Equatable {
  /// The encrypted entry is in the spool.
  case spooled(String)
  /// The Guard dropped the message (not financial, OTP, ignored card, ...).
  case dropped
  /// The spool refused it (full, generic budget or rate); nothing written.
  case refused
  /// Nothing could be written (no container, Keychain or I/O error).
  case failed
}

/// The fixed dialogs an intent can answer with (string-catalog keys). None
/// takes an argument, so a dialog can never carry an amount, a sender or text
/// from the message (lock-screen privacy, ADR-006).
enum IntentDialogKey: String, CaseIterable {
  /// Spooled, and the headless engine stored it.
  case saved = "native_ios_intentDialogSaved"
  /// Spooled; stored on the next open or background refresh.
  case savedForLater = "native_ios_intentDialogSavedForLater"
  /// The Guard dropped it.
  case notFinancial = "native_ios_intentDialogNotBank"
  /// Refused or failed; nothing was kept.
  case notSaved = "native_ios_intentDialogNotSaved"
}

/// T-063: the work behind `LogBankMessageIntent` and
/// `LogWalletTransactionIntent`, without the AppIntents types so XCTest can
/// drive it. Order (ADR-006 addendum): Guard, then the encrypted spool write,
/// and only after a successful write the headless engine. Nothing logs.
final class IntentCapture {
  /// Source of a message when Shortcuts passes no sender (the spool record
  /// needs a non-empty source). Machine data, never shown.
  static let noSender = "shortcut"
  /// Source of a Wallet transaction without a card name.
  static let noCard = "wallet"
  /// Hard bound of the headless run inside `perform()` (ADR-006 addendum:
  /// 8 s until device numbers exist).
  static let headlessTimeoutS: Double = 8

  private let guardRuntime: () -> GuardRuntime?
  private let spool: () -> SpoolRuntime?
  private let runs: () -> IntentRunLog?
  private let headless: () async -> Bool
  private let wallClockMs: () -> Int64

  init(
    guardRuntime: @escaping () -> GuardRuntime? = { CaptureGuardRuntime.shared },
    spool: @escaping () -> SpoolRuntime? = { SpoolRuntime.shared },
    runs: @escaping () -> IntentRunLog? = { IntentCapture.productionRuns },
    headless: @escaping () async -> Bool = {
      await HeadlessIngestion.attempt(timeoutS: IntentCapture.headlessTimeoutS)
    },
    wallClockMs: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
  ) {
    self.guardRuntime = guardRuntime
    self.spool = spool
    self.runs = runs
    self.headless = headless
    self.wallClockMs = wallClockMs
  }

  static let shared = IntentCapture()

  static let productionRuns: IntentRunLog? = {
    guard let container = SpoolLocation.containerURL(), let s = SpoolRuntime.shared else { return nil }
    return IntentRunLog(file: IntentRunLog.file(in: container), cipher: s.cipher)
  }()

  // MARK: Intents

  /// Shortcuts Message automation (`shortcut_message`).
  func logMessage(message: String, sender: String?) async -> IntentDialogKey {
    let source = Self.clean(sender) ?? Self.noSender
    return await run(.message, channel: .shortcutMessage, source: source, body: message)
  }

  /// Shortcuts Transaction (Wallet) automation (`apple_pay`). The body is the
  /// amount and the merchant on two lines (platform-channels section 3); the
  /// card name is the source the Guard maps to an institution.
  func logWallet(amount: String, merchant: String, card: String) async -> IntentDialogKey {
    let body = [Self.clean(amount), Self.clean(merchant)].compactMap { $0 }.joined(separator: "\n")
    return await run(.wallet, channel: .applePay, source: Self.clean(card) ?? Self.noCard, body: body)
  }

  // MARK: Core

  func run(
    _ kind: CaptureIntentKind, channel: IosGuardChannel, source: String, body: String
  ) async -> IntentDialogKey {
    let outcome = capture(channel: channel, source: source, body: body)
    runs()?.record(kind, atMs: wallClockMs())
    switch outcome {
    case .spooled:
      // Only after the write succeeded; the entry stays on every engine outcome.
      return await headless() ? .saved : .savedForLater
    case .dropped:
      return .notFinancial
    case .refused, .failed:
      return .notSaved
    }
  }

  /// Guard, then the spool write. A refused or failed write leaves no entry
  /// (the store removes its `.tmp`).
  func capture(channel: IosGuardChannel, source: String, body: String) -> IntentCaptureOutcome {
    guard let guardRuntime = guardRuntime(), let spool = spool() else { return .failed }
    let cls: SpoolAdmissionClass
    let inst: String?
    let last4: String?
    switch guardRuntime.decide(channel: channel, source: source, body: body) {
    case .drop:
      return .dropped
    case .keep(let kind, let i, let l):
      cls = kind == .generic ? .generic : .priority
      inst = i
      last4 = l
    }
    let record = SpoolRecord(
      channel: channel.channel.wire, source: source, body: body, receivedAtMs: wallClockMs(),
      guardInst: inst, guardLast4: last4,
      rxElapsedNs: Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000))
    do {
      switch try spool.store.write(record, cls: cls) {
      case .written(let id): return .spooled(id)
      case .refused: return .refused
      }
    } catch {
      return .failed
    }
  }

  private static func clean(_ s: String?) -> String? {
    guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
    return t
  }
}
