// T-023: the app Locale and digits mode from the settings (T-020). The
// language setting `system` yields null so MaterialApp follows the device.

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_keys.dart';
import '../settings/settings_providers.dart';
import 'digits_mode.dart';

const supportedLanguageCodes = ['ar', 'en'];

/// null = follow the device.
final appLocaleProvider = Provider<Locale?>((ref) {
  final pref = ref.watch(languageProvider).value ?? LanguagePref.ar;
  return switch (pref) {
    LanguagePref.ar => const Locale('ar'),
    LanguagePref.en => const Locale('en'),
    LanguagePref.system => null,
  };
}, name: 'appLocaleProvider');

/// Resolves [DigitsPref] for the language actually shown ([languageCode]).
final digitsModeProvider = Provider.family<DigitsMode, String>((
  ref,
  languageCode,
) {
  final pref = ref.watch(digitsProvider).value ?? DigitsPref.auto;
  return DigitsMode.resolve(pref, languageCode);
}, name: 'digitsModeProvider');
