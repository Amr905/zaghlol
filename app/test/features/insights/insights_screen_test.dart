// T-101: the Insights shell segments.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/insights/presentation/insights_screen.dart';

import '../budget/presentation/budget_test_support.dart';

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    testWidgets('segments switch ${locale.languageCode}', (tester) async {
      await initDateFormatting();
      await tester.pumpWidget(
        harness(
          InsightsScreen(
            chartsBuilder: (_) => const Text('charts-body'),
            billsBuilder: (_) => const Text('bills-body'),
          ),
          locale: locale,
          scale: 1.3,
          overrides: [
            budgetScreenDataProvider.overrideWith(
              (ref) async => data([egpView()]),
            ),
          ],
        ),
      );
      await tester.pump();
      final l = AppLocalizations.of(
        tester.element(find.byType(InsightsScreen)),
      );
      expect(find.text('charts-body'), findsOneWidget);
      await tester.tap(find.text(l.insightsTabsBudget).first);
      await tester.pumpAndSettle();
      expect(find.text('charts-body'), findsNothing);
      expect(find.text(l.budgetOverviewEdit), findsOneWidget);
      await tester.tap(find.text(l.insightsTabsBills).first);
      await tester.pumpAndSettle();
      expect(find.text('bills-body'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('deep link target: initial Budget segment', (tester) async {
    await initDateFormatting();
    await tester.pumpWidget(
      harness(
        const InsightsScreen(initial: InsightsSegment.budget),
        locale: const Locale('en'),
        overrides: [
          budgetScreenDataProvider.overrideWith(
            (ref) async => data([egpView()]),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(find.text('Edit budgets'), findsOneWidget);
  });
}
