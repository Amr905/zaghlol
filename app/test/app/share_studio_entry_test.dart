// T-117: the real S-73 opens through the app's screen opener, over the
// current screen, and closes back.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/app_screens.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_providers.dart';
import 'package:zaghlol/features/share_cards/presentation/share_studio_screen.dart';

void main() {
  for (final lang in ['ar', 'en']) {
    testWidgets('default opener shows the Share studio ($lang, 1.3x)', (
      t,
    ) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            chartsCurrenciesProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp(
            locale: Locale(lang),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ZaghlolTheme.light,
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Builder(
              builder: (c) => TextButton(
                onPressed: () => const AppScreens().shareStudio(c),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.byType(ShareStudioScreen), findsOneWidget);
      final l = AppLocalizations.of(t.element(find.byType(ShareStudioScreen)));
      expect(find.text(l.shareStudioEmptyTitle), findsOneWidget);
      await t.tap(find.byTooltip(l.shareStudioCloseA11y));
      await t.pumpAndSettle();
      expect(find.byType(ShareStudioScreen), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
