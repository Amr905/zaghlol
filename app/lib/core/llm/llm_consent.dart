// T-340: the user's consent to send to the online LLM helper, per feature
// (FR-LLM-30/31, FR-LCAT-44; ask-llm §6 "Settings (encrypted)",
// llm-categorise §7 "Consent").
//
// Stored as `ask.llm_consent` / `cat.llm_consent` = `{provider, v, at}` in the
// `settings` table of the encrypted database, so it is wiped with the database
// by "Delete everything". A different active provider or consent version, an
// empty or malformed active provider, or unreadable stored text all mean
// "ask again" (fail closed). Nothing here logs.

import 'dart:convert';

import '../settings/setting_key.dart';
import '../settings/settings_repository.dart';
import 'llm_feature.dart';

/// What the user agreed to: the provider shown on the sheet, the sheet's
/// version, and when (UTC ms).
final class LlmConsentGrant {
  const LlmConsentGrant({
    required this.provider,
    required this.v,
    required this.atMs,
  });

  /// The wire form of a provider id (OpenAPI `LlmConsent.provider`).
  static final RegExp providerPattern = RegExp(r'^[a-z0-9][a-z0-9-]{1,31}$');

  final String provider;
  final int v;
  final int atMs;

  /// True when [provider] and [v] are what the backend accepts.
  static bool validTerms(String provider, int v) =>
      providerPattern.hasMatch(provider) && v >= 1 && v <= 0x7fffffff;

  /// True when this grant covers [provider] at version [v].
  bool covers(String provider, int v) =>
      validTerms(provider, v) && provider == this.provider && v == this.v;

  String toJson() => jsonEncode({'provider': provider, 'v': v, 'at': atMs});

  /// Null for anything that isn't exactly a grant this app wrote.
  static LlmConsentGrant? tryFromJson(String stored) {
    try {
      final m = jsonDecode(stored);
      if (m is! Map<String, Object?> || m.length != 3) return null;
      final p = m['provider'];
      final v = m['v'];
      final at = m['at'];
      if (p is! String || v is! int || at is! int || at < 0) return null;
      if (!validTerms(p, v)) return null;
      return LlmConsentGrant(provider: p, v: v, atMs: at);
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is LlmConsentGrant &&
      other.provider == provider &&
      other.v == v &&
      other.atMs == atMs;

  @override
  int get hashCode => Object.hash(provider, v, atMs);

  @override
  String toString() => 'LlmConsentGrant($provider, v$v)';
}

/// The consent settings keys.
abstract final class LlmConsentSettings {
  static final ask = _key(LlmFeature.ask);
  static final categorise = _key(LlmFeature.categorise);

  static SettingKey<LlmConsentGrant?> of(LlmFeature f) => switch (f) {
    LlmFeature.ask => ask,
    LlmFeature.categorise => categorise,
  };

  static SettingKey<LlmConsentGrant?> _key(LlmFeature f) => SettingKey.custom(
    '${f.settingsPrefix}.llm_consent',
    byDefault: null,
    decode: LlmConsentGrant.tryFromJson,
    encode: (v) => v?.toJson() ?? '',
  );
}

final class LlmConsentStore {
  LlmConsentStore(this._settings, {int Function()? nowMs})
    : _nowMs = nowMs ?? _utcNowMs;

  final SettingsRepository _settings;
  final int Function() _nowMs;

  static int _utcNowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// The stored grant, or null (none, or unreadable).
  Future<LlmConsentGrant?> read(LlmFeature feature) =>
      _settings.get(LlmConsentSettings.of(feature));

  /// The grant when it covers the active [provider] at version [v]; null
  /// otherwise (the caller must ask again).
  Future<LlmConsentGrant?> grantFor(
    LlmFeature feature,
    String provider,
    int v,
  ) async {
    final g = await read(feature);
    return g != null && g.covers(provider, v) ? g : null;
  }

  /// True unless a stored grant covers exactly [activeProvider] at [v].
  Future<bool> needsConsent(
    LlmFeature feature,
    String activeProvider,
    int v,
  ) async => await grantFor(feature, activeProvider, v) == null;

  /// "Allow" on the consent sheet. Throws [ArgumentError] (no value echoed)
  /// for terms the backend would refuse; nothing is stored then.
  Future<LlmConsentGrant> grant(
    LlmFeature feature,
    String provider,
    int v,
  ) async {
    if (!LlmConsentGrant.validTerms(provider, v)) {
      throw ArgumentError('invalid consent terms');
    }
    final g = LlmConsentGrant(provider: provider, v: v, atMs: _nowMs());
    await _settings.set(LlmConsentSettings.of(feature), g);
    return g;
  }

  /// The Settings switch off, or a `409 LLM_CONSENT_REQUIRED`.
  Future<void> clear(LlmFeature feature) =>
      _settings.reset(LlmConsentSettings.of(feature));
}
