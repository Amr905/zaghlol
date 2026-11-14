// T-174: guideline + 1.3x checks for screens that had none (S-05 lock,
// Insights shell, S-23 edit budgets). ar/en x light/dark x scale 1.0/1.3.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/budget/presentation/edit_budgets_screen.dart';
import 'package:zaghlol/features/insights/presentation/insights_screen.dart';
import 'package:zaghlol/features/security/data/device_security_providers.dart';
import 'package:zaghlol/features/security/presentation/lock_screen.dart';

import '../features/budget/presentation/budget_test_support.dart';
import '../support/a11y_guidelines.dart';
import '../support/golden_matrix.dart';

void main() {
  for (final v in [...goldenVariants, ...goldenVariantsScaled]) {
    testWidgets('lock screen a11y ${v.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        harness(
          LockScreen(
            outcome: AuthOutcome.lockedOut,
            busy: false,
            onUnlock: () {},
          ),
          locale: v.locale,
          dark: v.dark,
          scale: v.textScale,
        ),
      );
      await t.pump();
      await expectA11yGuidelines(t);
    });

    testWidgets('insights shell a11y ${v.name}', (t) async {
      await initDateFormatting();
      await t.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        harness(
          InsightsScreen(
            chartsBuilder: (_) => const Text('charts-body'),
            billsBuilder: (_) => const Text('bills-body'),
          ),
          locale: v.locale,
          dark: v.dark,
          scale: v.textScale,
          overrides: [
            budgetScreenDataProvider.overrideWith(
              (ref) async => data([egpView()]),
            ),
          ],
        ),
      );
      await t.pump();
      await expectA11yGuidelines(t);
    });

    testWidgets('edit budgets a11y ${v.name}', (t) async {
      await initDateFormatting();
      await t.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        harness(
          EditBudgetsScreen(initialCurrency: egp),
          locale: v.locale,
          dark: v.dark,
          scale: v.textScale,
          overrides: [
            categoryRowsProvider.overrideWith((ref) async => const []),
            cycleBudgetRowsProvider.overrideWith((ref) async => const []),
          ],
        ),
      );
      await t.pumpAndSettle();
      await expectA11yGuidelines(t);
    });
  }
}
