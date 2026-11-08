import 'package:flutter/material.dart';

/// Spacing scale (04-design-system 2.5): 4 dp grid.
abstract final class ZSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Screen side padding.
  static const double screen = 16;

  /// Minimum interactive target (WCAG / Material).
  static const double minTarget = 48;
}

/// Corner radii. Mint Fresh refinements (05-theme-2026 4): 24 for cards and
/// lists, 28 for the hero; pills are fully rounded.
abstract final class ZRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double card = 24;
  static const double hero = 28;
  static const double pill = 999;
}

/// Motion durations (04-design-system 2.9).
abstract final class ZMotion {
  static const Duration micro = Duration(milliseconds: 100);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration sheet = Duration(milliseconds: 300);
  static const Curve curve = Curves.easeInOut;
}

/// Font family bundled by the app. Falls back to the system font when the
/// family is not available (see [kZFontFallback]).
const String kZFontFamily = 'IBMPlexSansArabic';
const List<String> kZFontFallback = ['Roboto', 'sans-serif'];

/// Type scale (04-design-system 2.2). Sizes are in logical px (scaled by the
/// OS text scale); line height is given as a multiple of the size.
abstract final class ZType {
  static TextStyle _s(double size, FontWeight w, double lineHeight) =>
      TextStyle(
        fontFamily: kZFontFamily,
        fontFamilyFallback: kZFontFallback,
        fontSize: size,
        fontWeight: w,
        height: lineHeight / size,
        // Tabular figures so amounts align in lists.
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static final TextStyle display = _s(32, FontWeight.w700, 40);
  static final TextStyle headline = _s(24, FontWeight.w700, 32);
  static final TextStyle title = _s(20, FontWeight.w600, 28);
  static final TextStyle titleSmall = _s(16, FontWeight.w600, 24);
  static final TextStyle body = _s(16, FontWeight.w400, 24);
  static final TextStyle bodySmall = _s(14, FontWeight.w400, 20);
  static final TextStyle label = _s(14, FontWeight.w500, 20);
  static final TextStyle caption = _s(12, FontWeight.w500, 16);
}

/// Colour tokens from 05-theme-2026 section 0 (Mint Fresh / Jade Night),
/// exposed as a [ThemeExtension] so widgets read them through
/// `ZColors.of(context)`.
@immutable
class ZColors extends ThemeExtension<ZColors> {
  const ZColors({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.outline,
    required this.text,
    required this.textMuted,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.accent,
    required this.accentLight,
    required this.accentDark,
    required this.onAccent,
    required this.incomeText,
    required this.incomeBg,
    required this.zaghlolBg,
    required this.warningText,
    required this.warningBg,
    required this.dangerText,
    required this.dangerBg,
    required this.heroNumber,
    required this.shadow,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color outline;
  final Color text;
  final Color textMuted;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color accent;
  final Color accentLight;
  final Color accentDark;
  final Color onAccent;
  final Color incomeText;
  final Color incomeBg;
  final Color zaghlolBg;
  final Color warningText;
  final Color warningBg;
  final Color dangerText;
  final Color dangerBg;
  final Color heroNumber;
  final Color shadow;

  /// Mint Fresh (light).
  static const ZColors light = ZColors(
    brightness: Brightness.light,
    bg: Color(0xFFF3FBF7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE5F5EC),
    outline: Color(0xFFDDF0E5),
    text: Color(0xFF0F2A20),
    textMuted: Color(0xFF4D695C),
    primary: Color(0xFF0F7A55),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD7F3E5),
    onPrimaryContainer: Color(0xFF0F2A20),
    accent: Color(0xFFFFB86B),
    accentLight: Color(0xFFFFCB8E),
    accentDark: Color(0xFFFFA94D),
    onAccent: Color(0xFF2E1600),
    incomeText: Color(0xFF0F7A55),
    incomeBg: Color(0xFFD7F3E5),
    zaghlolBg: Color(0xFFFFF3E6),
    warningText: Color(0xFF7A5200),
    warningBg: Color(0xFFFFF4E2),
    dangerText: Color(0xFF9E3F27),
    dangerBg: Color(0xFFF8E6DF),
    heroNumber: Color(0xFF0F5E43),
    shadow: Color(0x0D000000),
  );

  /// Jade Night (dark).
  static const ZColors dark = ZColors(
    brightness: Brightness.dark,
    bg: Color(0xFF08130F),
    surface: Color(0xFF10211A),
    surfaceAlt: Color(0xFF163026),
    outline: Color(0xFF1D3A2E),
    text: Color(0xFFE6F4EE),
    textMuted: Color(0xFF93AFA3),
    primary: Color(0xFF34D399),
    onPrimary: Color(0xFF08130F),
    primaryContainer: Color(0xFF163F31),
    onPrimaryContainer: Color(0xFFE6F4EE),
    accent: Color(0xFFFFB86B),
    accentLight: Color(0xFF6EE7B7),
    accentDark: Color(0xFF34D399),
    onAccent: Color(0xFF2E1600),
    incomeText: Color(0xFF6EE7B7),
    incomeBg: Color(0xFF163F31),
    zaghlolBg: Color(0xFF2B2419),
    warningText: Color(0xFFF5C26B),
    warningBg: Color(0xFF33280F),
    dangerText: Color(0xFFF2A08B),
    dangerBg: Color(0xFF3B1F1A),
    heroNumber: Color(0xFF6EE7B7),
    shadow: Color(0x33000000),
  );

  /// The tokens of the nearest [Theme]. Throws in debug if the theme was not
  /// built with `ZaghlolTheme`.
  static ZColors of(BuildContext context) {
    final ext = Theme.of(context).extension<ZColors>();
    assert(ext != null, 'ZColors missing: build the theme with ZaghlolTheme');
    return ext ?? light;
  }

  @override
  ZColors copyWith({Color? primary}) => ZColors(
    brightness: brightness,
    bg: bg,
    surface: surface,
    surfaceAlt: surfaceAlt,
    outline: outline,
    text: text,
    textMuted: textMuted,
    primary: primary ?? this.primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    accent: accent,
    accentLight: accentLight,
    accentDark: accentDark,
    onAccent: onAccent,
    incomeText: incomeText,
    incomeBg: incomeBg,
    zaghlolBg: zaghlolBg,
    warningText: warningText,
    warningBg: warningBg,
    dangerText: dangerText,
    dangerBg: dangerBg,
    heroNumber: heroNumber,
    shadow: shadow,
  );

  @override
  ZColors lerp(ThemeExtension<ZColors>? other, double t) =>
      other is ZColors ? (t < 0.5 ? this : other) : this;
}
