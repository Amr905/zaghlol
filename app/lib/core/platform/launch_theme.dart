// T-224: hands the user's theme choice (light / dark / system, nothing else) to
// native code so the next cold start can paint the launch frame in the chosen
// theme. Native keeps it in a non-backup file (Android noBackupFilesDir, iOS
// Application Support, excluded per T-165). Never carries financial data.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
