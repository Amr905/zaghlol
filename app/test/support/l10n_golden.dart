import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';

import 'golden_matrix.dart';

/// Localized, themed host with a golden root for one variant.
Widget l10nGoldenHost(GoldenVariant v, Widget child) => ProviderScope(
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: v.locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ZaghlolTheme.light,
    darkTheme: ZaghlolTheme.dark,
    themeMode: v.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(v.textScale)),
      child: app!,
    ),
    home: Scaffold(
      body: RepaintBoundary(
        key: const ValueKey('golden-root'),
        child: Builder(
          builder: (context) => ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: child,
          ),
        ),
      ),
    ),
  ),
);

void l10nGoldenMatrix(
  String name,
  Widget Function(AppLocalizations l) build, {
  Size size = const Size(390, 480),
}) {
  for (final v in goldenVariants) {
    testWidgets('$name golden ${v.name}', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        l10nGoldenHost(
          v,
          Builder(builder: (c) => build(AppLocalizations.of(c))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byKey(const ValueKey('golden-root')),
        matchesGoldenFile('goldens/${name}_${v.name}.png'),
      );
    });
  }
}
