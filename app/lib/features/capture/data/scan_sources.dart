// T-048: the database and registry side of the scan: candidate senders and
// the catch-up watermark. Reads go through guardRead (a failure is a code,
// never the text). Nothing here logs.

import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show Registry, SenderMatchKind;

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/write_errors.dart';
import '../application/scan.dart';
import '../domain/scan_plan.dart';

/// Registry exact senders (regex-only senders are not scannable: SQL cannot
/// run the regex; T-036 exports the concrete ids, Lead decision 6) plus the
/// user's SMS senders (always-capture rows and custom-template senders),
/// classified by [classifyUserSender].
final class DriftScanSenderSource implements ScanSenderSource {
  DriftScanSenderSource(this._db, this._registry);

  final AppDatabase _db;
  final Registry Function() _registry;

  @override
  Future<List<ScanSender>> read() async {
    final out = <ScanSender>[];
    for (final i in _registry().institutions) {
      for (final s in i.senders) {
        if (s.kind == SenderMatchKind.exact) {
          out.add(
            ScanSender(
              s.value,
              ScanSenderKind.registry,
              institutionCode: i.code,
            ),
          );
        }
      }
    }
    final user = await guardRead(() async {
      final rows = await _db
          .customSelect(
            "SELECT sender FROM capture_senders WHERE channel = 'sms' "
            'AND always_capture = 1 '
            'UNION '
            "SELECT sender FROM custom_templates WHERE channel = 'sms'",
            readsFrom: {_db.captureSenders, _db.customTemplates},
          )
          .get();
      return [for (final r in rows) r.read<String>('sender')];
    });
    for (final s in user) {
      out.add(ScanSender(s, classifyUserSender(s)));
    }
    return out;
  }
}

/// The catch-up watermark: the largest `received_at` stored from channel
/// `sms` (T-008 design: no separate state).
abstract interface class WatermarkSource {
  Future<int?> maxSmsReceivedAtMs();
}

final class DriftWatermarkSource implements WatermarkSource {
  DriftWatermarkSource(this._db);

  final AppDatabase _db;

  @override
  Future<int?> maxSmsReceivedAtMs() => guardRead(() async {
    final row = await _db
        .customSelect(
          "SELECT MAX(received_at) AS m FROM raw_messages WHERE channel = 'sms'",
          readsFrom: {_db.rawMessages},
        )
        .getSingle();
    return row.read<int?>('m');
  });
}
