// T-224: hands the user's theme choice (light / dark / system, nothing else) to
// native code so the next cold start can paint the launch frame in the chosen
// theme. Native keeps it in a non-backup file (Android noBackupFilesDir, iOS
// Application Support, excluded per T-165). Never carries financial data.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_mode_provider.dart';

const String _systemIsDarkMethod = 'systemIsDark';

const MethodChannel launchThemeChannel = MethodChannel('zaghlol/launch_theme');

/// The wire value for [mode]: exactly `light`, `dark` or `system`.
String launchThemeWireValue(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};

/// Writes the choice to native storage. Never throws; a missing host (tests,
/// headless engine) does nothing.
final launchThemeWriterProvider = Provider<Future<void> Function(ThemeMode)>(
  (ref) => (mode) async {
    try {
      await launchThemeChannel.invokeMethod<void>(
        'set',
        launchThemeWireValue(mode),
      );
    } on PlatformException {
      // Best effort: the launch frame then follows the system theme.
    } on MissingPluginException {
      // No host on this platform.
    }
  },
  name: 'launchThemeWriterProvider',
);

/// The phone's real dark mode as native reports it (Android only; null until
/// known or where the host does not answer). The activity's own night bits
/// are forced by the stored choice, so Flutter's platformBrightness cannot be
/// trusted for "system" there. Native pushes `systemIsDark` on every change.
final systemIsDarkProvider = NotifierProvider<SystemIsDark, bool?>(
  SystemIsDark.new,
  name: 'systemIsDarkProvider',
);

class SystemIsDark extends Notifier<bool?> {
  @override
  bool? build() {
    launchThemeChannel.setMethodCallHandler((call) async {
      if (call.method == _systemIsDarkMethod && call.arguments is bool) {
        state = call.arguments as bool;
      }
      return null;
    });
    ref.onDispose(() => launchThemeChannel.setMethodCallHandler(null));
    Future<void>(() async {
      try {
        final v = await launchThemeChannel.invokeMethod<bool>(
          _systemIsDarkMethod,
        );
        if (v != null && ref.mounted) state = v;
      } on PlatformException {
        // Follow platformBrightness.
      } on MissingPluginException {
        // No host (iOS, tests).
      }
    });
    return null;
  }
}

/// The ThemeMode to give MaterialApp: the choice, except that "system" becomes
/// an explicit light/dark from the phone's real mode when native reports it.
final effectiveThemeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref.watch(appThemeModeProvider);
  if (mode != ThemeMode.system) return mode;
  final dark = ref.watch(systemIsDarkProvider);
  if (dark == null) return mode;
  return dark ? ThemeMode.dark : ThemeMode.light;
}, name: 'effectiveThemeModeProvider');
