// T-064 (FR-ING-I-07): the per-automation check reuses the 7-day rule.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/domain/ios_setup_checker.dart';
import 'package:zaghlol/features/capture/domain/ios_shortcut_checker.dart';

const int _day = 24 * 60 * 60 * 1000;
const int _now = 1800000000000;

void main() {
  test('a disabled automation is flagged; a running one is not', () {
    final r = deriveShortcutSetupReport(
      nowMs: _now,
      lastMessageIntentAtMs: _now - 1 * _day,
      lastWalletIntentAtMs: _now - 9 * _day, // turned off 9 days ago
    );
    expect(r.message.status.state, IosSetupState.ok);
    expect(r.wallet.status.state, IosSetupState.silent);
    expect(r.wallet.status.silentDays, 9);
    expect(r.wallet.neverRan, isFalse);
    expect(r.flagged, [ShortcutAutomation.wallet]);
    expect(r.allOk, isFalse);
  });

  test('exactly 7 days is flagged, one hour less is not (same rule)', () {
    expect(
      deriveShortcutSetupReport(
        nowMs: _now,
        lastMessageIntentAtMs: _now - 7 * _day,
        lastWalletIntentAtMs: _now - 7 * _day + 3600000,
      ).flagged,
      [ShortcutAutomation.message],
    );
  });

  test('never ran: flagged only once the baseline is 7 days old', () {
    final young = deriveShortcutSetupReport(
      nowMs: _now,
      baselineAtMs: _now - 2 * _day,
    );
    expect(young.allOk, isTrue);
    expect(young.message.neverRan, isTrue);
    final old = deriveShortcutSetupReport(
      nowMs: _now,
      baselineAtMs: _now - 8 * _day,
    );
    expect(old.flagged, [
      ShortcutAutomation.message,
      ShortcutAutomation.wallet,
    ]);
    expect(old.message.neverRan, isTrue);
  });

  test('no run and no baseline: cannot tell, not flagged', () {
    final r = deriveShortcutSetupReport(nowMs: _now);
    expect(r.message.status.state, IosSetupState.unknown);
    expect(r.allOk, isTrue);
  });
}
