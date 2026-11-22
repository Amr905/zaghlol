// QA BUG-013 (B57): after stepping a relative preset with the arrows, the
// period chip's spoken label still names the original preset. "This month"
// stepped back once shows last month's range but TalkBack says
// "Chart period: This month, 1 Oct – 31 Oct". Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/insights/domain/chart_period_selection.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_period_bar.dart';

import '../features/insights/presentation/charts/charts_test_support.dart';

void main() {
  testWidgets('BUG-013 stepped "This month" is not announced as This month', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      harness(
        const Material(child: ChartPeriodBar()),
        locale: const Locale('en'),
        overrides: chartOverrides(
          selection: const ChartPeriodSelection(
            ChartPreset.thisMonth,
            offset: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(ChartPeriodBar)));
    final node = tester.getSemantics(find.byKey(const Key('charts-period')));
    handle.dispose();
    // The chip shows last month's range; its spoken name must not be
    // "This month".
    expect(
      node.label.contains(l.commonPeriodThisMonth),
      isFalse,
      reason: node.label,
    );
  });
}
