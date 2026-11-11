// T-021: renders the diagnostic log as shareable text (user-initiated; the
// Settings -> About screen shares the string). The text is regenerated from
// codes: every stored key and value is re-validated against the allow-list,
// and anything that fails is dropped, so even a tampered row can't carry text.

import 'dart:convert';

import '../db/daos/misc_daos.dart' show DiagLogDao;
import 'diag_code.dart';
import 'diag_field.dart';
import 'diag_logger.dart';

class DiagExporter {
  DiagExporter(this._dao);

  final DiagLogDao _dao;

  /// One line per event, oldest first: `ISO-UTC level CODE key=value ...`.
  /// Rows older than 7 days (relative to [now]) are left out.
  Future<String> exportText({required DateTime now}) async {
    final cutoff = now
        .toUtc()
        .subtract(DiagLogger.maxAge)
        .millisecondsSinceEpoch;
    final rows = await _dao.recent(limit: DiagLogger.maxRows);
    final out = StringBuffer('zaghlol diagnostics\n');
    for (final row in rows.reversed) {
      if (row.at < cutoff) continue;
      final code = DiagCode.fromRegistry(row.code);
      if (code == null) continue;
      final line = StringBuffer(
        '${DateTime.fromMillisecondsSinceEpoch(row.at, isUtc: true).toIso8601String()} '
        '${row.level} ${code.value}',
      );
      for (final f in _fieldsOf(row.fields)) {
        line.write(' ${f.key.wire}=${f.value}');
      }
      out.writeln(line);
    }
    return out.toString();
  }

  static List<DiagField> _fieldsOf(String? json) {
    if (json == null) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const [];
    }
    if (decoded is! Map<String, Object?>) return const [];
    return [
      for (final e in decoded.entries) ?DiagField.tryFromStored(e.key, e.value),
    ];
  }
}
