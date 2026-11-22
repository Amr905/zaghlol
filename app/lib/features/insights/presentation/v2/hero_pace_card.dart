// T-209 (CHARTS-V2): the hero pace card of the Overview tab: what you spent
// so far, the day of the period, the comparison with the same days of the
// previous period, the pace chart with its legend, the projection and the
// three small stats (income, left in budget, bills coming).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/amount_semantics.dart';
import '../../../../core/ui/z_card.dart';
import '../../../budget/application/budget_providers.dart' show todayProvider;
import '../../domain/chart_summary.dart' show percentChange;
import '../../domain/overview_models.dart';
import '../../domain/pace.dart';
import '../charts/chart_card.dart';
import '../charts/chart_format.dart';
import '../charts/chart_overview.dart' show ChangeChip, toneOf;
import '../charts/charts_providers.dart';
import 'overview_providers.dart';
import 'pace_chart.dart';
import 'v2_format.dart';

class HeroPaceCard extends ConsumerWidget {
  const HeroPaceCard({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final pace = ref.watch(paceProvider(code));
    return pace.when(
      loading: () => ChartSkeleton(title: l.insightsV2HeroLabel),
      error: (_, _) => ChartError(
        title: l.insightsV2HeroLabel,
        onRetry: () => ref.invalidate(paceProvider(code)),
      ),
      data: (data) => _Hero(code: code, data: data),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.code, required this.data});
  final String code;
  final PaceData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final cur = Currency.of(code);
    String money(int minor) => chartMoney(ref, context, Money(cur, minor));
    final line = paceLineColor(c);
    final totals = ref.watch(overviewTotalsProvider(code)).value;
    final others =
        ref.watch(otherCurrencySpendProvider(code)).value ?? const [];
    final dues = ref.watch(upcomingDuesProvider(code)).value;
    final resolved = ref.watch(chartsResolvedPeriodProvider).value;
    final today = ref.watch(todayProvider);
    final billsEnd = resolved?.period.to;
    final bills = (dues == null || billsEnd == null || data.closed)
        ? null
        : duesUntil(dues, today, billsEnd, cur);
    final left = data.leftInBudgetMinor;

    // The comparison line (or the thin-data line).
    final Widget compare;
    final base = data.comparisonBase;
    if (data.thin || base == null) {
      compare = Text(
        l.insightsV2HeroThin,
        key: const Key('hero-thin'),
        style: ZType.bodySmall.copyWith(color: c.textMuted),
      );
    } else {
      final delta = data.spent - base;
      final trend =
          (delta > 0 ? _Sel.up : (delta < 0 ? _Sel.down : _Sel.other)).name;
      final change = percentChange(data.spent, base);
      final text = data.closed
          ? l.insightsV2HeroVsClosed(trend, money(delta.abs()))
          : l.insightsV2HeroVs(trend, money(delta.abs()));
      compare = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: ZSpacing.sm,
        runSpacing: ZSpacing.xs,
        children: [
          ChangeChip(change: change, tone: toneOf(change, moreIsGood: false)),
          Semantics(
            label: a11yAmounts(l, text),
            excludeSemantics: true,
            child: Text(
              text,
              key: const Key('hero-vs'),
              style: ZType.bodySmall.copyWith(color: c.text),
            ),
          ),
        ],
      );
    }

    // The projection (or, for a closed period, how it ended) against budget.
    String? panel;
    final over = data.overBudget;
    final state =
        (over == null ? _Sel.other : (over ? _Sel.over : _Sel.under)).name;
    if (data.closed) {
      if (data.budgetMinor != null && over != null) {
        panel = l.insightsV2HeroClosedBudget(state, money(data.budgetMinor!));
      }
    } else if (data.projectedMinor != null) {
      panel = l.insightsV2HeroProjection(
        state,
        money(data.projectedMinor!),
        data.budgetMinor == null ? '' : money(data.budgetMinor!),
      );
    }

