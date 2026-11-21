// T-189: the top of the redesigned charts screen: the summary strip (spent,
// income, saved, savings rate, each against the previous period of the same
// elapsed length), the Zaghlol one-liner and the shared change chip. One
// currency at a time: nothing here adds two currencies. Colour is never the
// only cue: every chip carries an arrow or "=" and a spoken label. Spending
// that went up is apricot, never red; hide-amounts masks the figures but
// keeps the percentages.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_mascot_bubble.dart';
import '../../../../core/ui/amount_semantics.dart';
import '../../../../core/ui/z_money_text.dart';
import '../../../mascot/presentation/zaghlol_avatar.dart' show ZaghlolMoment;
import '../../domain/chart_models.dart' show ChartReady;
import '../../domain/chart_period_selection.dart' show ResolvedChartPeriod;
import '../../domain/chart_summary.dart';
import 'chart_card.dart';
import 'chart_format.dart';
import 'chart_period_text.dart';
import 'charts_providers.dart';

/// How a change reads: [good] green, [warn] apricot (never red), [neutral].
enum ChangeTone { good, warn, neutral }

/// The tone of [change]; [moreIsGood] is false for spending.
ChangeTone toneOf(ChartChange change, {required bool moreIsGood}) {
  switch (change.direction) {
    case ChangeDirection.up:
      return moreIsGood ? ChangeTone.good : ChangeTone.warn;
    case ChangeDirection.down:
      return moreIsGood ? ChangeTone.warn : ChangeTone.good;
    case ChangeDirection.same:
    case ChangeDirection.none:
      return ChangeTone.neutral;
  }
}

String _digitsOf(WidgetRef ref, BuildContext context, String s) => ref
    .watch(digitsModeProvider(Localizations.localeOf(context).languageCode))
    .render(s);

/// The visible text of a change ("▲ 12%", "▼ 4 pts", "= same", "New").
String changeText(
  WidgetRef ref,
  BuildContext context,
  AppLocalizations l,
  ChartChange c,
) {
  final n = _digitsOf(ref, context, '${c.value}');
  final pct = chartPercent(ref, context, c.value);
  switch (c.direction) {
    case ChangeDirection.up:
      return c.isPoints ? l.insightsChangeUpPts(n) : l.insightsChangeUpPct(pct);
    case ChangeDirection.down:
      return c.isPoints
          ? l.insightsChangeDownPts(n)
          : l.insightsChangeDownPct(pct);
    case ChangeDirection.same:
      return l.insightsChangeSame;
    case ChangeDirection.none:
      return l.insightsChangeNew;
  }
}

/// The spoken text of a change.
String changeA11y(
  WidgetRef ref,
  BuildContext context,
  AppLocalizations l,
  ChartChange c,
) {
  final n = _digitsOf(ref, context, '${c.value}');
  final pct = chartPercent(ref, context, c.value);
  switch (c.direction) {
    case ChangeDirection.up:
      return c.isPoints
          ? l.insightsChangeA11yUpPts(n)
          : l.insightsChangeA11yUp(pct);
    case ChangeDirection.down:
      return c.isPoints
          ? l.insightsChangeA11yDownPts(n)
          : l.insightsChangeA11yDown(pct);
    case ChangeDirection.same:
      return l.insightsChangeA11ySame;
    case ChangeDirection.none:
      return l.insightsChangeA11yNew;
  }
}

/// A small pill with a change ("▲ 12%"); excluded from semantics: the owner
/// speaks it.
class ChangeChip extends ConsumerWidget {
  const ChangeChip({super.key, required this.change, required this.tone});
  final ChartChange change;
  final ChangeTone tone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final (bg, fg) = switch (tone) {
      ChangeTone.good => (c.incomeBg, c.incomeText),
      ChangeTone.warn => (c.warningBg, c.warningText),
      ChangeTone.neutral => (c.surfaceAlt, c.textMuted),
    };
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(ZRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.sm,
            vertical: ZSpacing.xs / 2,
          ),
          child: Text(
            '\u2068${changeText(ref, context, l, change)}\u2069',
            style: ZType.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// The text naming the baseline ("last month", "the same 26 days of last
/// month").
String baselineText(
  AppLocalizations l,
  ChartPeriodText text,
  ResolvedChartPeriod r,
) {
  final name = text.prevName(r);
  return r.previousCapped
      ? l.insightsSummaryBaselineDays(
          text.digits.render('${r.previous.lengthDays}'),
          name,
        )
      : l.insightsSummaryBaseline(name);
}

class _Tile extends ConsumerWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.change,
    required this.moreIsGood,
    required this.baseline,
    this.valueKey,
  });
  final String label;
  final String value;
  final ChartChange change;
  final bool moreIsGood;
  final String baseline;
  final Key? valueKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Semantics(
      container: true,
      label: a11yLabel(ref, context, l),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(ZRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.md,
            vertical: ZSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: ZType.caption.copyWith(color: c.textMuted)),
              const SizedBox(height: ZSpacing.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '\u2068$value\u2069',
                  key: valueKey,
                  style: ZType.headline.copyWith(color: c.text),
                ),
              ),
              const SizedBox(height: ZSpacing.xs),
              ChangeChip(
                change: change,
                tone: toneOf(change, moreIsGood: moreIsGood),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String a11yLabel(WidgetRef ref, BuildContext context, AppLocalizations l) =>
      a11yAmounts(
        l,
        l.insightsSummaryTileA11y(
          label,
          value,
          changeA11y(ref, context, l, change),
          baseline,
        ),
      );
}

