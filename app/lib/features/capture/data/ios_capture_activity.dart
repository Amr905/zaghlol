// T-066: when the last iOS automation capture (Shortcuts message, Apple Pay)
// arrived. Share, paste, OCR, PDF and CSV are manual, so they do not count:
// the checker asks whether the automations work. Reads one aggregate; no
// message body is selected.

import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';

/// Raw-message channels fed by the iOS automations.
const List<String> kIosAutomationChannels = ['shortcut_message', 'apple_pay'];

abstract interface class IosCaptureActivity {
  /// Newest `received_at` (UTC epoch ms) of an automation capture, or null.
  Stream<int?> watchLastCaptureAtMs();
}

final class DriftIosCaptureActivity implements IosCaptureActivity {
  DriftIosCaptureActivity(this._db);

  final AppDatabase _db;

  @override
  Stream<int?> watchLastCaptureAtMs() {
    final newest = _db.rawMessages.receivedAt.max();
    final query = _db.selectOnly(_db.rawMessages)
      ..addColumns([newest])
      ..where(_db.rawMessages.channel.isIn(kIosAutomationChannels));
    return query.map((row) => row.read(newest)).watchSingle();
  }
}
