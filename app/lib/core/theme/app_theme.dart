import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'z_tokens.dart';

/// Builds the Material themes from the Mint Fresh / True Black tokens.
abstract final class ZaghlolTheme {
  // Cached per platform: the switch theme holds closures, so two builds never
  // compare equal and MaterialApp would keep animating between "different"
  // themes. ThemeData captures the target platform, so the cache is keyed on it.
  static ThemeData get light => _cached(ZColors.light, dark: false);
  static ThemeData get dark => _cached(ZColors.dark, dark: true);

  static final Map<(bool, TargetPlatform), ThemeData> _cache = {};

  static ThemeData _cached(ZColors c, {required bool dark}) =>
      _cache.putIfAbsent((dark, defaultTargetPlatform), () => _build(c));

  static ThemeData _build(ZColors c) {
    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryContainer,
      onPrimaryContainer: c.onPrimaryContainer,
      secondary: c.accent,
      onSecondary: c.onAccent,
      error: c.dangerText,
      onError: c.dangerBg,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.textMuted,
      surfaceContainerHighest: c.surfaceAlt,
      outline: c.outline,
      outlineVariant: c.outline,
      shadow: c.shadow,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      fontFamily: kZFontFamily,
      fontFamilyFallback: kZFontFallback,
      extensions: <ThemeExtension<dynamic>>[c],
    );
    final textTheme = base.textTheme
        .copyWith(
          displayMedium: ZType.display,
          headlineMedium: ZType.headline,
          titleLarge: ZType.title,
          titleMedium: ZType.titleSmall,
          bodyLarge: ZType.body,
          bodyMedium: ZType.bodySmall,
          labelLarge: ZType.label,
          labelSmall: ZType.caption,
        )
        .apply(bodyColor: c.text, displayColor: c.text);
    final fill = c.brightness == Brightness.dark ? c.brandMint : c.primary;
    return base.copyWith(
      textTheme: textTheme,
      dividerColor: c.outline,
      // brandMint is fill-only: dark (True Black) swaps the white primary for
      // mint on progress and switches; light keeps the primary.
      progressIndicatorTheme: ProgressIndicatorThemeData(color: fill),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? fill : null,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onPrimary : null,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: ZType.title.copyWith(color: c.text),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        showDragHandle: true,
        dragHandleColor: c.primaryContainer,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ZRadius.hero),
          ),
        ),
      ),
    );
  }
}
