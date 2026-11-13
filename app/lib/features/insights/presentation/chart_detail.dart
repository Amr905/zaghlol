// T-108: S-21 Chart detail & explanation (mockup 08). The chart at full
// width, then Captain Zaghlol's explainer (C-15): a typing indicator of at
// most 600 ms, then the fact and the tip from the T-106 engine. Free sees the
// basic tier plus one deep upsell; Gold sees the deep tier (T-119). A Free
// user on a Gold chart sees the locked preview and the paywall CTA. The
// mascot ignores pointers, so it never blocks anything.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../budget/presentation/budget_providers_ui.dart';
import '../../gold/application/gating.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import '../application/chart_gate.dart';
import '../domain/chart_models.dart';
import '../domain/explanations.dart';
import 'chart_explain_l10n.dart';
import 'chart_explain_providers.dart';
import 'charts/chart_bodies.dart';
import 'charts/chart_card.dart';
import 'charts/chart_format.dart';
import 'charts/charts_providers.dart';

/// The typing indicator never runs longer than this (S-21).
const Duration chartTypingDuration = Duration(milliseconds: 500);

String chartDetailTitle(AppLocalizations l, ChartId id) => switch (id) {
  ChartId.cashFlow => l.insightsChartTitleCashFlow,
  ChartId.categoryDonut => l.insightsChartTitleCategories,
  ChartId.burnCurve => l.insightsChartTitleBurnRate,
  ChartId.fiftyThirtyTwenty => l.insightsChartTitleRule503020,
  ChartId.dayHourPattern => l.insightsChartTitleWeekPattern,
  ChartId.topMerchants => l.insightsChartTitleMerchants,
  ChartId.monthVsAverage => l.insightsChartTitleVsAverage,
  ChartId.installmentTimeline => l.insightsChartTitleInstallments,
  ChartId.subscriptionsAnnual => l.insightsChartTitleSubscriptions,
  ChartId.cardsSplit => l.insightsChartTitleCards,
  ChartId.netWorth => l.insightsChartTitleNetWorth,
  ChartId.personalInflation => l.insightsChartTitleInflation,
  ChartId.budgetProgress => l.insightsTabsBudget,
};

/// Opens S-21 for [chart] in currency [code]. [openExplainer] is the
/// "Explain" entry on the chart cards: the explainer starts already open.
Future<void> openChartDetail(
  BuildContext context, {
  required ChartId chart,
  required String code,
  bool openExplainer = false,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => ChartDetailScreen(
      chart: chart,
      code: code,
      openExplainer: openExplainer,
    ),
  ),
);

class ChartDetailScreen extends ConsumerWidget {
  const ChartDetailScreen({
    super.key,
    required this.chart,
    required this.code,
    this.openExplainer = false,
  });

  final ChartId chart;
  final String code;
  final bool openExplainer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final title = chartDetailTitle(l, chart);
    final locked = !decideChart(
      ref.watch(entitlementStateProvider),
      chart,
    ).allowed;
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        leading: IconButton(
          tooltip: l.commonActionBackA11y,
          icon: const BackButtonIcon(),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          ZSpacing.screen,
          ZSpacing.sm,
          ZSpacing.screen,
          ZSpacing.xxl,
        ),
        children: [
          if (locked)
            _LockedDetail(title: title)
          else ...[
            _ChartSection(chart: chart, code: code, title: title),
            _Explainer(chart: chart, code: code, startOpen: openExplainer),
          ],
        ],
      ),
    );
  }
}

String _contextLine(AppLocalizations l, String code) => l.insightsChartsContext(
  l.commonCardFilterAll,
  code,
  l.commonPeriodThisCycle,
);

class _LockedDetail extends ConsumerWidget {
  const _LockedDetail({required this.title});
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return ChartCard(
      title: l.insightsChartDetailLockedTitle,
      trailing: ExcludeSemantics(
        child: Icon(Icons.lock_outline, size: 20, color: c.accentDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.insightsChartDetailLockedBody,
            style: ZType.body.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.md),
          ZButton(
            label: l.commonGoldUnlock,
            variant: ZButtonVariant.gold,
            onPressed: () =>
                ref.read(paywallTriggerProvider)(GoldCapability.allCharts),
          ),
        ],
      ),
    );
  }
}

