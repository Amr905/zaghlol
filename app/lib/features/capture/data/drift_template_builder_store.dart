// T-164: Drift side of S-65. Message bodies are read into memory for the
// test step only; nothing here logs or returns them in an error.

import 'package:drift/drift.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show maxCustomTestMessages;

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/capture_controls_dao.dart';
import '../application/template_builder.dart';

final class DriftTemplateBuilderStore implements TemplateBuilderStore {
  DriftTemplateBuilderStore(this._db);

  final Future<AppDatabase> Function() _db;

  static const int _reviewLimit = 20;

  @override
  Future<List<TemplateSample>> reviewSamples() async {
    final db = await _db();
    final rows = await db
        .customSelect(
          'SELECT sender, channel, body FROM raw_messages '
          "WHERE parse_status = 'review' AND sender IS NOT NULL "
          "AND channel IN ('sms', 'notification', 'shortcut_message') "
          'ORDER BY received_at DESC LIMIT ?',
          variables: [const Variable<int>(_reviewLimit)],
          readsFrom: {db.rawMessages},
        )
        .get();
    return [
      for (final r in rows)
        TemplateSample(
          sender: r.read<String>('sender'),
          channel: r.read<String>('channel'),
          body: r.read<String>('body'),
        ),
    ];
  }

  @override
  Future<List<String>> senderHistory(String sender, String channel) async {
    final db = await _db();
    final rows = await db
        .customSelect(
          'SELECT body FROM raw_messages WHERE sender = ? AND channel = ? '
          'ORDER BY received_at DESC LIMIT ?',
          variables: [
            Variable<String>(sender),
            Variable<String>(channel),
            const Variable<int>(maxCustomTestMessages),
          ],
          readsFrom: {db.rawMessages},
        )
        .get();
    return [for (final r in rows) r.read<String>('body')];
  }

  @override
  Future<void> saveTemplate({
    required String id,
    required String sender,
    required String channel,
    required Map<String, Object?> template,
    required String sampleHash,
    required int createdAt,
  }) async {
    final db = await _db();
    await CustomTemplatesDao(db).insert(
      id: id,
      sender: sender,
      channel: channel,
      template: template,
      sampleHash: sampleHash,
      createdAt: createdAt,
    );
  }
}
