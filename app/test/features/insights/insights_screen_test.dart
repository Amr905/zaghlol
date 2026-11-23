// T-101: the Insights shell segments.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/home/application/card_filter.dart';
import 'package:zaghlol/features/home/presentation/home_widgets.dart'
    show homeAccountsProvider;
import 'package:zaghlol_domain/zaghlol_domain.dart';
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

  // T-231: a single-card filter with a long name must not overflow the row
  // above the title on a 320dp screen (found on the emulator).
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    testWidgets('long card name in the filter chip does not overflow '
        '${locale.languageCode}', (tester) async {
      await initDateFormatting();
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final account = Account(
        id: 'a1',
        kind: AccountKind.values.first,
        label: 'National Bank of Egypt Platinum Debit Card Account',
        defaultCurrency: Currency.of('EGP'),
        isHidden: false,
        isDefaultCash: false,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        last4: '1234',
      );
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
            homeAccountsProvider.overrideWith((ref) async => [account]),
            cardFilterProvider.overrideWith(() => _OneCard('a1')),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}

class _OneCard extends CardFilterNotifier {
  _OneCard(this.id);
  final String id;
  @override
  Set<String> build() => {id};
}
