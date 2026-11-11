// T-047 (design note §2, "Absorb-then-clear"): the app owns the durable
// alert state, native is a mailbox. Pure: given a status read and what the
// app already stored, decide what to store and whether to clear.
//
// Order the caller must keep: persist [AbsorbPlan.next] in one transaction,
// then `clearSpoolAlerts(seq)`. A crash between them repeats the clear only
// (same seq). Residual: an alert racing the clear leaves old + new in
// native, and the next read adds the old counts again to the informational
// missed-notification count (over-count by at most one snapshot); the
// catch-up request is a `min` and the flags are idempotent.

/// Why a catch-up scan was requested.
enum CatchUpReason { missedSms, keyInvalidated }

/// What native reported (counts and times only).
final class AlertSnapshot {
  const AlertSnapshot({
    required this.seq,
    required this.missedNotifications,
    required this.decryptDeleted,
    this.firstMissedSmsAtMs,
    this.keyInvalidatedAtMs,
  });

  final int seq;
  final int missedNotifications;
  final int decryptDeleted;
  final int? firstMissedSmsAtMs;
  final int? keyInvalidatedAtMs;

  /// True when there is nothing for the app to record.
  bool get isEmpty =>
      missedNotifications <= 0 &&
      decryptDeleted <= 0 &&
      firstMissedSmsAtMs == null &&
      keyInvalidatedAtMs == null;
}

/// The app's durable alert state (settings, encrypted DB).
final class PersistedAlerts {
  const PersistedAlerts({
    this.absorbedSeq,
    this.missedNotifications = 0,
    this.unreadableAtMs,
    this.catchUpFromMs,
    this.catchUpReason,
  });

  static const PersistedAlerts empty = PersistedAlerts();

  final int? absorbedSeq;
  final int missedNotifications;
  final int? unreadableAtMs;

  /// T-048 consumes these two (catch-up request).
  final int? catchUpFromMs;
  final CatchUpReason? catchUpReason;

  PersistedAlerts copyWith({
    int? absorbedSeq,
    int? missedNotifications,
    int? unreadableAtMs,
    int? catchUpFromMs,
    CatchUpReason? catchUpReason,
  }) => PersistedAlerts(
    absorbedSeq: absorbedSeq ?? this.absorbedSeq,
    missedNotifications: missedNotifications ?? this.missedNotifications,
    unreadableAtMs: unreadableAtMs ?? this.unreadableAtMs,
    catchUpFromMs: catchUpFromMs ?? this.catchUpFromMs,
    catchUpReason: catchUpReason ?? this.catchUpReason,
  );
}

sealed class AbsorbPlan {
  const AbsorbPlan();
}

/// Nothing to record, nothing to clear.
final class AbsorbNothing extends AbsorbPlan {
  const AbsorbNothing();
}

/// This `seq` was absorbed before and its clear failed: only clear again.
final class AbsorbRetryClear extends AbsorbPlan {
  const AbsorbRetryClear(this.seq);

  final int seq;
}

/// Persist [next] in one transaction, then clear [seq].
final class AbsorbStore extends AbsorbPlan {
  const AbsorbStore(this.next, this.seq);

  final PersistedAlerts next;
  final int seq;
}

/// Cap of the informational missed count (saturating add).
const int kMissedNotificationsCap = 999999999;

/// Window of the catch-up request when a key was invalidated and no first
/// missed SMS time is known. PROVISIONAL: T-048 owns the default window
/// (A-11: 6 months scan depth); one decision point.
const Duration kKeyInvalidatedCatchUpWindow = Duration(days: 183);

int _saturatingAdd(int a, int b) {
  final sum = (a < 0 ? 0 : a) + (b < 0 ? 0 : b);
  return sum > kMissedNotificationsCap ? kMissedNotificationsCap : sum;
}

AbsorbPlan planAbsorb({
  required AlertSnapshot snapshot,
  required PersistedAlerts persisted,
  required int nowMs,
}) {
  if (snapshot.isEmpty) return const AbsorbNothing();
  if (snapshot.seq == persisted.absorbedSeq) {
    return AbsorbRetryClear(snapshot.seq);
  }
  var from = persisted.catchUpFromMs;
  var reason = persisted.catchUpReason;
  void request(int candidate, CatchUpReason why) {
    if (from == null || candidate < from!) {
      from = candidate;
      reason = why;
    }
  }

  final firstMissed = snapshot.firstMissedSmsAtMs;
  if (firstMissed != null) request(firstMissed, CatchUpReason.missedSms);
  if (snapshot.keyInvalidatedAtMs != null) {
    final window = nowMs - kKeyInvalidatedCatchUpWindow.inMilliseconds;
    // The earlier of the two wins; a missed SMS never narrows the request.
    request(window < 0 ? 0 : window, CatchUpReason.keyInvalidated);
  }
  return AbsorbStore(
    PersistedAlerts(
      absorbedSeq: snapshot.seq,
      missedNotifications: _saturatingAdd(
        persisted.missedNotifications,
        snapshot.missedNotifications,
      ),
      unreadableAtMs: snapshot.decryptDeleted > 0
          ? (persisted.unreadableAtMs ?? nowMs)
          : persisted.unreadableAtMs,
      catchUpFromMs: from,
      catchUpReason: reason,
    ),
    snapshot.seq,
  );
}
