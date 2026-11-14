// T-082: the Asset entry of S-30 carries the Gold badge for Free users.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/ui/shell/add_sheet.dart';
import 'package:zaghlol/features/gold/application/gating.dart';

Future<ProviderContainer> _pump(
  WidgetTester t,
  Locale locale, {
  required bool gold,
  ValueChanged<AddAction>? onSelected,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  if (gold) {
    container
        .read(entitlementStateProvider.notifier)
        .applyVerified(verified: true, status: 'active');
  }
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ZaghlolTheme.light,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(body: AddSheet(onSelected: onSelected)),
      ),
    ),
  );
  await t.pumpAndSettle();
  return container;
}

void main() {
  for (final lang in ['ar', 'en']) {
    final locale = Locale(lang);
    testWidgets('Free: Asset shows the Gold badge, others do not ($lang)', (
      t,
    ) async {
      AddAction? picked;
      await _pump(t, locale, gold: false, onSelected: (a) => picked = a);
      final l = AppLocalizations.of(t.element(find.byType(AddSheet)));
      expect(find.text(l.commonGoldBadge), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text(l.homeQuickAddAsset),
            matching: find.byType(InkWell),
          ),
          matching: find.text(l.commonGoldBadge),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '${l.homeQuickAddAssetA11y}, ${l.commonGoldBadge}',
        ),
        findsOneWidget,
      );
      await t.tap(find.text(l.homeQuickAddAsset));
      expect(picked, AddAction.asset);
      expect(t.takeException(), isNull);
    });

    testWidgets('Gold: no badge ($lang)', (t) async {
      await _pump(t, locale, gold: true);
      final l = AppLocalizations.of(t.element(find.byType(AddSheet)));
      expect(find.text(l.commonGoldBadge), findsNothing);
      expect(find.bySemanticsLabel(l.homeQuickAddAssetA11y), findsOneWidget);
    });
  }
}
