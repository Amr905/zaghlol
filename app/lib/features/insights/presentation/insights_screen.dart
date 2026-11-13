// T-101: the Insights tab shell (S-20): a Charts | Budget | Bills segmented
// header. Charts (T-107) and Bills (T-102) plug in through the builders;
// until then their segments are empty. `zaghlol://budget` selects Budget.

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_segmented.dart';
import '../../budget/presentation/budget_screen.dart';

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
        widget.chartsBuilder?.call(context) ?? const SizedBox.expand(),
      InsightsSegment.budget =>
        widget.budgetBuilder?.call(context) ?? const BudgetScreen(),
      InsightsSegment.bills =>
        widget.billsBuilder?.call(context) ?? const SizedBox.expand(),
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
              child: ZSegmentedControl<InsightsSegment>(
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
            ),
            Expanded(child: body),
          ],
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
