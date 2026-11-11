// T-019: capture controls (database-schema §2.7): ignore rules (FR-CAP-*,
// EC-59: institution + last-4, never last-4 alone), the generic-parser
// senders the user keeps (FR-PAR-13, A-66) and Gold custom templates
// (FR-PAR-07). Senders and institution codes come from other apps or
// messages, so every read that binds them runs through guardRead and every
// write through guardWrite: a failure is a code, never the text. Nothing
// here logs.

import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

/// `ignore_rules.channel` values (FR-CAP-01).
abstract final class IgnoreChannel {
  static const String sms = 'sms';
  static const String notification = 'notification';
  static const String applePay = 'apple_pay';
}

/// `capture_senders.channel` / `custom_templates.channel` values.
abstract final class SenderChannel {
  static const String sms = 'sms';
  static const String notification = 'notification';
  static const String shortcutMessage = 'shortcut_message';
}

/// Result of a `capture_senders` write (T-047).
sealed class SenderWrite {
  const SenderWrite();
}

/// The row was written; [confirmedCount] is set by [recordConfirmation].
final class SenderWritten extends SenderWrite {
  const SenderWritten(this.confirmedCount);

  final int? confirmedCount;
}

/// The sender exists on another channel; nothing changed. The Guard key is
/// `(channel, sender)` but the table's key is `sender` (T-047 decision: no
/// migration).
final class ChannelConflict extends SenderWrite {
  const ChannelConflict();
}

class CaptureControlsDao {
  CaptureControlsDao(this._db);

  final AppDatabase _db;

  /// Adds an ignore rule; a NULL [last4] ignores the whole institution on
  /// [channel] (FR-CAP-05). Returns false when an equal rule already exists
  /// (nothing changes then), so a double tap or two engines add one rule.
  Future<bool> addIgnoreRule({
    required String id,
    required String institutionCode,
    String? last4,
    required String channel,
    required int createdAt,
  }) => guardWrite(() async {
    final changed = await _db.customUpdate(
      'INSERT INTO ignore_rules (id, institution_code, last4, channel, '
      'created_at) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT DO NOTHING',
      variables: [
        Variable.withString(id),
        Variable.withString(institutionCode),
        Variable<String>(last4),
        Variable.withString(channel),
        Variable.withInt(createdAt),
      ],
      updates: {_db.ignoreRules},
      updateKind: UpdateKind.insert,
    );
    return changed == 1;
  });

  Future<int> removeIgnoreRule(String id) => guardWrite(
    () => (_db.delete(_db.ignoreRules)..where((r) => r.id.equals(id))).go(),
  );

  /// Every rule, by institution, card, channel (FR-CAP-06).
  Future<List<IgnoreRuleRow>> ignoreRules() =>
      (_db.select(_db.ignoreRules)..orderBy([
            (r) => OrderingTerm.asc(r.institutionCode),
            (r) => OrderingTerm(expression: r.last4, nulls: NullsOrder.first),
            (r) => OrderingTerm.asc(r.channel),
          ]))
          .get();

  /// True when a message from [institutionCode] on [channel] for card
  /// [last4] is ignored: a rule for that exact card, or an
  /// institution-level rule. A message without a last-4 matches only
  /// institution-level rules (EC-59).
  Future<bool> isIgnored({
    required String institutionCode,
    String? last4,
    required String channel,
  }) => guardRead(() async {
    final row = await _db
        .customSelect(
          'SELECT 1 FROM ignore_rules WHERE institution_code = ?1 '
          'AND channel = ?2 AND (last4 IS NULL OR last4 = ?3) LIMIT 1',
          variables: [
            Variable.withString(institutionCode),
            Variable.withString(channel),
            Variable<String>(last4),
          ],
          readsFrom: {_db.ignoreRules},
        )
        .getSingleOrNull();
    return row != null;
  });

