// Chart series fills from 05-theme-2026 (chart.income / spend / saved) plus the
// category ramp used by the donut. Fills only: meaning is always carried by a
// text legend as well.

import 'dart:ui';

import '../../../../core/theme/z_tokens.dart';

abstract final class ZChartColors {
  static const income = Color(0xFF3E8A86);

  /// Neutral slate, not red: spending is ink/neutral by brand rule (explorer
  /// finding 17). Mid-tone so it reads on both the light and the dark card.
  static const spend = Color(0xFF6B7F75);
  static const saved = Color(0xFF7DB89A);

  /// Budget bar at or over the limit (a warning, not a spending amount).
  static const overLimit = Color(0xFFD9765F);

  /// First series colour: brandMint in True Black, [income] in light.
  static Color incomeOf(ZColors c) =>
      c.brightness == Brightness.dark ? c.brandMint : income;

  /// Donut ramp for the theme: the lead slice follows [incomeOf].
  static List<Color> rampOf(ZColors c) => [incomeOf(c), ...ramp.skip(1)];

  /// Donut ramp, largest slice first.
  static const ramp = [
    income,
    Color(0xFF9185D0),
    Color(0xFF5BA3C9),
    Color(0xFFE0A245),
    Color(0xFF6A8FD6),
    Color(0xFF7F85DC),
  ];
}
