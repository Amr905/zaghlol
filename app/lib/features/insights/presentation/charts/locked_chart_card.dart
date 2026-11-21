// T-107: the Gold-locked chart preview (C-13 locked). It draws a fixed,
// generic silhouette: no query runs and no real figure is ever painted, so
// nothing readable sits behind the overlay (FR-GOLD-05).

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_button.dart';
import '../../../gold/application/gating.dart';
import 'chart_card.dart';
import 'chart_palette.dart';

class LockedChartCard extends ConsumerWidget {
  const LockedChartCard({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Semantics(
      label: '$title. ${l.commonGoldLockedA11y}',
      container: true,
      child: ChartCard(
        title: title,
        meta: null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                ExcludeSemantics(
                  child: Opacity(
                    opacity: 0.5,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                      child: SizedBox(
                        height: 96,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final h in const [
                              0.4,
                              0.7,
                              0.55,
                              0.85,
                              0.5,
                              0.65,
                            ])
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsetsDirectional.symmetric(
                                        horizontal: ZSpacing.xs,
                                      ),
                                  child: FractionallySizedBox(
                                    heightFactor: h,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: ZChartColors.incomeOf(
                                          ZColors.of(context),
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          ZRadius.sm,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.zaghlolBg,
                      borderRadius: BorderRadius.circular(ZRadius.pill),
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: ZSpacing.md,
                        vertical: ZSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_border,
                            size: 18,
                            color: c.warningText,
                          ),
                          const SizedBox(width: ZSpacing.xs),
                          Text(
                            l.commonGoldBadge,
                            style: ZType.label.copyWith(color: c.warningText),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZSpacing.sm),
            Text(
              l.insightsChartsLockedSub,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.sm),
            ZButton(
              label: l.commonGoldUnlock,
              variant: ZButtonVariant.gold,
              onPressed: () =>
                  ref.read(paywallTriggerProvider)(GoldCapability.allCharts),
            ),
          ],
        ),
      ),
    );
  }
}
