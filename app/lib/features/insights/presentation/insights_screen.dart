// T-101: the Insights tab shell (S-20): a Charts | Budget | Bills segmented
// header. Charts (T-107) and Bills (T-102) plug in through the builders;
// until then their segments are empty. `zaghlol://budget` selects Budget.

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_segmented.dart';
import '../../budget/presentation/budget_screen.dart';
import '../../home/presentation/home_widgets.dart';
import 'v2/insights_v2_screen.dart';
import '../../recurring/presentation/bills_screen.dart';
import '../../../core/ui/z_hide_amounts_button.dart';

enum InsightsSegment { charts, budget, bills }

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    this.initial = InsightsSegment.charts,
    this.chartsBuilder,
    this.billsBuilder,
    this.budgetBuilder,
  });

  final InsightsSegment initial;
  final WidgetBuilder? chartsBuilder;
  final WidgetBuilder? billsBuilder;
  final WidgetBuilder? budgetBuilder;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late InsightsSegment _segment = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final body = switch (_segment) {
      InsightsSegment.charts =>
        widget.chartsBuilder?.call(context) ?? const ChartsV2Screen(),
      InsightsSegment.budget =>
        widget.budgetBuilder?.call(context) ?? const BudgetScreen(),
      InsightsSegment.bills =>
        widget.billsBuilder?.call(context) ?? const BillsScreen(),
    };
    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                ZSpacing.screen,
                ZSpacing.sm,
                ZSpacing.screen,
                ZSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [HomeCardFilterChip()]),
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.symmetric(
                              vertical: ZSpacing.sm,
                            ),
                            child: Text(
                              l.commonNavInsights,
                              style: ZType.display.copyWith(color: c.text),
                            ),
                          ),
                        ),
                      ),
                      // D-67: hides the amounts of Charts, Budget and Bills.
                      const ZHideAmountsButton(),
                    ],
                  ),
                  _InsightsTabs(
                    segments: [
                      ZSegment(
                        value: InsightsSegment.charts,
                        label: l.insightsTabsCharts,
                      ),
                      ZSegment(
                        value: InsightsSegment.budget,
                        label: l.insightsTabsBudget,
                      ),
                      ZSegment(
                        value: InsightsSegment.bills,
                        label: l.insightsTabsBills,
                      ),
                    ],
                    selected: _segment,
                    onChanged: (s) => setState(() => _segment = s),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// The Insights tab switcher (mockups 07/09/10): a mint track with the
/// selected tab raised as a white pill. Local to this shell.
class _InsightsTabs extends StatelessWidget {
  const _InsightsTabs({
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<ZSegment<InsightsSegment>> segments;
  final InsightsSegment selected;
  final ValueChanged<InsightsSegment> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final shape = BorderRadius.circular(ZRadius.pill);
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: shape),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(ZSpacing.xs),
          child: Row(
            children: [
              for (final s in segments)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: s.value == selected,
                    label: s.label,
                    excludeSemantics: true,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: s.value == selected
                            ? c.surface
                            : Colors.transparent,
                        borderRadius: shape,
                        border: s.value == selected ? c.flatBorder : null,
                        boxShadow: s.value == selected
                            ? [
                                BoxShadow(
                                  color: c.shadow,
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: InkWell(
                        borderRadius: shape,
                        onTap: () => onChanged(s.value),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: ZSpacing.minTarget,
                          ),
                          child: Center(
                            child: Text(
                              s.label,
                              textAlign: TextAlign.center,
                              style: ZType.titleSmall.copyWith(
                                color: s.value == selected
                                    ? c.text
                                    : c.textMuted,
                                fontWeight: s.value == selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
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
    );
  }
}

/// The `TabRoots.insights` builder (T-024); the composition root passes it to
/// `tabRootsProvider`. `zaghlol://budget` lands on the Budget segment through
/// [initial].
Widget insightsTabRoot(
  BuildContext context, {
  InsightsSegment initial = InsightsSegment.charts,
}) => InsightsScreen(initial: initial);
