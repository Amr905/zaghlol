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
        'zaghlolText on zaghlolBg': (c.zaghlolText, c.zaghlolBg),
        'text on surfaceSunk': (c.text, c.surfaceSunk),
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

  group('True Black table (05-theme-2026 section 0, D-79)', () {
    const d = ZColors.dark;
    test('hex values match the table exactly', () {
      expect(d.bg, const Color(0xFF000000));
      expect(d.surface, const Color(0xFF141414));
      expect(d.surfaceAlt, const Color(0xFF222222));
      expect(d.surfaceSunk, const Color(0xFF0A0A0A));
      expect(d.outline, const Color(0xFF242424));
      expect(d.text, const Color(0xFFFFFFFF));
      expect(d.textMuted, const Color(0xFFA8A8A8));
      expect(d.primary, const Color(0xFFFFFFFF));
      expect(d.primaryContainer, const Color(0xFF2A2A2A));
      expect(d.onPrimary, const Color(0xFF000000));
      expect(d.brandMint, const Color(0xFF62E0AB));
      expect(d.incomeText, const Color(0xFF6EE7B7));
      expect(d.accentLight, const Color(0xFFFFCB8E));
      expect(d.accentDark, const Color(0xFFFFA94D));
      expect(d.onAccent, const Color(0xFF2E1600));
      expect(d.zaghlolBg, const Color(0xFF2A2018));
      expect(d.zaghlolText, const Color(0xFFFBE7D2));
      expect(d.warningBg, const Color(0xFF262113));
      expect(d.warningText, const Color(0xFFF2C76A));
      expect(d.dangerText, const Color(0xFFF2A08B));
    });

    test('documented contrast ratios', () {
      expect(contrastRatio(d.text, d.surface), closeTo(18.7, 0.4));
      expect(contrastRatio(d.textMuted, d.surface), closeTo(8.0, 0.4));
      expect(contrastRatio(d.primary, d.primaryContainer), closeTo(14.4, 0.4));
      expect(contrastRatio(d.onPrimary, d.primary), closeTo(21, 0.01));
      expect(contrastRatio(d.incomeText, d.surface), closeTo(12.0, 0.4));
      expect(contrastRatio(d.zaghlolText, d.zaghlolBg), closeTo(13.3, 0.4));
      expect(contrastRatio(d.warningText, d.warningBg), closeTo(10.4, 0.4));
      expect(contrastRatio(d.dangerText, d.surface), closeTo(8.6, 0.4));
    });

    test('no green text: every text token except income is neutral grey', () {
      for (final t in [d.text, d.textMuted, d.primary, d.heroNumber]) {
        expect(t.r, closeTo(t.g, 0.001));
        expect(t.g, closeTo(t.b, 0.001));
      }
    });

    test('no shadows: the shadow token is fully transparent', () {
      expect(d.shadow.a, 0);
    });

    test('flat hero: no gradient, mint progress fill', () {
      expect(d.heroFrom, d.heroTo);
      expect(d.heroFrom, d.surface);
      expect(d.progressFrom, d.brandMint);
    });
  });
}
