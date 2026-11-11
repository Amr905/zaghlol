// T-020: Riverpod access to the settings. [settingProvider] makes one
// reactive provider per key; declare it once, at top level.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../db/app_database_providers.dart';
import '../db/daos/settings_dao.dart';
import 'setting_key.dart';
import 'settings_keys.dart';
import 'settings_repository.dart';

final settingsRepositoryProvider = FutureProvider<SettingsRepository>(
  (ref) async => SettingsRepository(
    SettingsDao(await ref.watch(appDatabaseProvider.future)),
  ),
  name: 'settingsRepositoryProvider',
);

/// A provider of [key]'s value: its default while unset, then every change.
StreamProvider<T> settingProvider<T>(SettingKey<T> key) =>
    StreamProvider<T>((ref) async* {
      final repo = await ref.watch(settingsRepositoryProvider.future);
      yield* repo.watch(key);
    }, name: 'setting.${key.name}');

final languageProvider = settingProvider(Settings.language);
final digitsProvider = settingProvider(Settings.digits);
final themeProvider = settingProvider(Settings.theme);
final paydayDayProvider = settingProvider(Settings.paydayDay);
final incomeTargetProvider = settingProvider<Money?>(Settings.incomeTarget);
final primaryCurrencyProvider = settingProvider(Settings.primaryCurrency);
final approxViewEnabledProvider = settingProvider(Settings.approxViewEnabled);
final approxViewTargetProvider = settingProvider(Settings.approxViewTarget);
final quietHoursEnabledProvider = settingProvider(Settings.quietHoursEnabled);
final appLockEnabledProvider = settingProvider(Settings.appLockEnabled);
final appLockTimeoutSProvider = settingProvider(Settings.appLockTimeoutS);
final contributionOptInProvider = settingProvider(Settings.contributionOptIn);
final scanDepthMonthsProvider = settingProvider(Settings.scanDepthMonths);
final setupProgressProvider = settingProvider(Settings.setupProgress);
