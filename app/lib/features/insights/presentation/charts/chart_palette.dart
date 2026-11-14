// Chart series fills from 05-theme-2026 (chart.income / spend / saved) plus the
// category ramp used by the donut. Fills only: meaning is always carried by a
// text legend as well.

import 'dart:ui';

abstract final class ZChartColors {
  static const income = Color(0xFF3E8A86);
  static const spend = Color(0xFFD9765F);
  static const saved = Color(0xFF7DB89A);

  /// Donut ramp, largest slice first.
  static const ramp = [
    income,
    Color(0xFF9185D0),
    spend,
    Color(0xFFE0A245),
    Color(0xFF6A8FD6),
    Color(0xFF7F85DC),
  ];
}
