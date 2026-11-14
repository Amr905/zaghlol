// T-064 (FR-ING-I-07, EC-14): per-automation setup check. The Shortcuts
// Message automations and the Wallet Transaction automation each record when
// they last ran (natively, times only). An automation the OS disabled, or
// that never got turned on, never runs again, so it looks like silence: the
// same 7-day rule as the overall checker (`deriveIosSetupStatus`, T-066),
// applied to each automation's own last-run time. Pure; no sender, keyword,
// message or amount.

import 'ios_setup_checker.dart';

enum ShortcutAutomation { message, wallet }

final class ShortcutAutomationCheck {
  const ShortcutAutomationCheck(
    this.automation,
    this.status, {
    required this.neverRan,
  });

  final ShortcutAutomation automation;
  final IosSetupStatus status;

  /// No run was ever recorded (it was never enabled, or was disabled at once).
  final bool neverRan;

  /// Flagged: silent for [kIosSilenceDays] or more.
  bool get flagged => status.shouldNudge;

  @override
  bool operator ==(Object other) =>
      other is ShortcutAutomationCheck &&
      other.automation == automation &&
      other.status == status &&
      other.neverRan == neverRan;

  @override
  int get hashCode => Object.hash(automation, status, neverRan);
}

final class ShortcutSetupReport {
  const ShortcutSetupReport(this.message, this.wallet);

  final ShortcutAutomationCheck message;
  final ShortcutAutomationCheck wallet;

  /// The automations to tell the user to check, message first.
  List<ShortcutAutomation> get flagged => [
    if (message.flagged) ShortcutAutomation.message,
    if (wallet.flagged) ShortcutAutomation.wallet,
  ];

  bool get allOk => flagged.isEmpty;
}

/// [lastMessageIntentAtMs] / [lastWalletIntentAtMs]: the native run times
/// (null = never). [baselineAtMs]: as in `deriveIosSetupStatus`; with neither
/// a run nor a baseline an automation is `unknown`, not flagged.
ShortcutSetupReport deriveShortcutSetupReport({
  required int nowMs,
  int? lastMessageIntentAtMs,
  int? lastWalletIntentAtMs,
  int? baselineAtMs,
}) {
  ShortcutAutomationCheck check(ShortcutAutomation a, int? last) =>
      ShortcutAutomationCheck(
        a,
        deriveIosSetupStatus(
          nowMs: nowMs,
          lastCaptureAtMs: last,
          baselineAtMs: baselineAtMs,
        ),
        neverRan: last == null,
      );
  return ShortcutSetupReport(
    check(ShortcutAutomation.message, lastMessageIntentAtMs),
    check(ShortcutAutomation.wallet, lastWalletIntentAtMs),
  );
}
