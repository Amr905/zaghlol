import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/core/theme/app_theme.dart';

/// Builds the app around [home] with an in-memory database behind the
/// settings repository, plus [overrides] for the reads.
class SettingsHarness {
  SettingsHarness() {
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    repo = SettingsRepository(SettingsDao(db));
  }

  late final AppDatabase db;
  late final SettingsRepository repo;

  List<Override> _base({
    int payday = 1,
    bool appLock = false,
    bool approx = false,
  }) => [
    appDatabaseProvider.overrideWith((ref) async => db),
    settingsRepositoryProvider.overrideWith((ref) async => repo),
    // Reads come from fixed streams: drift's watch streams leave a pending
    // timer behind in widget tests. Writes still go to the real repository.
    languageProvider.overrideWith((ref) => Stream.value(LanguagePref.system)),
    digitsProvider.overrideWith((ref) => Stream.value(DigitsPref.auto)),
    themeProvider.overrideWith((ref) => Stream.value(ThemePref.system)),
    paydayDayProvider.overrideWith((ref) => Stream.value(payday)),
    incomeTargetProvider.overrideWith((ref) => Stream.value(null)),
    primaryCurrencyProvider.overrideWith(
      (ref) => Stream.value(Currency.of('EGP')),
    ),
    approxViewEnabledProvider.overrideWith((ref) => Stream.value(approx)),
    approxViewTargetProvider.overrideWith(
      (ref) => Stream.value(Currency.of('EGP')),
    ),
    appLockEnabledProvider.overrideWith((ref) => Stream.value(appLock)),
    appLockTimeoutSProvider.overrideWith((ref) => Stream.value(60)),
    contributionOptInProvider.overrideWith((ref) => Stream.value(false)),
  ];

  Widget app(
    Widget home, {
    Locale locale = const Locale('en'),
    bool dark = false,
    double scale = 1.0,
    int payday = 1,
    bool appLock = false,
    bool approx = false,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        ..._base(payday: payday, appLock: appLock, approx: approx),
        ...overrides,
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ZaghlolTheme.light,
        darkTheme: ZaghlolTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    );
  }
}

Future<void> settle(WidgetTester tester, {double height = 3000}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}
