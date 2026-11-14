// T-101: S-23 flows (save, validation, unsaved dialog) in ar and en.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/budget/presentation/budget_edit_draft.dart';
import 'package:zaghlol/features/budget/presentation/budget_providers_ui.dart';
import 'package:zaghlol/features/budget/presentation/budget_saver.dart';
import 'package:zaghlol/features/budget/presentation/edit_budgets_screen.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'budget_test_support.dart';

CategoryRow cat(String id, String en, String ar, int sort) => CategoryRow(
  id: id,
  systemCode: null,
  parentId: null,
  nameAr: ar,
  nameEn: en,
  icon: 'x',
  color: '#000000',
  bucket: 'needs',
  isCustom: 0,
  isArchived: 0,
  sort: sort,
);

BudgetRow budget(String id, String? cat, int minor) => BudgetRow(
  id: id,
  categoryId: cat,
  currency: 'EGP',
  limitMinor: minor,
  period: 'cycle',
  rollover: 0,
  thresholds: '[80,100]',
  createdAt: 0,
);

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    group('S-23 ${locale.languageCode}', () {
      final saved = <(Currency, BudgetValidated, bool)>[];

      Future<AppLocalizations> pump(
        WidgetTester tester, {
        bool failSave = false,
        double scale = 1.0,
      }) async {
        saved.clear();
        await tester.binding.setSurfaceSize(const Size(390, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          harness(
            Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EditBudgetsScreen(initialCurrency: egp),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
            locale: locale,
            scale: scale,
            overrides: [
              categoryRowsProvider.overrideWith(
                (ref) async => [
                  cat('groceries', 'Groceries', 'بقالة', 1),
                  cat('dining', 'Dining', 'مطاعم', 2),
                ],
              ),
              cycleBudgetRowsProvider.overrideWith(
                (ref) async => [budget('b1', 'groceries', 700000)],
              ),
              budgetSaverProvider.overrideWith(
                (ref) async => (Currency c, BudgetValidated v, bool r) async {
                  if (failSave) throw StateError('x');
                  saved.add((c, v, r));
                },
              ),
            ],
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        return AppLocalizations.of(
          tester.element(find.byType(EditBudgetsScreen)),
        );
      }

      testWidgets('prefills, saves integer minor units, closes', (
        tester,
      ) async {
        final l = await pump(tester);
        expect(find.text('7000.00'), findsOneWidget);
        final dining = find.widgetWithText(
          TextField,
          locale.languageCode == 'ar' ? 'مطاعم' : 'Dining',
        );
        await tester.enterText(dining, '٤٠٠٠');
        await tester.tap(find.text(l.commonActionSave));
        await tester.pumpAndSettle();
        expect(saved, hasLength(1));
        final (c, v, rollover) = saved.single;
        expect(c, egp);
        expect(v.limits['dining']!.minor, 400000);
        expect(v.limits['groceries']!.minor, 700000);
        expect(rollover, isFalse);
        expect(find.byType(EditBudgetsScreen), findsNothing);
      });

      testWidgets('invalid threshold blocks save with the copy-deck error', (
        tester,
      ) async {
        final l = await pump(tester);
        final first = find.widgetWithText(TextField, l.budgetEditAlertFirst);
        await tester.enterText(first, '120');
        await tester.tap(find.text(l.commonActionSave));
        await tester.pumpAndSettle();
        expect(saved, isEmpty);
        expect(find.text(l.budgetEditErrorOrder), findsOneWidget);
      });

      testWidgets('the field refuses a minus sign', (tester) async {
        await pump(tester);
        final dining = find.widgetWithText(
          TextField,
          locale.languageCode == 'ar' ? 'مطاعم' : 'Dining',
        );
        await tester.enterText(dining, '-15');
        expect(tester.widget<TextField>(dining).controller!.text, '15');
      });

      testWidgets('save failure shows an inline error and keeps input', (
        tester,
      ) async {
        final l = await pump(tester, failSave: true);
        await tester.tap(find.text(l.commonActionSave));
        await tester.pumpAndSettle();
        expect(find.text(l.commonErrorSaveFailed), findsOneWidget);
        expect(find.byType(EditBudgetsScreen), findsOneWidget);
        expect(find.text('7000.00'), findsOneWidget);
      });

      testWidgets('unsaved changes ask before closing', (tester) async {
        final l = await pump(tester);
        await tester.enterText(
          find.widgetWithText(
            TextField,
            locale.languageCode == 'ar' ? 'مطاعم' : 'Dining',
          ),
          '10',
        );
        await tester.tap(find.byTooltip(l.commonActionClose));
        await tester.pumpAndSettle();
        expect(find.text(l.commonDiscardTitle), findsOneWidget);
        await tester.tap(find.text(l.commonDiscardKeep));
        await tester.pumpAndSettle();
        expect(find.byType(EditBudgetsScreen), findsOneWidget);
        await tester.tap(find.byTooltip(l.commonActionClose));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.commonDiscardConfirm));
        await tester.pumpAndSettle();
        expect(find.byType(EditBudgetsScreen), findsNothing);
      });

      testWidgets('text scale 1.3 does not overflow', (tester) async {
        await pump(tester, scale: 1.3);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