/// The large chart. Only the charts with a query provider draw; any other
/// chart (Gold, not wired yet) says what it needs.
class _ChartSection extends ConsumerWidget {
  const _ChartSection({
    required this.chart,
    required this.code,
    required this.title,
  });
  final ChartId chart;
  final String code;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    String money0(Money m) => chartMoney(ref, context, m);
    Widget empty(ChartNotEnoughData<Object?>? r) => ChartCard(
      title: title,
      contextLine: _contextLine(l, code),
      child: ChartMessage(
        text: r?.reason == NotEnoughReason.noData
            ? l.insightsChartsEmptyFilter
            : l.insightsChartsEmptyCycle,
      ),
    );
    Widget skeleton() => ChartSkeleton(title: title);
    Widget error(VoidCallback retry) =>
        ChartError(title: title, onRetry: retry);

    switch (chart) {
      case ChartId.cashFlow:
        return ref
            .watch(cashFlowChartProvider(code))
            .when(
              loading: skeleton,
              error: (_, _) =>
                  error(() => ref.invalidate(cashFlowChartProvider(code))),
              data: (r) => switch (r) {
                ChartReady(:final data) => ChartCard(
                  title: title,
                  contextLine: _contextLine(l, code),
                  summary: CashFlowBody.summary(l, money0, data),
                  child: CashFlowBody(points: data),
                ),
                ChartNotEnoughData() => empty(r),
              },
            );
      case ChartId.categoryDonut:
        final arabic = Localizations.localeOf(context).languageCode == 'ar';
        final cats = ref.watch(categoryRowsProvider).value ?? const [];
        String nameOf(String? id) {
          for (final c in cats) {
            if (c.id == id) return arabic ? c.nameAr : c.nameEn;
          }
          return l.insightsChartsOtherSlice;
        }

        return ref
            .watch(donutChartProvider(code))
            .when(
              loading: skeleton,
              error: (_, _) =>
                  error(() => ref.invalidate(donutChartProvider(code))),
              data: (r) => switch (r) {
                ChartReady(:final data) => ChartCard(
                  title: title,
                  contextLine: _contextLine(l, code),
                  summary: DonutBody.summary(
                    l,
                    money0,
                    (bp) => chartPercentBp(ref, context, bp),
                    data,
                    nameOf,
                  ),
                  child: DonutBody(donut: data, nameOf: nameOf),
                ),
                ChartNotEnoughData() => empty(r),
              },
            );
      case ChartId.topMerchants:
        return ref
            .watch(merchantsChartProvider(code))
            .when(
              loading: skeleton,
              error: (_, _) =>
                  error(() => ref.invalidate(merchantsChartProvider(code))),
              data: (r) => switch (r) {
                ChartReady(:final data) when data.isNotEmpty => ChartCard(
                  title: title,
                  contextLine: _contextLine(l, code),
                  summary: MerchantsBody.summary(l, money0, data),
                  child: MerchantsBody(rows: data),
                ),
                ChartReady() => empty(null),
                ChartNotEnoughData() => empty(r),
              },
            );
      default:
        return ChartCard(
          title: title,
          contextLine: _contextLine(l, code),
          child: ChartMessage(
            text: l.insightsChartDetailNeedsData(
              needsDataFor(chart, NotEnoughReason.noData),
            ),
          ),
        );
    }
  }
}

/// C-15: the professor bubble. Closed it offers the button; open it types for
/// [chartTypingDuration] then shows the lines.
class _Explainer extends ConsumerStatefulWidget {
  const _Explainer({
    required this.chart,
    required this.code,
    required this.startOpen,
  });
  final ChartId chart;
  final String code;
  final bool startOpen;

  @override
  ConsumerState<_Explainer> createState() => _ExplainerState();
}

