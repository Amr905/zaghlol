@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/onboarding/presentation/welcome.dart';

import '../../../support/golden_matrix.dart';

void main() {
  for (final v in [...goldenVariants, ...goldenVariantsScaled]) {
    testWidgets('welcome golden ${v.name}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ZaghlolTheme.light,
            darkTheme: ZaghlolTheme.dark,
            themeMode: v.dark ? ThemeMode.dark : ThemeMode.light,
            locale: v.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(v.textScale)),
              child: RepaintBoundary(
                key: const ValueKey('golden-root'),
                child: child!,
              ),
            ),
            home: WelcomeScreen(
              onStart: () {},
              onRestore: () {},
              onPrivacy: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('golden-root')),
        matchesGoldenFile('welcome_${v.name}.png'),
      );
    });
  }
}
