// T-209 (CHARTS-V2): the Charts segment of Insights in its v2 form: three
// tabs (Overview / Categories / Trends) under the shared period control.
// The period applies to all tabs. The T-189 charts screen stays behind "All
// charts (12)".

import 'package:flutter/material.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_segmented.dart';
import '../charts/chart_period_bar.dart';
import 'categories_tab.dart';
import 'overview_tab.dart';
import 'trends_tab.dart';

enum InsightsV2Tab { overview, categories, trends }

class ChartsV2Screen extends StatefulWidget {
  const ChartsV2Screen({super.key, this.initial = InsightsV2Tab.overview});
  final InsightsV2Tab initial;

  @override
  State<ChartsV2Screen> createState() => _ChartsV2ScreenState();
}

class _ChartsV2ScreenState extends State<ChartsV2Screen> {
  late InsightsV2Tab _tab = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final body = switch (_tab) {
      InsightsV2Tab.overview => OverviewTab(
        onSeeAllCategories: () =>
            setState(() => _tab = InsightsV2Tab.categories),
      ),
      InsightsV2Tab.categories => const CategoriesTab(),
      InsightsV2Tab.trends => const TrendsTab(),
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            ZSpacing.screen,
            0,
            ZSpacing.screen,
            ZSpacing.xs,
          ),
          child: ZSegmentedControl<InsightsV2Tab>(
            segments: [
              ZSegment(
                value: InsightsV2Tab.overview,
                label: l.insightsV2TabOverview,
              ),
              ZSegment(
                value: InsightsV2Tab.categories,
                label: l.insightsV2TabCategories,
              ),
              ZSegment(
                value: InsightsV2Tab.trends,
                label: l.insightsV2TabTrends,
              ),
            ],
            selected: _tab,
            onChanged: (t) => setState(() => _tab = t),
          ),
        ),
        const Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: ZSpacing.screen),
          child: ChartPeriodBar(),
        ),
        Expanded(child: body),
      ],
    );
  }
}
