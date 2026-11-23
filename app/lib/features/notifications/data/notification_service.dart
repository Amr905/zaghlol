// T-094: all alerts flow through [NotificationService]: per-type toggle,
// once-only dedupe (fired_alerts), quiet hours (delay, not drop) and
// lock-screen redaction (FR-NTF-01..03). Nothing here logs; the text is the
// caller's and is never echoed into an error.

import '../domain/notification_types.dart';
import '../domain/quiet_hours.dart';

/// A snapshot of the settings the service needs.
final class NotificationPrefs {
  const NotificationPrefs({
    required this.typeEnabled,
    required this.quietHours,
    required this.hideAmounts,
  });

  final bool Function(NotificationType) typeEnabled;
  final QuietHours quietHours;

  /// `hide_amounts.notifications`. T-103 turns it on with app lock.
  final bool hideAmounts;
}

enum AlertOutcome { disabled, duplicate, shown, scheduled }

final class NotificationService {
  NotificationService({
    required this.gateway,
    required this.loadPrefs,
    required this.markFired,
    required this.unmarkFired,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final NotificationGateway gateway;
  final Future<NotificationPrefs> Function() loadPrefs;

  /// True for exactly one caller per dedupe key (FiredAlertsDao.markFired).
  final Future<bool> Function({
    required String kind,
    required String subjectId,
    required String periodKey,
    required int threshold,
    required int at,
  })
  markFired;

  /// Releases a claim made by [markFired] (FU-133): called when the gateway
  /// failed, so a later retry can still alert.
  final Future<void> Function({
    required String kind,
    required String subjectId,
    required String periodKey,
    required int threshold,
  })
  unmarkFired;
  final DateTime Function() _now;

  /// FU-133: alerts scheduled for the end of quiet hours with the full text,
  /// by platform id. Held in memory only (see [redactScheduled]).
  final Map<int, (AlertRequest, PlatformNotification)> _scheduledVisible = {};

  Future<AlertOutcome> notify(AlertRequest r) async {
    final prefs = await loadPrefs();
    if (!prefs.typeEnabled(r.type)) return AlertOutcome.disabled;

    final now = _now();
    final won = await markFired(
      kind: r.type.kind,
      subjectId: r.subjectId,
      periodKey: r.periodKey,
      threshold: r.threshold,
      at: now.toUtc().millisecondsSinceEpoch,
    );
    if (!won) return AlertOutcome.duplicate;

    final local = now.toLocal();
    final when = prefs.quietHours.nextAllowed(local);
    final delayed = when != local;
    final n = PlatformNotification(
      id: _id(r),
      title: prefs.hideAmounts ? r.redactedTitle : r.title,
      body: prefs.hideAmounts ? r.redactedBody : r.body,
      payload: r.payload,
      actionTitle: r.actionTitle,
      actionRoute: r.actionRoute,
      at: delayed ? when.toUtc() : null,
      type: r.type,
    );
    // FU-133: the claim stays only if the platform accepted the alert.
    try {
      if (delayed) {
        await gateway.schedule(n);
        if (!prefs.hideAmounts) _scheduledVisible[n.id] = (r, n);
        return AlertOutcome.scheduled;
      }
      await gateway.show(n);
      return AlertOutcome.shown;
    } catch (_) {
      await unmarkFired(
        kind: r.type.kind,
        subjectId: r.subjectId,
        periodKey: r.periodKey,
        threshold: r.threshold,
      );
      rethrow;
    }
  }

  /// T-228: the platform id of the alert with this dedupe key.
  static int idFor({
    required NotificationType type,
    required String subjectId,
    required String periodKey,
    int threshold = 0,
  }) => _hash('${type.kind}|$subjectId|$periodKey|$threshold');

  /// T-228: drops what is waiting for these dedupe keys (shown or scheduled),
  /// e.g. a bill's reminders once it is paid. The "fired" claims stay, so a
  /// cancelled reminder is never sent again. Other alerts are untouched.
  /// Best effort: a platform failure is swallowed (the reminder is stale, not
  /// harmful, and the next paid mark or the user's tap clears it).
  Future<void> cancelAlerts({
    required NotificationType type,
    required String subjectId,
    required String periodKey,
    required Iterable<int> thresholds,
  }) async {
    for (final t in thresholds) {
      final id = idFor(
        type: type,
        subjectId: subjectId,
        periodKey: periodKey,
        threshold: t,
      );
      _scheduledVisible.remove(id);
      try {
        await gateway.cancel(id);
      } on Object {
        // See above.
      }
    }
  }

  /// T-228: schedules [r] for [at] (UTC) without a dedupe claim: the id is
  /// stable per key, so scheduling again replaces the earlier one. Honours the
  /// per-type toggle and quiet hours (a time inside quiet hours moves to its
  /// end). Disabled type: cancels any earlier one. Text is chosen like
  /// [notify]. Returns false when nothing was scheduled.
  Future<bool> scheduleAt(AlertRequest r, DateTime at) async {
    final prefs = await loadPrefs();
    final id = idFor(
      type: r.type,
      subjectId: r.subjectId,
      periodKey: r.periodKey,
      threshold: r.threshold,
    );
    if (!prefs.typeEnabled(r.type)) {
      await gateway.cancel(id);
      return false;
    }
    final local = at.toLocal();
    final when = prefs.quietHours.nextAllowed(local);
    if (!when.isAfter(_now())) return false;
    await gateway.schedule(
      PlatformNotification(
        id: id,
        title: prefs.hideAmounts ? r.redactedTitle : r.title,
        body: prefs.hideAmounts ? r.redactedBody : r.body,
        payload: r.payload,
        actionTitle: r.actionTitle,
        actionRoute: r.actionRoute,
        at: when.toUtc(),
        type: r.type,
      ),
    );
    return true;
  }

  /// FU-133: the redaction choice is made when an alert is scheduled. When
  /// the user hides amounts later (or turns app lock on) before it fires,
  /// this re-schedules every alert still waiting with the full text, under
  /// the same id, with the redacted text (the platform replaces it). Does
  /// nothing while amounts are shown. Returns how many were replaced.
  ///
  /// Residual: the list lives in memory, so an alert scheduled before the
  /// app process restarted keeps its text.
  Future<int> redactScheduled() async {
    if (_scheduledVisible.isEmpty) return 0;
    final prefs = await loadPrefs();
    if (!prefs.hideAmounts) return 0;
    final now = _now().toUtc();
    var replaced = 0;
    for (final key in [..._scheduledVisible.keys]) {
      final (r, n) = _scheduledVisible[key]!;
      _scheduledVisible.remove(key);
      final at = n.at;
      if (at == null || !at.isAfter(now)) continue;
      await gateway.schedule(
        PlatformNotification(
          id: n.id,
          title: r.redactedTitle,
          body: r.redactedBody,
          payload: n.payload,
          at: at,
          type: n.type,
          actionTitle: n.actionTitle,
          actionRoute: n.actionRoute,
        ),
      );
      replaced++;
    }
    return replaced;
  }

  /// A stable positive 31-bit id (FNV-1a) of the dedupe key.
  static int _id(AlertRequest r) => idFor(
    type: r.type,
    subjectId: r.subjectId,
    periodKey: r.periodKey,
    threshold: r.threshold,
  );

  static int _hash(String key) {
    var h = 0x811c9dc5;
    for (final u in key.codeUnits) {
      h = ((h ^ u) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }
}
