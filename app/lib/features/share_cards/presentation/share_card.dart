// T-117 C-34: the branded card. Hidden mode renders percentages only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../insights/presentation/charts/chart_format.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import '../domain/share_figures.dart';

/// The card line for [figure]; the amount variant only when [showAmounts].
String shareCardText(
  WidgetRef ref,
  BuildContext context,
  ShareFigure figure,
  bool showAmounts,
) {
  final l = AppLocalizations.of(context);
  final pct = chartPercent(ref, context, figure.percent);
  final amt = chartMoney(ref, context, figure.amount);
  return switch ((figure.template, showAmounts)) {
    (ShareTemplate.savings, false) => l.shareStudioCardSavings(pct),
    (ShareTemplate.savings, true) => l.shareStudioCardSavingsAmount(amt),
    (ShareTemplate.delivery, false) => l.shareStudioCardDelivery(pct),
    (ShareTemplate.delivery, true) => l.shareStudioCardDeliveryAmount(amt),
    (ShareTemplate.budget, false) => l.shareStudioCardBudget(pct),
    (ShareTemplate.budget, true) => l.shareStudioCardBudgetAmount(amt),
  };
}

class ShareCard extends ConsumerWidget {
  const ShareCard({super.key, required this.figure, required this.showAmounts});

  final ShareFigure figure;
  final bool showAmounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ZColors.of(context);
    final l = AppLocalizations.of(context);
    final text = shareCardText(ref, context, figure, showAmounts);
    return Semantics(
      container: true,
      label: l.shareStudioPreviewA11y(text),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
        decoration: BoxDecoration(
          color: c.accentLight,
          borderRadius: BorderRadius.circular(ZRadius.card),
          border: Border.all(color: c.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const ZaghlolAvatar(moment: ZaghlolMoment.proud, size: 72),
                const SizedBox(width: ZSpacing.md),
                Expanded(
                  child: Text(
                    l.shareStudioCertificate,
                    style: ZType.caption.copyWith(color: c.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZSpacing.lg),
            Text(text, style: ZType.title.copyWith(color: c.text)),
            const SizedBox(height: ZSpacing.lg),
            Text(
              l.shareStudioHashtag,
              style: ZType.body.copyWith(color: c.primary),
            ),
          ],
        ),
      ),
    );
  }
}
