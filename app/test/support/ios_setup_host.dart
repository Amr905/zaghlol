import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/capture/application/ios_shortcut_providers.dart';
import 'package:zaghlol/features/capture/domain/ios_shortcut_checker.dart';
import 'package:zaghlol/features/onboarding/presentation/ios_setup.dart';

const int kDayMs = 24 * 60 * 60 * 1000;
const int kNow = 100 * kDayMs;

/// A report built with the real derivation. Null ms = never ran.
ShortcutSetupReport report({int? message, int? wallet, int? baseline}) =>
    deriveShortcutSetupReport(
      nowMs: kNow,
      lastMessageIntentAtMs: message,
      lastWalletIntentAtMs: wallet,
      baselineAtMs: baseline,
    );

/// Both automations ran an hour ago.
ShortcutSetupReport healthy() =>
    report(message: kNow - 3600000, wallet: kNow - 3600000, baseline: 0);

Widget iosSetupHost(
  String lang, {
  FutureOr<ShortcutSetupReport?> Function()? reportFn,
  Future<void> Function()? install,
  double scale = 1,
  bool dark = false,
  VoidCallback? onDone,
  void Function(String)? onSkipped,
  VoidCallback? onSay,
  VoidCallback? onType,
  VoidCallback? onOnlineBanks,
  Key? rootKey,
}) => ProviderScope(
  overrides: [
    shortcutSetupReportProvider.overrideWith(
      (ref) async => (reportFn ?? healthy)(),
    ),
    installShortcutProvider.overrideWithValue(install ?? () async {}),
    languageProvider.overrideWith(
      (ref) => Stream.value(lang == 'ar' ? LanguagePref.ar : LanguagePref.en),
    ),
    digitsProvider.overrideWith((ref) => Stream.value(DigitsPref.auto)),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ZaghlolTheme.light,
    darkTheme: ZaghlolTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    locale: Locale(lang),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: RepaintBoundary(key: rootKey, child: child!),
    ),
    home: IosSetupScreen(
      onDone: onDone ?? () {},
      onSkipped: onSkipped,
      onSay: onSay ?? () {},
      onType: onType ?? () {},
      onOnlineBanks: onOnlineBanks ?? () {},
    ),
  ),
);
