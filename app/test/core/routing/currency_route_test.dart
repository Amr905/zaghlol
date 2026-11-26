// T-279: `/home/currency/:iso` reaches the currency builder with the code.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/routing/app_router.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/routing/app_routes.dart';

void main() {
  test('helper builds the location', () {
    expect(AppRoutes.currencyViewFor('USD'), '/home/currency/USD');
  });

  testWidgets('the route passes the ISO code', (tester) async {
    final router = buildAppRouter(
      TabRoots(currencyView: (c, iso) => Text('view:$iso')),
      initialLocation: AppRoutes.currencyViewFor('USD'),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: ZaghlolTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('view:USD'), findsOneWidget);
  });
}