  /// Counts one user confirmation of a generic parse from [sender] (A-66).
  /// One statement: two engines confirming at once count twice. A row of the
  /// same sender on the other channel is left as it is and the result is
  /// [ChannelConflict] (T-047, FU-096 m-2): the other channel is never
  /// silently counted.
  Future<SenderWrite> recordConfirmation({
    required String sender,
    required String channel,
    required int at,
  }) => guardWrite(() async {
    final rows = await _db.customWriteReturning(
      'INSERT INTO capture_senders (sender, channel, confirmed_count, '
      'created_at) VALUES (?1, ?2, 1, ?3) ON CONFLICT (sender) DO UPDATE '
      'SET confirmed_count = confirmed_count + 1 '
      'WHERE channel = excluded.channel RETURNING confirmed_count',
      variables: [
        Variable.withString(sender),
        Variable.withString(channel),
        Variable.withInt(at),
      ],
      updates: {_db.captureSenders},
      updateKind: UpdateKind.update,
    );
    if (rows.isEmpty) return const ChannelConflict();
    return SenderWritten(rows.single.read<int>('confirmed_count'));
  });

  /// Sets "always capture this sender" (A-66). Creates the row with no
  /// confirmations when it is new. A row of the same sender on the other
  /// channel is left as it is: [ChannelConflict] (T-047, FU-096 m-2).
  /// Refused writes throw.
  Future<SenderWrite> setAlwaysCapture({
    required String sender,
    required String channel,
    required bool always,
    required int at,
  }) => guardWrite(() async {
    final changed = await _db.customUpdate(
      'INSERT INTO capture_senders (sender, channel, always_capture, '
      'created_at) VALUES (?1, ?2, ?3, ?4) ON CONFLICT (sender) DO UPDATE '
      'SET always_capture = excluded.always_capture '
      'WHERE channel = excluded.channel',
      variables: [
        Variable.withString(sender),
        Variable.withString(channel),
        Variable.withInt(always ? 1 : 0),
        Variable.withInt(at),
      ],
      updates: {_db.captureSenders},
      updateKind: UpdateKind.update,
    );
    return changed == 0 ? const ChannelConflict() : const SenderWritten(null);
  });

  Future<CaptureSenderRow?> sender(String sender) => guardRead(
    () => (_db.select(
      _db.captureSenders,
    )..where((s) => s.sender.equals(sender))).getSingleOrNull(),
  );

  /// How many senders are stored for [channel] with "always capture" on.
  Future<int> alwaysCaptureCount(String channel) => guardRead(() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM capture_senders '
          'WHERE channel = ?1 AND always_capture = 1',
          variables: [Variable.withString(channel)],
          readsFrom: {_db.captureSenders},
        )
        .getSingle();
    return row.read<int>('n');
  });

  Future<int> deleteSender(String sender) => guardWrite(
    () => (_db.delete(
      _db.captureSenders,
    )..where((s) => s.sender.equals(sender))).go(),
  );
}

class CustomTemplatesDao {
  CustomTemplatesDao(this._db);

  final AppDatabase _db;

  /// Stores a template; [template] is encoded as a JSON object (≤ 64 KiB).
  /// [sampleHash]: SHA-256 hex of the sample, never the sample itself.
  Future<void> insert({
    required String id,
    required String sender,
    required String channel,
    required Map<String, Object?> template,
    required String sampleHash,
    required int createdAt,
  }) {
    final encoded = jsonEncode(template);
    return guardWrite(
      () => _db
          .into(_db.customTemplates)
          .insert(
            CustomTemplatesCompanion.insert(
              id: id,
              sender: sender,
              channel: channel,
              templateJson: encoded,
              sampleHash: sampleHash,
              createdAt: createdAt,
            ),
          ),
    );
  }

  Future<CustomTemplateRow?> byId(String id) => (_db.select(
    _db.customTemplates,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// The templates for [sender] on [channel], oldest first.
  Future<List<CustomTemplateRow>> forSender(String sender, String channel) =>
      guardRead(
        () =>
            (_db.select(_db.customTemplates)
                  ..where(
                    (t) => t.sender.equals(sender) & t.channel.equals(channel),
                  )
                  ..orderBy([
                    (t) => OrderingTerm.asc(t.createdAt),
                    (t) => OrderingTerm.asc(t.id),
                  ]))
                .get(),
      );

  Future<int> deleteById(String id) => guardWrite(
    () => (_db.delete(_db.customTemplates)..where((t) => t.id.equals(id))).go(),
  );
}
