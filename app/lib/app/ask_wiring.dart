// T-347: wires the online helper's two seams in the root ProviderScope.
//
// - `consentPrompterProvider` -> the consent sheet (T-345) over S-50;
// - `llmAnswerViewBuilderProvider` -> the answer views (T-347).
//
// - `askConsentTermsProvider` -> the one provider of the synced config
//   (`llmProviderTermsProvider`, FU-425); null (no id or no names) keeps the
//   sheet from being allowed and nothing is sent.

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../core/config/remote_config_providers.dart';
import '../core/l10n/locale_providers.dart';
import '../core/llm/llm_provider_terms.dart';
import '../features/ask/application/llm_ask_flow.dart'
    show askLlmConsentVersion;
import '../features/ask/presentation/consent_sheet.dart';
import '../features/gold/application/gating.dart';

import '../features/ask/data/llm_ask_providers.dart';
import '../features/ask/presentation/llm_answer_views.dart';
import '../features/ask/presentation/llm_ask_ui.dart';

/// Sheet terms from the one provider and the tier's monthly count.
AskConsentTerms? _askConsentTerms(Ref ref) {
  final p = ref.watch(llmProviderTermsProvider);
  if (p == null) return null;
  final cfg = ref.watch(remoteConfigProvider).value;
  final gold = ref.watch(entitlementStateProvider).isGold;
  final lang =
      (ref.watch(appLocaleProvider) ?? PlatformDispatcher.instance.locale)
          .languageCode;
  return AskConsentTerms(
    providerId: p.id,
    version: askLlmConsentVersion,
    providerName: p.nameFor(lang),
    quotaPerMonth: gold ? (cfg?.askQuotaGold ?? 50) : (cfg?.askQuotaFree ?? 5),
  );
}

final List<Override> askLlmWiringOverrides = [
  askConsentTermsProvider.overrideWith(_askConsentTerms),
  consentPrompterProvider.overrideWith(
    (ref) => ref.watch(sheetConsentPrompterProvider),
  ),
  llmAnswerViewBuilderProvider.overrideWithValue(buildLlmAnswerView),
];
