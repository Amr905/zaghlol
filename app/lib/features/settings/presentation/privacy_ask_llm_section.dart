// T-345: S-71 group for the online helper (FR-LLM-31; ask-llm-ux §3). Shown
// only while the `ask_llm` flag is on.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/flags/feature_flags.dart';
import '../../../core/flags/flags_providers.dart';
import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/llm/llm_feature.dart';
import '../../../core/llm/llm_gateway_client.dart';
import '../../../core/llm/llm_quota_snapshot.dart';
import '../../../core/theme/z_tokens.dart';
import '../../ask/presentation/consent_sheet.dart';
import 'settings_widgets.dart';

/// The stored quota hint and the paused mark.
typedef AskQuotaState = ({LlmQuotaSnapshot? snapshot, bool paused});

final askQuotaStateProvider = FutureProvider.autoDispose<AskQuotaState>((
  ref,
) async {
  final store = await ref.watch(llmQuotaStoreProvider.future);
  final paused = await store.isPaused(LlmFeature.ask);
  final snap = await store.current(LlmFeature.ask, DateTime.now());
  return (snapshot: snap, paused: paused);
}, name: 'askQuotaStateProvider');

class PrivacyAskLlmSection extends ConsumerWidget {
  const PrivacyAskLlmSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(featureFlagProvider(FeatureFlag.askLlm))) {
      return const SizedBox.shrink();
    }
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final on = ref.watch(askConsentGrantedProvider).value ?? false;
    final terms = ref.watch(askConsentTermsProvider);
    final quota = on ? ref.watch(askQuotaStateProvider).value : null;
    return SettingsSection(
      children: [
        SettingsSwitchRow(
          key: const ValueKey('ask-llm-switch'),
          title: t.privacyAskLlmLabel,
          subtitle: t.privacyAskLlmSentence,
          value: on,
          onChanged: terms == null
              ? null
              : (v) async {
                  if (v) {
                    await AskConsentFlow.prompt(context, ref);
                    return;
                  }
                  final store = await ref.read(llmConsentStoreProvider.future);
                  await store.clear(LlmFeature.ask);
                  ref.invalidate(askConsentGrantedProvider);
                  if (context.mounted) {
                    showSettingsMessage(context, t.privacyAskLlmTurnedOff);
                  }
                },
        ),
        if (on && quota != null && !quota.paused)
          Padding(
            key: const ValueKey('ask-llm-quota'),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.lg,
              vertical: ZSpacing.xs,
            ),
            child: Text(
              _quotaText(context, ref, t, quota.snapshot),
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
          ),
        if (terms != null)
          SettingsRow(
            key: const ValueKey('ask-llm-details'),
            title: t.privacyAskLlmDetails,
            onTap: () => AskConsentFlow.showReadOnly(context, ref),
          ),
      ],
    );
  }

  String _quotaText(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations t,
    LlmQuotaSnapshot? s,
  ) {
    if (s == null) return t.privacyAskLlmQuotaUnknown;
    final lang = Localizations.localeOf(context).languageCode;
    final date = ZDateFormat.date(
      s.resetsAt,
      lang,
      ref.watch(digitsModeProvider(lang)),
    );
    return t.privacyAskLlmQuota(s.remaining, date, s.remaining);
  }
}
