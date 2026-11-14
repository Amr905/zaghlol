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
      at: delayed ? when.toUtc() : null,
      type: r.type,
    );
    // FU-133: the claim stays only if the platform accepted the alert.
    try {
      if (delayed) {
        await gateway.schedule(n);
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

  /// A stable positive 31-bit id (FNV-1a) of the dedupe key.
  static int _id(AlertRequest r) {
    var h = 0x811c9dc5;
    for (final u
        in '${r.type.kind}|${r.subjectId}|${r.periodKey}|${r.threshold}'
            .codeUnits) {
      h = ((h ^ u) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }
}