    final prevNote = data.previousAt(data.elapsedDays);
    final a11y = [
      l.insightsV2PaceA11y(
        v2Digits(ref, context, data.elapsedDays),
        v2Digits(ref, context, data.periodDays),
        money(data.spent),
      ),
      if (prevNote != null) l.insightsV2PaceA11yPrev(money(prevNote)),
      if (data.projectedMinor != null)
        l.insightsV2PaceA11yProjected(money(data.projectedMinor!)),
    ].join('. ');

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: ZCard(
        padding: const EdgeInsetsDirectional.all(ZSpacing.lg + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data.closed
                        ? l.insightsV2HeroLabelClosed
                        : l.insightsV2HeroLabel,
                    style: ZType.bodySmall.copyWith(color: c.textMuted),
                  ),
                ),
                if (!data.closed)
                  Text(
                    l.insightsV2HeroDay(
                      v2Digits(ref, context, data.elapsedDays),
                      v2Digits(ref, context, data.periodDays),
                    ),
                    key: const Key('hero-day'),
                    style: ZType.caption.copyWith(color: c.textMuted),
                  ),
              ],
            ),
            const SizedBox(height: ZSpacing.xs),
            Semantics(
              label: a11yAmounts(l, money(data.spent)),
              excludeSemantics: true,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  isolate(money(data.spent)),
                  key: const Key('hero-spent'),
                  style: ZType.display.copyWith(color: c.text, fontSize: 40),
                ),
              ),
            ),
            const SizedBox(height: ZSpacing.xs),
            compare,
            for (final m in others)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                child: Semantics(
                  label: a11yAmounts(
                    l,
                    l.insightsV2OtherCurrency(chartMoney(ref, context, m)),
                  ),
                  excludeSemantics: true,
                  child: Text(
                    l.insightsV2OtherCurrency(
                      isolate(chartMoney(ref, context, m)),
                    ),
                    key: Key('hero-other-${m.currency.code}'),
                    style: ZType.bodySmall.copyWith(color: c.textMuted),
                  ),
                ),
              ),
            const SizedBox(height: ZSpacing.md),
            PaceChart(
              data: data,
              axisLabel: (m) => v2AxisMoney(ref, context, m, cur),
              dayLabel: (d) => v2Digits(ref, context, d),
              firstDayLabel: (d) =>
                  l.insightsV2PaceDay(v2Digits(ref, context, d)),
              budgetLabel: data.budgetMinor == null
                  ? null
                  : '${l.insightsV2LegendBudget} ${v2AxisMoney(ref, context, data.budgetMinor!, cur)}',
              scrubSpent: (d, spent) => l.insightsV2ScrubSpent(
                v2Digits(ref, context, d),
                money(spent),
              ),
              scrubLast: (p) => l.insightsV2ScrubLast(money(p)),
              semanticLabel: a11yAmounts(l, a11y),
              semanticHint: l.insightsV2ScrubHint,
            ),
            const SizedBox(height: ZSpacing.sm),
            Wrap(
              spacing: ZSpacing.lg,
              runSpacing: ZSpacing.xs,
              children: [
                _Legend(
                  PaceSwatch(color: line, kind: PaceSwatchKind.solid),
                  l.insightsV2LegendThis,
                ),
                if (data.previousCumulative.isNotEmpty)
                  _Legend(
                    PaceSwatch(
                      color: c.textMuted.withValues(alpha: .6),
                      kind: PaceSwatchKind.dashed,
                    ),
                    l.insightsV2LegendLast,
                  ),
                if (data.budgetMinor != null)
                  _Legend(
                    PaceSwatch(color: c.accent, kind: PaceSwatchKind.dotted),
                    l.insightsV2LegendBudget,
                  ),
                if (data.projectedMinor != null)
                  _Legend(
                    PaceSwatch(color: line, kind: PaceSwatchKind.dotted),
                    l.insightsV2LegendProjected,
                  ),
              ],
            ),
            if (panel != null) ...[
              const SizedBox(height: ZSpacing.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surfaceSunk,
                  borderRadius: BorderRadius.circular(ZRadius.md),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: ZSpacing.md,
                    vertical: ZSpacing.md,
                  ),
                  child: Semantics(
                    label: a11yAmounts(l, panel),
                    excludeSemantics: true,
                    child: Text(
                      panel,
                      key: const Key('hero-projection'),
                      style: ZType.bodySmall.copyWith(color: c.text),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: ZSpacing.md),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.outline)),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(top: ZSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Stat(
                      key: const Key('stat-income'),
                      label: l.insightsV2StatIncome,
                      value: totals == null
                          ? null
                          : chartMoney(ref, context, totals.income),
                      valueColor: c.incomeText,
                    ),
                    if (left != null)
                      _Stat(
                        key: const Key('stat-left'),
                        label: l.insightsV2StatLeft,
                        value: money(left),
                      ),
                    if (bills != null)
                      _Stat(
                        key: const Key('stat-bills'),
                        label: l.insightsV2StatBills,
                        value: chartMoney(ref, context, bills),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.swatch, this.label);
  final Widget swatch;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: ZSpacing.sm - 2),
        Flexible(
          child: Text(label, style: ZType.caption.copyWith(color: c.textMuted)),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String? value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final l = AppLocalizations.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: ZSpacing.sm),
        child: Semantics(
          container: true,
          label: a11yAmounts(l, '$label: ${value ?? ''}'),
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: ZType.caption.copyWith(color: c.textMuted)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value == null ? '' : isolate(value!),
                  style: ZType.titleSmall.copyWith(
                    color: valueColor ?? c.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ICU select keys for the hero copy (not user-facing text).
enum _Sel { up, down, over, under, other }
