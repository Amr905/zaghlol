// T-021: writes diagnostic events into the `diag_log` ring buffer (7 days or
// 2000 rows). Diagnostics must never crash the app, so [record] never throws.

import '../db/daos/misc_daos.dart' show DiagLevel, DiagLogDao;
import 'diag_event.dart';

/// Where events go. The production adapter is [DiagLogDaoStore].
abstract interface class DiagStore {
  Future<void> append({
    required int at,
    required DiagLevel level,
    required String code,
    required Map<String, Object?> fields,
  });

  Future<void> prune({required int olderThan, required int keepAtMost});
}

final class DiagLogDaoStore implements DiagStore {
  DiagLogDaoStore(this._dao);

  final DiagLogDao _dao;

  @override
  Future<void> append({
    required int at,
    required DiagLevel level,
    required String code,
    required Map<String, Object?> fields,
  }) => _dao.append(
    at: at,
    level: level,
    code: code,
    fields: fields.isEmpty ? null : fields,
  );

  @override
  Future<void> prune({required int olderThan, required int keepAtMost}) =>
      _dao.prune(olderThan: olderThan, keepAtMost: keepAtMost).then((_) {});
}

class DiagLogger {
  DiagLogger(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const int maxRows = 2000;
  static const Duration maxAge = Duration(days: 7);

  final DiagStore _store;
  final DateTime Function() _now;

  /// Appends [event] and trims the buffer. Returns `false` when the event
  /// could not be stored (the failure is deliberately not surfaced: a broken
  /// diagnostic log must not break the app, and its error text is not read).
  Future<bool> record(DiagEvent event) async {
    try {
      final at = _now().toUtc();
      await _store.append(
        at: at.millisecondsSinceEpoch,
        level: event.level,
        code: event.code.value,
        fields: event.toFieldsJson(),
      );
      await _store.prune(
        olderThan: at.subtract(maxAge).millisecondsSinceEpoch,
        keepAtMost: maxRows,
      );
      return true;
    } on Object {
      return false;
    }
  }
}
