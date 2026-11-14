// PO 2026-11-14: light theme and Arabic until the user picks otherwise.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/theme_mode_provider.dart';
import 'package:zaghlol/main.dart';

ProviderContainer _container({LanguagePref? lang, ThemePref? theme}) {
  final c = ProviderContainer(
    overrides: [
      languageProvider.overrideWith(
        (ref) => Stream.value(lang ?? LanguagePref.ar),
      ),
      themeProvider.overrideWith(
        (ref) => Stream.value(theme ?? ThemePref.light),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Keeps both settings streams listened to and lets them emit.
Future<void> _load(ProviderContainer c) async {
  c.listen(languageProvider, (_, _) {});
  c.listen(themeProvider, (_, _) {});
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('fresh settings give light and Arabic', () async {
    final c = _container();
    await _load(c);
    expect(c.read(appThemeModeProvider), ThemeMode.light);
    expect(c.read(appLocaleProvider), const Locale('ar'));
  });

  test('before the settings load the defaults still hold', () {
    final c = ProviderContainer(
      overrides: [
        languageProvider.overrideWith((ref) => const Stream.empty()),
        themeProvider.overrideWith((ref) => const Stream.empty()),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(appThemeModeProvider), ThemeMode.light);
    expect(c.read(appLocaleProvider), const Locale('ar'));
  });

  test('an explicit choice wins', () async {
    final c = _container(lang: LanguagePref.en, theme: ThemePref.dark);
    await _load(c);
    expect(c.read(appThemeModeProvider), ThemeMode.dark);
    expect(c.read(appLocaleProvider), const Locale('en'));
  });

  test('system stays an option', () async {
    final c = _container(lang: LanguagePref.system, theme: ThemePref.system);
    await _load(c);
    expect(c.read(appThemeModeProvider), ThemeMode.system);
    expect(c.read(appLocaleProvider), isNull);
  });

  testWidgets('a dark English device still opens light and Arabic', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockEnabledProvider.overrideWith((ref) => Stream.value(false)),
        ],
        child: const ZaghlolApp(),
      ),
    );
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(NavigationBar));
    expect(Theme.of(ctx).brightness, Brightness.light);
    expect(Localizations.localeOf(ctx).languageCode, 'ar');
    expect(Directionality.of(ctx), TextDirection.rtl);
  });
}
