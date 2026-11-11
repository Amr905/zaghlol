// T-047: the app's durable alert state in the encrypted settings table
// (keys `capture.alert.*` and `capture.catchup.*`, design note §2). One
// transaction per absorb. Values are integers and one enum name; nothing
// else is stored. `absorbed_seq` is kept as text because native's random
// `seq` can be any 64-bit value.

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/settings_dao.dart';
import '../domain/alert_absorb.dart';

abstract interface class AlertStore {
  Future<PersistedAlerts> read();

  /// Persists [next] in one transaction.
  Future<void> write(PersistedAlerts next);

  /// Dismissing the missed-notification notice zeroes the count only.
  Future<void> dismissMissedNotifications();
}

abstract final class CaptureAlertKeys {
  static const String absorbedSeq = 'capture.alert.absorbed_seq';
  static const String missedNotifications =
      'capture.alert.missed_notifications';
  static const String unreadableAt = 'capture.alert.unreadable_at';
  static const String catchUpFromMs = 'capture.catchup.from_ms';
  static const String catchUpReason = 'capture.catchup.reason';
}

final class DriftAlertStore implements AlertStore {
  DriftAlertStore(this._db, {int Function()? nowMs})
    : _dao = SettingsDao(_db),
      _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final AppDatabase _db;
  final SettingsDao _dao;
  final int Function() _nowMs;

  @override
  Future<PersistedAlerts> read() async {
    final all = await _dao.all();
    int? int_(String k) {
      final v = all[k];
      return v == null ? null : int.tryParse(v);
    }

    final reasonName = all[CaptureAlertKeys.catchUpReason];
    CatchUpReason? reason;
    for (final r in CatchUpReason.values) {
      if (r.name == reasonName) reason = r;
    }
    final missed = int_(CaptureAlertKeys.missedNotifications);
    return PersistedAlerts(
      absorbedSeq: int_(CaptureAlertKeys.absorbedSeq),
      missedNotifications: missed == null || missed < 0 ? 0 : missed,
      unreadableAtMs: int_(CaptureAlertKeys.unreadableAt),
      catchUpFromMs: int_(CaptureAlertKeys.catchUpFromMs),
      catchUpReason: reason,
    );
  }

  @override
  Future<void> write(PersistedAlerts next) => _db.transaction(() async {
    final at = _nowMs();
    Future<void> put(String key, Object? value) => value == null
        ? _dao.delete(key).then((_) {})
        : _dao.write(key, '$value', at: at);
    await put(CaptureAlertKeys.absorbedSeq, next.absorbedSeq);
    await put(CaptureAlertKeys.missedNotifications, next.missedNotifications);
    await put(CaptureAlertKeys.unreadableAt, next.unreadableAtMs);
    await put(CaptureAlertKeys.catchUpFromMs, next.catchUpFromMs);
    await put(CaptureAlertKeys.catchUpReason, next.catchUpReason?.name);
  });

  @override
  Future<void> dismissMissedNotifications() =>
      _dao.write(CaptureAlertKeys.missedNotifications, '0', at: _nowMs());
}
