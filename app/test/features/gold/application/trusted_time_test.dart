// T-144: trusted-time rules of backend-api §4.3 on a fake clock.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/gold/application/trusted_time.dart';

import '../../../core/backend/backend_test_support.dart';
import 'entitlement_harness.dart';

Future<(TrustedTime, FakeClock)> _anchored({int? boot}) async {
  final clock = FakeClock(wall: t0, boot: boot);
  final t = TrustedTime(store: FakeBackendStore([]), clock: clock);
  await t.reanchor(serverTimeMs: t0, reading: await clock.sample());
  return (t, clock);
}

void main() {
  test('rollback while offline is flagged, hw is not lowered, a fresh echo '
      'recovers', () async {
    final (t, c) = await _anchored(boot: 3);
    c.pass(hour);
    c.wall -= 2 * day; // user sets the clock back
    final s = await t.advance();
    expect(s.tampered, isTrue);
    expect(s.hw, greaterThanOrEqualTo(t0 + hour));
    await t.reanchor(serverTimeMs: c.wall + 2 * day);
    final r = await t.peek();
    expect(r!.tampered, isFalse);
  });

  test('backward NTP adjustment under 10 minutes has no effect', () async {
    final (t, c) = await _anchored(boot: 3);
    c.pass(2 * hour);
    c.wall -= 9 * minute;
    final s = await t.advance();
    expect(s.tampered, isFalse);
  });

  test('a forward jump only raises lb/hw; the honest correction then flags '
      'it until a fresh echo', () async {
    final (t, c) = await _anchored(boot: 3);
    c.pass(hour);
    c.wall += 3 * day;
    var s = await t.advance();
    expect(s.tampered, isFalse);
    expect(s.hw, greaterThanOrEqualTo(t0 + 3 * day));
    c.pass(minute);
    c.wall -= 3 * day;
    s = await t.advance();
    expect(s.tampered, isTrue);
    await t.reanchor(serverTimeMs: c.wall);
    expect((await t.peek())!.tampered, isFalse);
    expect((await t.peek())!.hw, c.wall);
  });

  test('Android reboot (BOOT_COUNT change): 6 h charge to hw only', () async {
    final (t, c) = await _anchored(boot: 3);
    c.pass(10 * minute);
    await t.advance();
    final before = await t.peek();
    c.pass(20 * minute);
    c.reboot(uptimeMs: 2 * minute);
    c.wall += 0;
    final s = await t.advance();
    expect(s.tampered, isFalse);
    expect(s.hw - before!.hw, greaterThanOrEqualTo(6 * hour));
    expect(s.lb, lessThanOrEqualTo(c.wall));
    expect(s.lb, greaterThanOrEqualTo(c.wall - minute));
  });

  test('iOS reboot (m < mono, no boot count): 6 h minimum charge', () async {
    final (t, c) = await _anchored();
    c.pass(hour);
    await t.advance();
    final before = await t.peek();
    c.wall += 30 * minute;
    c.mono = 3 * minute; // monotonic went backwards: reboot
    final s = await t.advance();
    expect(s.tampered, isFalse);
    expect(s.hw - before!.hw, greaterThanOrEqualTo(6 * hour));
  });

  test('honest quick offline reboot: not tampered now nor on the following '
      '60 s advances', () async {
    final (t, c) = await _anchored(boot: 3);
    c.pass(5 * minute);
    c.reboot(uptimeMs: 0);
    c.pass(2 * minute);
    var s = await t.advance();
    expect(s.tampered, isFalse);
    expect(s.hw, greaterThanOrEqualTo(t0 + 6 * hour));
    expect((s.lb - c.wall).abs(), lessThan(minute));
    for (var i = 0; i < 20; i++) {
      c.pass(minute);
      s = await t.advance();
      expect(s.tampered, isFalse, reason: 'tick $i');
    }
  });

  test('iOS wall correction without reboot: charge max(m - mono, 6 h); '
      'tamper decided on lb + (m - mono)', () async {
    final (t, c) = await _anchored();
    c.pass(3 * hour);
    await t.advance();
    final before = await t.peek();
    // 4 h pass; NITZ moves the wall clock +2 h (boot reference shifts 2 h).
    c.pass(4 * hour);
    c.wall += 2 * hour;
    final s = await t.advance();
    expect(s.tampered, isFalse);
    expect(s.hw - before!.hw, 6 * hour); // max(4 h, 6 h), not m
    // Same shift but the wall clock is wrong the other way (-2 h): tamper.
    final (t2, c2) = await _anchored();
    c2.pass(3 * hour);
    await t2.advance();
    c2.pass(4 * hour);
    c2.wall -= 2 * hour;
    expect((await t2.advance()).tampered, isTrue);
  });

  test('Android with a null bootCount uses the monotonic-drop rule '
      '(FU-128)', () async {
    final (t, c) = await _anchored(); // boot null
    c.pass(hour);
    await t.advance();
    final before = await t.peek();
    c.mono = minute;
    c.wall += minute;
    final s = await t.advance();
    expect(s.hw - before!.hw, greaterThanOrEqualTo(6 * hour));
  });

  test('an unreadable record is treated as tampered, not as absent', () async {
    final store = FakeBackendStore([]);
    store.values[trustedTimeStateKey] = Uint8List.fromList([1, 2, 3]);
    final t = TrustedTime(
      store: store,
      clock: FakeClock(wall: t0),
    );
    expect((await t.advance()).tampered, isTrue);
  });
}
