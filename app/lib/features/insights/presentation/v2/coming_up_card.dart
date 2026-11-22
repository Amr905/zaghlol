// T-209 (CHARTS-V2): "Coming up": the next three subscriptions, bills and
// instalments with "in N days" and the amount. Free. Hidden when nothing is
// due (and while it loads or fails: a missing nice-to-have is not an error).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/amount_semantics.dart';
import '../../../budget/application/budget_providers.dart' show todayProvider;
import '../../domain/overview_models.dart';
import '../charts/chart_format.dart';
import 'overview_providers.dart';
import 'v2_card.dart';
import 'v2_format.dart';

class ComingUpCard extends ConsumerWidget {
  const ComingUpCard({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final today = ref.watch(todayProvider);
    final dues = ref.watch(upcomingDuesProvider(code)).value;
    if (dues == null) return const SizedBox.shrink();
    final next = nextDues(dues, today);
    if (next.isEmpty) return const SizedBox.shrink();
    return V2Card(
      title: l.insightsV2UpTitle,
      child: Column(
        children: [
          for (final d in next) _Row(due: d, days: d.date.difference(today)),
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.due, required this.days});
  final UpcomingDue due;
  final int days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final when = l.insightsV2UpIn(days, v2Digits(ref, context, days));
    final amount = chartMoney(ref, context, due.amount);
    return Semantics(
      label: a11yAmounts(l, l.insightsV2UpA11y(due.name, when, amount)),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 8, height: 8),
            ),
            const SizedBox(width: ZSpacing.md - 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    due.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ZType.bodySmall.copyWith(color: c.text),
                  ),
                  Text(when, style: ZType.caption.copyWith(color: c.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: ZSpacing.sm),
            Text(
              isolate(amount),
              style: ZType.bodySmall.copyWith(
                color: c.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
