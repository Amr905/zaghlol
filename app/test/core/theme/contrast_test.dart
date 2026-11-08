import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/theme/contrast.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';

void main() {
  test('contrast helper matches WCAG reference values', () {
    expect(
      contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.01),
    );
    expect(
      contrastRatio(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)),
      closeTo(1, 0.001),
    );
    // Documented in 05-theme-2026 section 0: ink on surface is 15.3.
    expect(
      contrastRatio(ZColors.light.text, ZColors.light.surface),
      closeTo(15.3, 0.1),
    );
  });

  for (final entry in {'light': ZColors.light, 'dark': ZColors.dark}.entries) {
    final c = entry.value;
    group('WCAG AA text pairs (${entry.key})', () {
      final pairs = <String, (Color, Color)>{
        'text on bg': (c.text, c.bg),
        'text on surface': (c.text, c.surface),
        'text on surfaceAlt': (c.text, c.surfaceAlt),
        'textMuted on bg': (c.textMuted, c.bg),
        'textMuted on surface': (c.textMuted, c.surface),
        'textMuted on surfaceAlt': (c.textMuted, c.surfaceAlt),
        'primary on bg': (c.primary, c.bg),
        'primary on surface': (c.primary, c.surface),
        'primary on surfaceAlt': (c.primary, c.surfaceAlt),
        'primary on primaryContainer': (c.primary, c.primaryContainer),
        'onPrimaryContainer on primaryContainer': (
          c.onPrimaryContainer,
          c.primaryContainer,
        ),
        'textMuted on primaryContainer': (c.textMuted, c.primaryContainer),
        'onPrimary on primary': (c.onPrimary, c.primary),
        'onAccent on accent': (c.onAccent, c.accent),
        'onAccent on accent gradient start': (c.onAccent, c.accentLight),
        'onAccent on accent gradient end': (c.onAccent, c.accentDark),
        'incomeText on bg': (c.incomeText, c.bg),
        'incomeText on surface': (c.incomeText, c.surface),
        'incomeText on incomeBg': (c.incomeText, c.incomeBg),
        'text on zaghlolBg': (c.text, c.zaghlolBg),
        'textMuted on zaghlolBg': (c.textMuted, c.zaghlolBg),
        'warningText on warningBg': (c.warningText, c.warningBg),
        'dangerText on dangerBg': (c.dangerText, c.dangerBg),
        'dangerBg on dangerText (destructive button)': (
          c.dangerBg,
          c.dangerText,
        ),
        'heroNumber on surface': (c.heroNumber, c.surface),
      };
      pairs.forEach((name, pair) {
        test(name, () {
          expect(
            contrastRatio(pair.$1, pair.$2),
            greaterThanOrEqualTo(4.5),
            reason: '$name must meet WCAG AA (4.5:1)',
          );
        });
      });
    });
  }
}
