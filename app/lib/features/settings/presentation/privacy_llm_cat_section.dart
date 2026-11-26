// T-362: S-71 group for the automatic category (FR-LCAT-42/44; Ask's
// `privacy_ask_llm_section.dart` pattern). Shown only while the
// `llm_categorise` flag is on and the provider is known (FU-425). The switch
// stores consent through the same sheet as the card; switching off clears the
// consent, which empties the send queue (T-340/T-358).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/llm/llm_feature.dart';
import '../../../core/llm/llm_gateway_client.dart';
import '../../../core/llm/llm_quota_snapshot.dart';
import '../../../core/theme/z_tokens.dart';
import '../../categorization/data/llm_cat_providers.dart';
import '../../categorization/presentation/llm_cat_consent_sheet.dart';
import '../../categorization/presentation/llm_cat_ui_providers.dart';
import 'settings_widgets.dart';

class PrivacyLlmCatSection extends ConsumerWidget {
  const PrivacyLlmCatSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(catFeatureOfferedProvider)) {
      return const SizedBox.shrink();
    }
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final terms = ref.watch(llmCatTermsProvider);
    final on = ref.watch(catConsentGrantedProvider).value ?? false;
    final quota = on ? ref.watch(catQuotaStateProvider).value : null;
    return SettingsSection(
      children: [
        SettingsSwitchRow(
          key: const ValueKey('cat-llm-switch'),
          title: t.privacyLlmCatLabel,
          subtitle: t.privacyLlmCatSentence(terms?.provider ?? ''),
          value: on,
          onChanged: (v) async {
            if (v) {
              await LlmCatConsentFlow.prompt(context, ref);
              return;
            }
            final store = await ref.read(llmConsentStoreProvider.future);
            await store.clear(LlmFeature.categorise);
            ref.invalidate(catConsentGrantedProvider);
            ref.invalidate(catQueueSizeProvider);
            if (context.mounted) {
              showSettingsMessage(context, t.privacyLlmCatTurnedOff);
            }
          },
        ),
        if (on && quota != null && !quota.paused)
          Padding(
            key: const ValueKey('cat-llm-quota'),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.lg,
              vertical: ZSpacing.xs,
            ),
            child: Text(
              _quotaText(context, ref, t, quota.snapshot),
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
          ),
        SettingsRow(
          key: const ValueKey('cat-llm-details'),
          title: t.privacyLlmCatDetails,
          onTap: () => LlmCatConsentFlow.showReadOnly(context, ref),
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
    if (s == null) return t.privacyLlmCatQuotaUnknown;
    final lang = Localizations.localeOf(context).languageCode;
    final date = ZDateFormat.date(
      s.resetsAt,
      lang,
      ref.watch(digitsModeProvider(lang)),
    );
    return t.privacyLlmCatQuota(
      s.remaining,
      date,
      catCount(context, ref, s.remaining),
    );
  }
}
