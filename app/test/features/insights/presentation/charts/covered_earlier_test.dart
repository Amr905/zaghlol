import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_bodies.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'charts_test_support.dart';

CategoryDonut _donut(int coveredMinor) => CategoryDonut(
  total: egpM(1000),
  slices: [
    CategorySlice(
      categoryId: 'x',
      amount: egpM(1000),
      shareBp: 10000,
      count: 2,
    ),
  ],
  coveredEarlier: coveredMinor == 0 ? null : Money(egp, coveredMinor),
);

void main() {
  for (final locale in const [Locale('en'), Locale('ar', 'EG')]) {
    final tag = locale.languageCode;
    for (final large in [true, false]) {
      final kind = large ? 'rows' : 'legend';
      Widget body(CategoryDonut d) => large
          ? DonutRows(donut: d, nameOf: (_) => 'Food', categories: const [])
          : DonutBody(donut: d, nameOf: (_) => 'Food');
      Future<void> pump(WidgetTester t, CategoryDonut d) async {
        await t.binding.setSurfaceSize(const Size(390, 1200));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(
          harness(
            body(d),
            locale: locale,
            scale: 1.3,
            overrides: chartOverrides(),
          ),
        );
        await t.pumpAndSettle();
      }

      testWidgets('$tag $kind: note shown when coveredEarlier > 0', (t) async {
        await pump(t, _donut(30000));
        final l = AppLocalizations.of(t.element(find.byType(Scaffold).first));
        expect(
          find.textContaining(l.insightsCoveredEarlier('').trim()),
          findsOneWidget,
        );
      });

      testWidgets('$tag $kind: note hidden when coveredEarlier is 0', (
        t,
      ) async {
        await pump(t, _donut(0));
        final l = AppLocalizations.of(t.element(find.byType(Scaffold).first));
        expect(
          find.textContaining(l.insightsCoveredEarlier('').trim()),
          findsNothing,
        );
      });
    }
  }

  // T-231: the legend row (name, amount, share) scales its amount down
  // instead of overflowing a 320dp screen (found on the emulator).
  for (final locale in const [Locale('en'), Locale('ar', 'EG')]) {
    testWidgets('${locale.languageCode} legend: wide amounts do not overflow '
        'at 320dp', (t) async {
      await t.binding.setSurfaceSize(const Size(320, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final donut = CategoryDonut(
        total: egpM(296296294),
        slices: [
          for (var i = 0; i < 3; i++)
            CategorySlice(
              categoryId: 'c$i',
              amount: egpM(98765432 - i),
              shareBp: 3333,
              count: 2,
            ),
        ],
      );
      await t.pumpWidget(
        harness(
          DonutBody(donut: donut, nameOf: (_) => 'Food and drinks'),
          locale: locale,
          overrides: chartOverrides(),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('donut-row-0')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
