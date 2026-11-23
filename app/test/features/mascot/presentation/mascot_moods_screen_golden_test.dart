@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/mascot/presentation/mascot_moods_screen.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';

import '../../../support/golden_matrix.dart';

void main() {
  for (final v in goldenVariants) {
    testWidgets('mascot_moods ${v.name}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          // No Rive in widget tests: the still pose stands in for the artboard.
          overrides: [
            zaghlolArtboardProvider.overrideWithValue(
              (context, moment, talk, size) => Image.asset(
                ZaghlolAvatar.stillAsset,
                width: size,
                height: size,
                fit: BoxFit.contain,
              ),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: v.locale,
            theme: ZaghlolTheme.light,
            darkTheme: ZaghlolTheme.dark,
            themeMode: v.dark ? ThemeMode.dark : ThemeMode.light,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const MascotMoodsScreen(),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.pump();
        await precacheImage(
          const AssetImage(ZaghlolAvatar.stillAsset),
          tester.element(find.byType(MascotMoodsScreen)),
        );
      });
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../goldens/mascot_moods_${v.name}.png'),
      );
    });
  }
}
