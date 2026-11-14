import AppIntents
import Foundation

// T-063 (FR-ING-I-01/02, ADR-006): the App Intents the Shortcuts Message and
// Transaction (Wallet) automations call. They live in the Runner target, so
// `perform()` runs in the app process; with `openAppWhenRun = false` iOS
// launches the app in the background when it is closed. The work is in
// `IntentCapture` (Guard, encrypted spool write, then the headless engine).
// Titles, parameters and dialogs come from the string catalog
// (`Localizable.xcstrings`, copy deck section 1.23); no dialog carries an
// amount, a sender or message text. Nothing here logs.

struct LogBankMessageIntent: AppIntent {
  static var title: LocalizedStringResource = "native_ios_intentLogMessageTitle"
  static var description = IntentDescription("native_ios_intentLogMessageDesc")
  static var openAppWhenRun: Bool = false

  @Parameter(title: "native_ios_intentMessageParam")
  var message: String

  /// The Shortcut passes the message's sender when it has one.
  @Parameter(title: "native_ios_intentSenderParam")
  var sender: String?

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let key = await IntentCapture.shared.logMessage(message: message, sender: sender)
    return .result(dialog: IntentDialog(key.resource))
  }
}

struct LogWalletTransactionIntent: AppIntent {
  static var title: LocalizedStringResource = "native_ios_intentLogWalletTitle"
  static var description = IntentDescription("native_ios_intentLogWalletDesc")
  static var openAppWhenRun: Bool = false

  /// As the Wallet automation formats it, e.g. "EGP 450.00"; parsed in Dart.
  @Parameter(title: "native_ios_intentAmountParam")
  var amount: String

  @Parameter(title: "native_ios_intentMerchantParam")
  var merchant: String

  /// The card or pass name; the Guard maps it to an institution
  /// (registry `walletCardNames`).
  @Parameter(title: "native_ios_intentCardParam")
  var card: String

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let key = await IntentCapture.shared.logWallet(amount: amount, merchant: merchant, card: card)
    return .result(dialog: IntentDialog(key.resource))
  }
}

/// Exposes both intents in the Shortcuts app (and Spotlight). The automations
/// themselves come from the signed Zaghlol.shortcut package (T-064).
struct ZaghlolShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: LogBankMessageIntent(),
      phrases: ["Log a bank message in \(.applicationName)"],
      shortTitle: "native_ios_intentLogMessageShort",
      systemImageName: "message")
    AppShortcut(
      intent: LogWalletTransactionIntent(),
      phrases: ["Log an Apple Pay payment in \(.applicationName)"],
      shortTitle: "native_ios_intentLogWalletShort",
      systemImageName: "wallet.pass")
  }
}

extension IntentDialogKey {
  /// Literal keys, so the catalog and the App Intents metadata see them.
  var resource: LocalizedStringResource {
    switch self {
    case .saved: return "native_ios_intentDialogSaved"
    case .savedForLater: return "native_ios_intentDialogSavedForLater"
    case .notFinancial: return "native_ios_intentDialogNotBank"
    case .notSaved: return "native_ios_intentDialogNotSaved"
    }
  }
}