class _ExplainerState extends ConsumerState<_Explainer> {
  bool _open = false;
  bool _typing = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.startOpen) _begin();
  }

  void _begin() {
    _open = true;
    _typing = true;
    _timer = Timer(chartTypingDuration, () {
      if (mounted) setState(() => _typing = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final key = (chart: widget.chart, code: widget.code);
    final outcome = _open ? ref.watch(chartExplanationProvider(key)) : null;
    final busy = _typing || (outcome?.isLoading ?? false);

    // Explainer failed: hide the bubble, the chart stays (S-21 error).
    if (outcome != null && outcome.hasError) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
        child: Text(
          l.insightsChartDetailExplainFailed,
          style: ZType.caption.copyWith(color: c.textMuted),
        ),
      );
    }

    final Widget content;
    if (!_open) {
      content = Align(
        alignment: AlignmentDirectional.centerStart,
        child: ZButton(
          label: l.insightsChartsExplain,
          variant: ZButtonVariant.secondary,
          onPressed: () => setState(_begin),
        ),
      );
    } else if (busy) {
      content = Semantics(
        label: l.insightsChartDetailTypingA11y,
        container: true,
        liveRegion: true,
        child: const ExcludeSemantics(child: _TypingDots()),
      );
    } else {
      content = _Lines(chart: widget.chart, outcome: outcome!.requireValue);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ZaghlolAvatar(moment: ZaghlolMoment.professor, talk: busy, size: 64),
        const SizedBox(width: ZSpacing.sm),
        Expanded(
          child: Container(
            key: const ValueKey('explainer-bubble'),
            padding: const EdgeInsets.all(ZSpacing.md),
            decoration: BoxDecoration(
              color: c.zaghlolBg,
              borderRadius: BorderRadius.circular(ZRadius.lg),
            ),
            child: content,
          ),
        ),
      ],
    );
  }
}

class _Lines extends ConsumerWidget {
  const _Lines({required this.chart, required this.outcome});
  final ChartId chart;
  final ExplainOutcome outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    final cats = ref.watch(categoryRowsProvider).value ?? const [];
    final fmt = ExplainFormat.of(context, ref, (id) {
      for (final r in cats) {
        if (r.id == id) return arabic ? r.nameAr : r.nameEn;
      }
      return l.insightsChartsOtherSlice;
    });
    final e = outcome.explanation;
    if (e.isEmpty) {
      return Text(
        l.insightsChartDetailNeedsData(
          needsDataFor(chart, outcome.reason ?? NotEnoughReason.noData),
        ),
        style: ZType.body.copyWith(color: c.text),
      );
    }

    Widget text(ExplanationLine line) => Text(
      renderExplanationLine(fmt, line),
      style: ZType.body.copyWith(color: c.text),
    );
    Widget labelled(String label, IconData icon, ExplanationLine line) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 20, color: c.accentDark)),
        const SizedBox(width: ZSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: ZType.caption.copyWith(color: c.textMuted)),
              text(line),
            ],
          ),
        ),
      ],
    );

    const gap = SizedBox(height: ZSpacing.md);
    final children = <Widget>[];
    for (final line in e.lines) {
      if (children.isNotEmpty) children.add(gap);
      children.add(switch (line.key.part) {
        ExplanationPart.tip => labelled(
          l.insightsChartDetailTipLabel,
          Icons.lightbulb_outline,
          line,
        ),
        ExplanationPart.deepFact ||
        ExplanationPart.deepTip ||
        ExplanationPart.projection ||
        ExplanationPart.drivers => labelled(
          l.insightsChartDetailDeepLabel,
          Icons.insights_outlined,
          line,
        ),
        ExplanationPart.fact => text(line),
      });
    }
    if (e.offersDeepUpsell) {
      children
        ..add(gap)
        ..add(
          Text(
            l.insightsChartDetailDeepUpsell,
            style: ZType.caption.copyWith(color: c.textMuted),
          ),
        )
        ..add(const SizedBox(height: ZSpacing.sm))
        ..add(
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ZButton(
              label: l.commonGoldUnlock,
              variant: ZButtonVariant.gold,
              onPressed: () =>
                  ref.read(paywallTriggerProvider)(GoldCapability.deepCoaching),
            ),
          ),
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// Three pulsing dots. A static row under reduce motion.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctl.stop();
    } else if (!_ctl.isAnimating) {
      _ctl.repeat();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return SizedBox(
      height: ZSpacing.xl,
      child: AnimatedBuilder(
        animation: _ctl,
        builder: (_, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: ZSpacing.xs),
                child: Opacity(
                  opacity: 0.35 + 0.65 * ((_ctl.value + i / 3) % 1.0),
                  child: Container(
                    width: ZSpacing.sm,
                    height: ZSpacing.sm,
                    decoration: BoxDecoration(
                      color: c.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
