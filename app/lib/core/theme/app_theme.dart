import 'package:flutter/material.dart';

import 'z_tokens.dart';

/// Builds the Material themes from the Mint Fresh / Jade Night tokens.
abstract final class ZaghlolTheme {
  static ThemeData get light => _build(ZColors.light);
  static ThemeData get dark => _build(ZColors.dark);

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
    return base.copyWith(
      textTheme: textTheme,
      dividerColor: c.outline,
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ZRadius.card),
          ),
        ),
      ),
    );
  }
}
