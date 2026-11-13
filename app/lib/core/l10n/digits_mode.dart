// T-023 / A-29, FR-L10N-03: which digits are shown, and normalizing typed
// digits back to ASCII (CLAUDE.md section 2 item 5).

import '../settings/settings_keys.dart';

/// The digits actually rendered.
enum DigitsMode {
  arabicIndic,
  western;

  /// A-29: `auto` is Arabic-Indic in Arabic and Western otherwise.
  static DigitsMode resolve(DigitsPref pref, String languageCode) =>
      switch (pref) {
        DigitsPref.arabicIndic => DigitsMode.arabicIndic,
        DigitsPref.western => DigitsMode.western,
        DigitsPref.auto =>
          languageCode == 'ar' ? DigitsMode.arabicIndic : DigitsMode.western,
      };

  /// Rewrites every ASCII digit of [text] (and `.` between digits is left to
  /// the caller) into this mode.
  String render(String text) {
    if (this == DigitsMode.western) {
      return text;
    }
    final out = StringBuffer();
    for (final unit in text.codeUnits) {
      out.writeCharCode(
        unit >= 0x30 && unit <= 0x39 ? unit - 0x30 + 0x0660 : unit,
      );
    }
    return out.toString();
  }
}

/// Input normalization: Arabic-Indic (U+0660..9) and Persian (U+06F0..9)
/// digits become ASCII, the Arabic decimal separator U+066B becomes `.`, the
/// Arabic thousands separator U+066C, the Arabic comma U+060C, spaces and
/// bidi/zero-width marks are dropped. Other characters pass through, so the
/// caller's strict parser still rejects garbage.
String normalizeDigits(String input) {
  final out = StringBuffer();
  for (final unit in input.runes) {
    if (unit >= 0x0660 && unit <= 0x0669) {
      out.writeCharCode(unit - 0x0660 + 0x30);
    } else if (unit >= 0x06F0 && unit <= 0x06F9) {
      out.writeCharCode(unit - 0x06F0 + 0x30);
    } else if (unit == 0x066B) {
      out.write('.');
    } else if (unit == 0x066C ||
        unit == 0x060C ||
        unit == 0x20 ||
        unit == 0xA0 ||
        unit == 0x200B ||
        unit == 0x200C ||
        unit == 0x200D ||
        unit == 0x200E ||
        unit == 0x200F ||
        (unit >= 0x2066 && unit <= 0x2069) ||
        unit == 0x061C) {
      continue;
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString();
}
