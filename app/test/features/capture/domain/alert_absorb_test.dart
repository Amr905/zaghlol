// T-047 test plan 6 (pure part): absorb planning.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/domain/alert_absorb.dart';

AlertSnapshot snap({
  int seq = 7,
  int missed = 0,
  int decrypt = 0,
  int? first,
  int? keyInv,
}) => AlertSnapshot(
  seq: seq,
  missedNotifications: missed,
  decryptDeleted: decrypt,
  firstMissedSmsAtMs: first,
  keyInvalidatedAtMs: keyInv,
);

const int now = 1700000000000;

AbsorbStore store(AbsorbPlan p) => p as AbsorbStore;

void main() {
  test('an empty snapshot records and clears nothing', () {
    expect(
      planAbsorb(
        snapshot: snap(),
        persisted: PersistedAlerts.empty,
        nowMs: now,
      ),
      isA<AbsorbNothing>(),
    );
  });

  test('counts add up, saturating; decryptDeleted sets unreadable once', () {
    final first = store(
      planAbsorb(
        snapshot: snap(missed: 4, decrypt: 1),
        persisted: PersistedAlerts.empty,
        nowMs: now,
      ),
    );
    expect(first.next.missedNotifications, 4);
    expect(first.next.unreadableAtMs, now);
    expect(first.next.absorbedSeq, 7);
    final second = store(
      planAbsorb(
        snapshot: snap(seq: 8, missed: 2, decrypt: 3),
        persisted: first.next,
        nowMs: now + 5,
      ),
    );
    expect(second.next.missedNotifications, 6);
    expect(second.next.unreadableAtMs, now, reason: 'first time kept');
    final sat = store(
      planAbsorb(
        snapshot: snap(seq: 9, missed: 5),
        persisted: const PersistedAlerts(
          absorbedSeq: 1,
          missedNotifications: kMissedNotificationsCap - 1,
        ),
        nowMs: now,
      ),
    );
    expect(sat.next.missedNotifications, kMissedNotificationsCap);
  });

  test('the same seq twice absorbs once (only the clear is retried)', () {
    final first = store(
      planAbsorb(
        snapshot: snap(missed: 4),
        persisted: PersistedAlerts.empty,
        nowMs: now,
      ),
    );
    final again = planAbsorb(
      snapshot: snap(missed: 4),
      persisted: first.next,
      nowMs: now,
    );
    expect(again, isA<AbsorbRetryClear>());
    expect((again as AbsorbRetryClear).seq, 7);
  });

  test('the race: an alert racing the clear over-counts by at most one '
      'snapshot and never reduces the catch-up request', () {
    final first = store(
      planAbsorb(
        snapshot: snap(missed: 4, first: 5000),
        persisted: PersistedAlerts.empty,
        nowMs: now,
      ),
    );
    // Native now holds old (4) + new (1) under a new seq.
    final raced = store(
      planAbsorb(
        snapshot: snap(seq: 8, missed: 5, first: 5000),
        persisted: first.next,
        nowMs: now,
      ),
    );
    expect(raced.next.missedNotifications, 9, reason: '4 + (4 old + 1 new)');
    expect(raced.next.missedNotifications, lessThanOrEqualTo(4 + 4 + 1));
    expect(raced.next.catchUpFromMs, 5000);
    // A later first-missed time never moves the request forward.
    final later = store(
      planAbsorb(
        snapshot: snap(seq: 9, missed: 1, first: 9000),
        persisted: raced.next,
        nowMs: now,
      ),
    );
    expect(later.next.catchUpFromMs, 5000);
    expect(later.next.catchUpReason, CatchUpReason.missedSms);
  });

  test('keyInvalidated requests a silent catch-up from the default window; '
      'an earlier missed SMS keeps the earlier time', () {
    final p = store(
      planAbsorb(
        snapshot: snap(keyInv: now - 10),
        persisted: PersistedAlerts.empty,
        nowMs: now,
      ),
    );
    expect(
      p.next.catchUpFromMs,
      now - kKeyInvalidatedCatchUpWindow.inMilliseconds,
    );
    expect(p.next.catchUpReason, CatchUpReason.keyInvalidated);
    expect(p.next.unreadableAtMs, isNull, reason: 'no notice without decrypt');
    expect(p.next.missedNotifications, 0);
    final early = store(
      planAbsorb(
        snapshot: snap(keyInv: now, first: 10),
        persisted: PersistedAlerts.empty,
        nowMs: now,
      ),
    );
    expect(early.next.catchUpFromMs, 10);
  });
}
