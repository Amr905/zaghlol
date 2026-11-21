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

  /// End padding of tab scrollers so the last row clears the raised Add
  /// (C-02, 40 dp). The bar itself is not overlaid: content ends above it.
  static const double fabClearance = 40;
  static const double fabSize = 62;

  /// Bottom bar (C-02): content height, Add raise above the bar, ring, tab
  /// indicator pill.
  static const double barHeight = 64;
  static const double addRaise = 34;
  static const double addRing = 5;
  static const double pillWidth = 56;
  static const double pillHeight = 30;

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
const List<String> kZFontFallback = ['Roboto', 'NotoColorEmoji', 'sans-serif'];

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

/// Colour tokens from 05-theme-2026 section 0 (Mint Fresh / True Black),
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
    required this.heroFrom,
    required this.heroTo,
    required this.progressFrom,
    required this.progressTo,
    required this.tintViolet,
    required this.tintBlue,
    required this.tintTeal,
    required this.brandMint,
    required this.surfaceSunk,
    required this.zaghlolText,
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

  /// Hero card gradient: [heroFrom] at the top end, [heroTo] at the bottom
  /// start (mockups 03 / 21), and the progress bar gradient.
  final Color heroFrom;
  final Color heroTo;
  final Color progressFrom;
  final Color progressTo;

  /// Icon-tile / avatar tints from the mockups (settings rows, bank
  /// avatars): not semantic, always paired with a label.
  final Color tintViolet;
  final Color tintBlue;
  final Color tintTeal;

  /// Fill-only mint (progress, chart series, switches on). Never text.
  final Color brandMint;

  /// KPI strip inside the hero (True Black); [surfaceAlt] in light.
  final Color surfaceSunk;

  /// Text on [zaghlolBg] (Captain Zaghlol's banners and bubbles).
  final Color zaghlolText;

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
    heroFrom: Color(0xFFB9EBD3),
    heroTo: Color(0xFFE4F8D8),
    progressFrom: Color(0xFF0F7A55),
    progressTo: Color(0xFF34B284),
    tintViolet: Color(0xFF9585CF),
    tintBlue: Color(0xFF6A8FD8),
    tintTeal: Color(0xFF3F8C86),
    brandMint: Color(0xFF34B284),
    surfaceSunk: Color(0xFFE5F5EC),
    zaghlolText: Color(0xFF0F2A20),
  );

  /// True Black (dark, D-79; 05-theme-2026 section 0). White text, no green
  /// text, no shadows: elevation is a surface step plus an outline.
  static const ZColors dark = ZColors(
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    surface: Color(0xFF141414),
    surfaceAlt: Color(0xFF222222),
    outline: Color(0xFF242424),
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xFFA8A8A8),
    primary: Color(0xFFFFFFFF),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF2A2A2A),
    onPrimaryContainer: Color(0xFFFFFFFF),
    accent: Color(0xFFFFB86B),
    accentLight: Color(0xFFFFCB8E),
    accentDark: Color(0xFFFFA94D),
    onAccent: Color(0xFF2E1600),
    incomeText: Color(0xFF6EE7B7),
    incomeBg: Color(0xFF12261E),
    zaghlolBg: Color(0xFF2A2018),
    warningText: Color(0xFFF2C76A),
    warningBg: Color(0xFF262113),
    dangerText: Color(0xFFF2A08B),
    dangerBg: Color(0xFF2A1713),
    heroNumber: Color(0xFFFFFFFF),
    // No shadows in dark.
    shadow: Color(0x00000000),
    // Flat hero: the surface colour, no gradient.
    heroFrom: Color(0xFF141414),
    heroTo: Color(0xFF141414),
    progressFrom: Color(0xFF62E0AB),
    progressTo: Color(0xFF62E0AB),
    tintViolet: Color(0xFFB4A8E6),
    tintBlue: Color(0xFF8FB0EE),
    tintTeal: Color(0xFF6CC4BD),
    brandMint: Color(0xFF62E0AB),
    surfaceSunk: Color(0xFF0A0A0A),
    zaghlolText: Color(0xFFFBE7D2),
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
    heroFrom: heroFrom,
    heroTo: heroTo,
    progressFrom: progressFrom,
    progressTo: progressTo,
    tintViolet: tintViolet,
    tintBlue: tintBlue,
    tintTeal: tintTeal,
    brandMint: brandMint,
    surfaceSunk: surfaceSunk,
    zaghlolText: zaghlolText,
  );

  @override
  ZColors lerp(ThemeExtension<ZColors>? other, double t) {
    if (other is! ZColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ZColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      outline: l(outline, other.outline),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      primaryContainer: l(primaryContainer, other.primaryContainer),
      onPrimaryContainer: l(onPrimaryContainer, other.onPrimaryContainer),
      accent: l(accent, other.accent),
      accentLight: l(accentLight, other.accentLight),
      accentDark: l(accentDark, other.accentDark),
      onAccent: l(onAccent, other.onAccent),
      incomeText: l(incomeText, other.incomeText),
      incomeBg: l(incomeBg, other.incomeBg),
      zaghlolBg: l(zaghlolBg, other.zaghlolBg),
      warningText: l(warningText, other.warningText),
      warningBg: l(warningBg, other.warningBg),
      dangerText: l(dangerText, other.dangerText),
      dangerBg: l(dangerBg, other.dangerBg),
      heroNumber: l(heroNumber, other.heroNumber),
      shadow: l(shadow, other.shadow),
      heroFrom: l(heroFrom, other.heroFrom),
      heroTo: l(heroTo, other.heroTo),
      progressFrom: l(progressFrom, other.progressFrom),
      progressTo: l(progressTo, other.progressTo),
      tintViolet: l(tintViolet, other.tintViolet),
      tintBlue: l(tintBlue, other.tintBlue),
      tintTeal: l(tintTeal, other.tintTeal),
      brandMint: l(brandMint, other.brandMint),
      surfaceSunk: l(surfaceSunk, other.surfaceSunk),
      zaghlolText: l(zaghlolText, other.zaghlolText),
    );
  }
}
