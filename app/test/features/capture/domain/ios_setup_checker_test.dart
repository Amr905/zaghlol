// T-066 (FR-ING-I-07, EC-14): the 7-day silence rule.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/domain/ios_setup_checker.dart';

const int _day = 24 * 60 * 60 * 1000;
const int _now = 1800000000000;

void main() {
  test('no capture and no baseline: cannot tell', () {
    final s = deriveIosSetupStatus(nowMs: _now);
    expect(s.state, IosSetupState.unknown);
    expect(s.passes, isNull);
    expect(s.shouldNudge, isFalse);
  });

  test('a capture 6 days 23 hours ago passes; exactly 7 days is silent', () {
    final ok = deriveIosSetupStatus(
      nowMs: _now,
      lastCaptureAtMs: _now - 7 * _day + 3600000,
    );
    expect(ok.state, IosSetupState.ok);
    expect(ok.passes, isTrue);
    final silent = deriveIosSetupStatus(
      nowMs: _now,
      lastCaptureAtMs: _now - 7 * _day,
    );
    expect(silent.state, IosSetupState.silent);
    expect(silent.silentDays, 7);
    expect(silent.shouldNudge, isTrue);
    expect(silent.passes, isFalse);
  });

  test('silentDays counts whole days', () {
    final s = deriveIosSetupStatus(
      nowMs: _now,
      lastCaptureAtMs: _now - 12 * _day - 5000,
    );
    expect(s.silentDays, 12);
  });

  test('never captured: silence counts from the setup baseline', () {
    expect(
      deriveIosSetupStatus(nowMs: _now, baselineAtMs: _now - 3 * _day).state,
      IosSetupState.ok,
      reason: 'a young install is not silent yet',
    );
    expect(
      deriveIosSetupStatus(nowMs: _now, baselineAtMs: _now - 8 * _day).state,
      IosSetupState.silent,
    );
  });

  test('the last capture wins over an older baseline', () {
    final s = deriveIosSetupStatus(
      nowMs: _now,
      lastCaptureAtMs: _now - _day,
      baselineAtMs: _now - 30 * _day,
    );
    expect(s.state, IosSetupState.ok);
  });

  test('a capture dated in the future (clock change) is not silent', () {
    final s = deriveIosSetupStatus(nowMs: _now, lastCaptureAtMs: _now + _day);
    expect(s.state, IosSetupState.ok);
  });
}
