// SMS-device: data side of the debug-only "SMS diagnostics" screen (dev
// flavours only). Counts and sender names per stage, never a body, an amount
// or a timestamp. Native supplies what it saw before the database (received,
// Guard kept/dropped by reason, spooled, inbox scan); the database supplies
// what the app made of it (parsed, saved, in review).

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/app_database_providers.dart';
import '../../../ingestion/ingestion_config.dart' show kIsDevBuild;

/// One read of the counters.
final class SmsDiagSnapshot {
  const SmsDiagSnapshot({
    required this.guardMode,
    required this.userState,
    required this.pending,
    required this.senders,
  });

  /// Native Guard mode (`full`, `base_only`, `invalid`...); `?` when unknown.
  final String guardMode;
  final String userState;

  /// Spool entries waiting for the app; -1 unknown.
  final int pending;

  /// sender -> stage -> count.
  final Map<String, Map<String, int>> senders;

  /// Sum of [stage] over every sender.
  int total(String stage) =>
      senders.values.fold(0, (a, m) => a + (m[stage] ?? 0));
}

abstract interface class SmsDiagnosticsSource {
  Future<SmsDiagSnapshot> read();
  Future<void> reset();
}

/// A sender that is a phone number is not a bank id: never named.
String diagSenderLabel(String? sender) {
  final s = (sender ?? '').trim();
  if (s.isEmpty) return '(none)';
  if (RegExp(r'^\+?[0-9][0-9 ()-]{5,}$').hasMatch(s)) return '(number)';
  return s.length > 40 ? s.substring(0, 40) : s;
}

const MethodChannel _channel = MethodChannel('app.zaghlol/sms_diag');

/// Native counters (dev builds) plus database counts.
final class NativeAndDbSmsDiagnostics implements SmsDiagnosticsSource {
  NativeAndDbSmsDiagnostics(this._db, [MethodChannel? channel])
    : _ch = channel ?? _channel;

  final AppDatabase _db;
  final MethodChannel _ch;

  @override
  Future<SmsDiagSnapshot> read() async {
    final senders = <String, Map<String, int>>{};
    void add(String sender, String stage, int n) {
      final m = senders.putIfAbsent(diagSenderLabel(sender), () => {});
      m[stage] = (m[stage] ?? 0) + n;
    }

    var mode = '?';
    var user = '?';
    var pending = -1;
    try {
      final raw = await _ch.invokeMethod<Map<Object?, Object?>>('snapshot');
      if (raw != null) {
        mode = '${raw['guardMode']}';
        user = '${raw['userState']}';
        pending = (raw['pending'] as num?)?.toInt() ?? -1;
        final counts = raw['counts'];
        if (counts is Map) {
          counts.forEach((sender, stages) {
            if (stages is Map) {
              stages.forEach((stage, n) {
                if (n is num) add('$sender', '$stage', n.toInt());
              });
            }
          });
        }
      }
    } on Object {
      // No native side (tests, iOS, a non-dev build): database counts only.
    }

    final status = await _db
        .customSelect(
          "SELECT sender, parse_status, COUNT(*) AS n FROM raw_messages "
          "WHERE channel = 'sms' GROUP BY sender, parse_status",
          readsFrom: {_db.rawMessages},
        )
        .get();
    for (final r in status) {
      add(
        r.read<String?>('sender') ?? '',
        'stored:${r.read<String>('parse_status')}',
        r.read<int>('n'),
      );
    }
    final saved = await _db
        .customSelect(
          'SELECT r.sender AS sender, COUNT(*) AS n FROM transactions t '
          'JOIN raw_messages r ON r.id = t.raw_message_id '
          "WHERE r.channel = 'sms' GROUP BY r.sender",
          readsFrom: {_db.rawMessages, _db.transactions},
        )
        .get();
    for (final r in saved) {
      add(r.read<String?>('sender') ?? '', 'saved', r.read<int>('n'));
    }
    final review = await _db
        .customSelect(
          'SELECT r.sender AS sender, v.kind AS kind, COUNT(*) AS n '
          'FROM review_items v JOIN raw_messages r ON r.id = v.raw_message_id '
          "WHERE r.channel = 'sms' AND v.resolved_at IS NULL "
          'GROUP BY r.sender, v.kind',
          readsFrom: {_db.rawMessages, _db.reviewItems},
        )
        .get();
    for (final r in review) {
      add(
        r.read<String?>('sender') ?? '',
        'review:${r.read<String>('kind')}',
        r.read<int>('n'),
      );
    }
    return SmsDiagSnapshot(
      guardMode: mode,
      userState: user,
      pending: pending,
      senders: senders,
    );
  }

  @override
  Future<void> reset() async {
    try {
      await _ch.invokeMethod<void>('reset');
    } on Object {
      // Nothing native to reset.
    }
  }
}

/// Whether the screen exists at all: dev flavours only.
final smsDiagnosticsEnabledProvider = Provider<bool>(
  (ref) => kIsDevBuild,
  name: 'smsDiagnosticsEnabledProvider',
);

final smsDiagnosticsSourceProvider = FutureProvider<SmsDiagnosticsSource>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return NativeAndDbSmsDiagnostics(db);
}, name: 'smsDiagnosticsSourceProvider');

@visibleForTesting
const String kSmsDiagChannelName = 'app.zaghlol/sms_diag';
