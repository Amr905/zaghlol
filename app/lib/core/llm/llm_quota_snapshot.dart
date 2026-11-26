// T-340: the last quota the backend reported, per feature, and the "paused
// until the next sync" mark (FR-LLM-12, FR-LCAT-40; ask-llm §6 "Settings
// (encrypted)").
//
// `ask.llm_quota` / `cat.llm_quota` = `{limit, remaining, resetsAt}` and
// `ask.llm_paused_until_sync` / `cat.llm_paused_until_sync` live in the
// `settings` table of the encrypted database (wiped with it by "Delete
// everything"). The snapshot is only a local hint: the backend counts. It is
// unknown before the first contact, after `resetsAt`, or when the stored text
// doesn't parse. At `remaining = 0` before `resetsAt` nothing is sent.
// Nothing here logs.

import 'dart:convert';

import '../backend/generated/api_models.g.dart' show LlmQuota;
import '../settings/setting_key.dart';
import '../settings/settings_repository.dart';
import 'llm_feature.dart';

final class LlmQuotaSnapshot {
  const LlmQuotaSnapshot({
    required this.limit,
    required this.remaining,
    required this.resetsAt,
  });

  final int limit;
  final int remaining;

  /// UTC.
  final DateTime resetsAt;

  /// The wire quota as a snapshot; null when `resetsAt` isn't a UTC instant
  /// or the counts are out of range.
  static LlmQuotaSnapshot? fromWire(LlmQuota q) {
    final at = _utc(q.resetsAt);
    if (at == null || !_count(q.limit) || !_count(q.remaining)) return null;
    return LlmQuotaSnapshot(
      limit: q.limit,
      remaining: q.remaining,
      resetsAt: at,
    );
  }

  static bool _count(int n) => n >= 0 && n <= 1000000;

  static DateTime? _utc(String s) {
    if (!s.endsWith('Z')) return null;
    final t = DateTime.tryParse(s);
    return t == null || !t.isUtc ? null : t;
  }

  /// True while [now] is before [resetsAt].
  bool validAt(DateTime now) => now.toUtc().isBefore(resetsAt);

  String toJson() => jsonEncode({
    'limit': limit,
    'remaining': remaining,
    'resetsAt': resetsAt.toIso8601String(),
  });

  static LlmQuotaSnapshot? tryFromJson(String stored) {
    try {
      final m = jsonDecode(stored);
      if (m is! Map<String, Object?> || m.length != 3) return null;
      final l = m['limit'];
      final r = m['remaining'];
      final at = m['resetsAt'];
      if (l is! int || r is! int || at is! String) return null;
      if (!_count(l) || !_count(r)) return null;
      final t = _utc(at);
      if (t == null) return null;
      return LlmQuotaSnapshot(limit: l, remaining: r, resetsAt: t);
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is LlmQuotaSnapshot &&
      other.limit == limit &&
      other.remaining == remaining &&
      other.resetsAt == resetsAt;

  @override
  int get hashCode => Object.hash(limit, remaining, resetsAt);

  @override
  String toString() => 'LlmQuotaSnapshot($remaining/$limit)';
}

/// The quota and pause settings keys.
abstract final class LlmQuotaSettings {
  static final askQuota = _quota(LlmFeature.ask);
  static final catQuota = _quota(LlmFeature.categorise);
  static final askPaused = _paused(LlmFeature.ask);
  static final catPaused = _paused(LlmFeature.categorise);

  static SettingKey<LlmQuotaSnapshot?> quota(LlmFeature f) => switch (f) {
    LlmFeature.ask => askQuota,
    LlmFeature.categorise => catQuota,
  };

  static SettingKey<bool> paused(LlmFeature f) => switch (f) {
    LlmFeature.ask => askPaused,
    LlmFeature.categorise => catPaused,
  };

  static SettingKey<LlmQuotaSnapshot?> _quota(LlmFeature f) =>
      SettingKey.custom(
        '${f.settingsPrefix}.llm_quota',
        byDefault: null,
        decode: LlmQuotaSnapshot.tryFromJson,
        encode: (v) => v?.toJson() ?? '',
      );

  static SettingKey<bool> _paused(LlmFeature f) => SettingKey.boolean(
    '${f.settingsPrefix}.llm_paused_until_sync',
    byDefault: false,
  );
}

final class LlmQuotaStore {
  LlmQuotaStore(this._settings);

  final SettingsRepository _settings;

  /// The last snapshot while still valid at [now]; null means unknown ("—").
  Future<LlmQuotaSnapshot?> current(LlmFeature feature, DateTime now) async {
    final s = await _settings.get(LlmQuotaSettings.quota(feature));
    return s != null && s.validAt(now) ? s : null;
  }

  /// True when the snapshot is known and nothing is left before `resetsAt`.
  Future<bool> exhausted(LlmFeature feature, DateTime now) async =>
      (await current(feature, now))?.remaining == 0;

  /// Stores [q] from a reply. A quota that doesn't parse leaves the old one.
  Future<void> record(LlmFeature feature, LlmQuota q) async {
    final s = LlmQuotaSnapshot.fromWire(q);
    if (s == null) return;
    await _settings.set(LlmQuotaSettings.quota(feature), s);
  }

  Future<bool> isPaused(LlmFeature feature) =>
      _settings.get(LlmQuotaSettings.paused(feature));

  /// `503 LLM_SERVICE_PAUSED`: nothing is sent until the next sync.
  Future<void> pause(LlmFeature feature) =>
      _settings.set(LlmQuotaSettings.paused(feature), true);

  /// After a successful sync (the backend's flags are fresh again).
  Future<void> resumeAll() async {
    for (final f in LlmFeature.values) {
      await _settings.reset(LlmQuotaSettings.paused(f));
    }
  }

  /// Drops the snapshot and the pause mark of [feature].
  Future<void> clear(LlmFeature feature) async {
    await _settings.reset(LlmQuotaSettings.quota(feature));
    await _settings.reset(LlmQuotaSettings.paused(feature));
  }
}
