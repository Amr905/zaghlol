// PO 2026-11-14: the app is light until the user picks another theme.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_keys.dart';
import '../settings/settings_providers.dart';

final appThemeModeProvider = Provider<ThemeMode>((ref) {
  final pref = ref.watch(themeProvider).value ?? ThemePref.light;
  return switch (pref) {
    ThemePref.light => ThemeMode.light,
    ThemePref.dark => ThemeMode.dark,
    ThemePref.system => ThemeMode.system,
  };
}, name: 'appThemeModeProvider');