/// The four-figure summary with its baseline line and the Zaghlol line.
class ChartSummaryStrip extends ConsumerWidget {
  const ChartSummaryStrip({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final resolved = ref.watch(chartsResolvedPeriodProvider).value;
    final summary = ref.watch(chartSummaryProvider(code));
    return summary.when(
      loading: () => Semantics(
        label: l.insightsChartsLoadingA11y,
        container: true,
        child: ExcludeSemantics(
          child: Column(
            children: [
              for (var i = 0; i < 2; i++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    bottom: ZSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      for (var j = 0; j < 2; j++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: ZSpacing.xs,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.surfaceAlt,
                                borderRadius: BorderRadius.circular(ZRadius.lg),
                              ),
                              child: const SizedBox(height: 84),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      error: (_, _) => ChartError(
        title: l.insightsTabsCharts,
        onRetry: () => ref.invalidate(chartSummaryProvider(code)),
      ),
      data: (s) {
        if (resolved == null) return const SizedBox.shrink();
        final text = ChartPeriodText.of(context, ref);
        if (s.isEmpty) {
          return Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
            child: ZMascotBubble(
              message: l.insightsSummaryEmpty,
              moment: ZaghlolMoment.thinking,
              avatarSize: 40,
            ),
          );
        }
        final baseline = baselineText(l, text, resolved);
        final rate = s.ratePct;
        Widget row(_Tile a, _Tile b) => Padding(
          padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: a),
                const SizedBox(width: ZSpacing.sm),
                Expanded(child: b),
              ],
            ),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(
              _Tile(
                label: l.insightsSummarySpent,
                value: trimCurrency(chartMoney(ref, context, s.spent)),
                change: s.spentChange,
                moreIsGood: false,
                baseline: baseline,
                valueKey: const Key('summary-spent'),
              ),
              _Tile(
                label: l.insightsSummaryIncome,
                value: trimCurrency(chartMoney(ref, context, s.income)),
                change: s.incomeChange,
                moreIsGood: true,
                baseline: baseline,
                valueKey: const Key('summary-income'),
              ),
            ),
            row(
              _Tile(
                label: l.insightsSummarySaved,
                value: trimCurrency(chartMoney(ref, context, s.saved)),
                change: s.savedChange,
                moreIsGood: true,
                baseline: baseline,
                valueKey: const Key('summary-saved'),
              ),
              _Tile(
                label: l.insightsSummaryRate,
                value: rate == null
                    ? kNoValueDash
                    : chartPercent(ref, context, rate),
                change: s.rateChange,
                moreIsGood: true,
                baseline: baseline,
                valueKey: const Key('summary-rate'),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
              child: Text(
                baseline,
                textAlign: TextAlign.center,
                style: ZType.caption.copyWith(color: c.textMuted),
              ),
            ),
            _OneLiner(code: code, summary: s, prev: text.prevName(resolved)),
          ],
        );
      },
    );
  }
}

class _OneLiner extends ConsumerWidget {
  const _OneLiner({
    required this.code,
    required this.summary,
    required this.prev,
  });
  final String code;
  final ChartSummary summary;
  final String prev;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final donut = ref.watch(donutChartProvider(code)).value;
    final before = ref.watch(previousDonutProvider(code)).value;
    final entries = switch (donut) {
      ChartReady(:final data) => topCategoriesPlusOther(data, previous: before),
      _ => const <DonutEntry>[],
    };
    final insight = pickInsight(summary, entries);
    final pct = chartPercent(
      ref,
      context,
      insight.kind == ChartInsightKind.downWithRiser ||
              insight.kind == ChartInsightKind.upWithRiser
          ? insight.riserPct
          : summary.spentChange.value,
    );
    final category = chartCategoryName(ref, context, insight.riserId);
    final message = switch (insight.kind) {
      ChartInsightKind.downWithRiser => l.insightsOneLinerDownRiser(
        category,
        pct,
        prev,
      ),
      ChartInsightKind.down => l.insightsOneLinerDown(prev),
      ChartInsightKind.upWithRiser => l.insightsOneLinerUpRiser(
        category,
        pct,
        prev,
      ),
      ChartInsightKind.up => l.insightsOneLinerUp(prev),
      ChartInsightKind.same => l.insightsOneLinerSame(prev),
      ChartInsightKind.noBaseline => l.insightsOneLinerNoBaseline,
    };
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: ZMascotBubble(
        message: message,
        moment: switch (insight.kind) {
          ChartInsightKind.up ||
          ChartInsightKind.upWithRiser => ZaghlolMoment.detective,
          ChartInsightKind.noBaseline => ZaghlolMoment.thinking,
          _ => ZaghlolMoment.proud,
        },
        avatarSize: 40,
      ),
    );
  }
}
