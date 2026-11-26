// T-362: the discovery card (FR-LCAT-40/41; Cat-1 mockup). The feature is off
// until the user allows it; when three or more unknown shops exist the card
// suggests it. "Let him guess" opens the consent sheet; "Not now" hides the
// card for 30 days (at most three times); "Don't ask again" hides it for
// good. Nothing is sent from here. Hidden while the `llm_categorise` flag is
// off or the provider is unknown (FU-425).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_card.dart';
import 'llm_cat_consent_sheet.dart';
import 'llm_cat_ui_providers.dart';

class LlmCatDiscoveryCard extends ConsumerWidget {
  const LlmCatDiscoveryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(catCardVisibleProvider).value ?? false)) {
      return const SizedBox.shrink();
    }
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final n = ref.watch(catEligibleCountProvider).value ?? 0;
    final stack = MediaQuery.textScalerOf(context).scale(16) > 16 * 1.2;
    final allow = ZButton(
      key: const ValueKey('cat-card-allow'),
      label: t.categorizationAiCardAllow,
      expand: true,
      onPressed: () => LlmCatConsentFlow.prompt(context, ref),
    );
    final notNow = ZButton(
      key: const ValueKey('cat-card-not-now'),
      label: t.categorizationAiCardNotNow,
      variant: ZButtonVariant.secondary,
      expand: true,
      onPressed: () async {
        await LlmCatCardActions.notNow(ref);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.categorizationAiConsentDeclined)),
          );
        }
      },
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.md),
      child: Semantics(
        container: true,
        label: t.categorizationAiCardTitle(n, catCount(context, ref, n)),
        child: ZCard(
          key: const ValueKey('cat-discovery-card'),
          color: c.zaghlolBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.categorizationAiCardTitle(n, catCount(context, ref, n)),
                style: ZType.titleSmall.copyWith(color: c.zaghlolText),
              ),
              const SizedBox(height: ZSpacing.xs),
              Text(
                t.categorizationAiCardBody,
                style: ZType.bodySmall.copyWith(color: c.zaghlolText),
              ),
              const SizedBox(height: ZSpacing.md),
              if (stack) ...[
                allow,
                const SizedBox(height: ZSpacing.sm),
                notNow,
              ] else
                Row(
                  children: [
                    Expanded(child: allow),
                    const SizedBox(width: ZSpacing.md),
                    Expanded(child: notNow),
                  ],
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ZButton(
                  key: const ValueKey('cat-card-never'),
                  label: t.categorizationAiCardNever,
                  variant: ZButtonVariant.text,
                  onPressed: () => LlmCatCardActions.never(ref),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
