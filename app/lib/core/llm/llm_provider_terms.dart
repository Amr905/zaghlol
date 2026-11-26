// T-367 (FU-425/FU-431): the ONE source of the provider the LLM consents are
// bound to. It reads only the signed sync `config` block (`llm.provider` plus
// the display names, ask-llm.md 4.6) through [remoteConfigProvider], so the id
// the app stores and the names the user reads can't come from two places.
// The id of a `409 LLM_CONSENT_REQUIRED` is never used. Null (no id, a bad
// id, a missing name, stale or no config) means nothing can be sent and no
// LLM consent UI is shown (fail closed). Nothing here logs.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/remote_config_providers.dart';
import 'llm_consent.dart';

/// The effective provider: wire id and both display names.
final class LlmProviderTerms {
  const LlmProviderTerms({
    required this.id,
    required this.nameAr,
    required this.nameEn,
  });

  final String id;
  final String nameAr;
  final String nameEn;

  /// The name for the UI language (`ar` or anything else = English).
  String nameFor(String languageCode) => languageCode == 'ar' ? nameAr : nameEn;

  @override
  bool operator ==(Object other) =>
      other is LlmProviderTerms &&
      other.id == id &&
      other.nameAr == nameAr &&
      other.nameEn == nameEn;

  @override
  int get hashCode => Object.hash(id, nameAr, nameEn);

  @override
  String toString() => 'LlmProviderTerms($id)';
}

/// Null unless the id is a valid wire id and both names are non-empty.
final llmProviderTermsProvider = Provider<LlmProviderTerms?>((ref) {
  final c = ref.watch(remoteConfigProvider).value;
  if (c == null) return null;
  final id = c.llmProvider;
  final ar = c.providerName.ar.trim();
  final en = c.providerName.en.trim();
  if (!LlmConsentGrant.providerPattern.hasMatch(id) ||
      ar.isEmpty ||
      en.isEmpty) {
    return null;
  }
  return LlmProviderTerms(id: id, nameAr: ar, nameEn: en);
}, name: 'llmProviderTermsProvider');
