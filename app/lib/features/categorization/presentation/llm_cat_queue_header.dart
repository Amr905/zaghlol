// T-362: the header of the "needs a category" list (FR-LCAT-42/43). While
// the feature is on it shows the monthly counter (from the stored
// `cat.llm_quota`; unknown before the first contact, hidden while paused);
// while it is off, a passive row that opens the consent sheet. Hidden when
// the `llm_categorise` flag is off or the provider is unknown (FU-425).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/llm/llm_quota_snapshot.dart';
import '../../../core/theme/z_tokens.dart';
import 'llm_cat_consent_sheet.dart';
import 'llm_cat_ui_providers.dart';

class LlmCatQueueHeader extends ConsumerWidget {
  const LlmCatQueueHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(catFeatureOfferedProvider)) return const SizedBox.shrink();
    final on = ref.watch(catConsentGrantedProvider).value;
    if (on == null) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    if (!on) {
      return Semantics(
        button: true,
        label: t.categorizationAiQueuePassiveRow,
        onTap: () => LlmCatConsentFlow.prompt(context, ref),
        excludeSemantics: true,
        child: InkWell(
          key: const ValueKey('cat-queue-passive'),
          onTap: () => LlmCatConsentFlow.prompt(context, ref),
          borderRadius: BorderRadius.circular(ZRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: ZSpacing.md,
                vertical: ZSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 20, color: c.primary),
                  const SizedBox(width: ZSpacing.sm),
                  Expanded(
                    child: Text(
                      t.categorizationAiQueuePassiveRow,
                      style: ZType.label.copyWith(color: c.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final q = ref.watch(catQuotaStateProvider).value;
    if (q == null || q.paused) return const SizedBox.shrink();
    final s = q.snapshot;
    final text = s == null
        ? t.categorizationAiQueueCounterUnknown
        : t.categorizationAiQueueCounter(
            s.remaining,
            catCount(context, ref, s.limit),
            catCount(context, ref, s.remaining),
          );
    final label = s == null
        ? t.privacyLlmCatQuotaUnknown
        : t.categorizationAiQueueCounterA11y(
            s.remaining,
            catCount(context, ref, s.remaining),
          );
    return Padding(
      key: const ValueKey('cat-queue-counter'),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: ZSpacing.md,
        vertical: ZSpacing.sm,
      ),
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: ZType.label.copyWith(color: c.text)),
            if (s != null && s.remaining == 0)
              Text(
                t.categorizationAiQueueResetOn(_date(context, ref, s)),
                style: ZType.bodySmall.copyWith(color: c.textMuted),
              ),
          ],
        ),
      ),
    );
  }

  String _date(BuildContext context, WidgetRef ref, LlmQuotaSnapshot s) {
    final lang = Localizations.localeOf(context).languageCode;
    return ZDateFormat.date(
      s.resetsAt,
      lang,
      ref.watch(digitsModeProvider(lang)),
    );
  }
}
