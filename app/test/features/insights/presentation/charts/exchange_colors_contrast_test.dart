import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_palette.dart';

double _lum(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double ratio(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  test('FU-386: exchange colours are not the accent and reach 3:1', () {
    const accent = Color(0xFFFFB86B);
    for (final c in [ZChartColors.exchangeIn, ZChartColors.exchangeOut]) {
      expect(c, isNot(accent));
      expect(ratio(c, const Color(0xFFFFFFFF)), greaterThanOrEqualTo(3));
      expect(ratio(c, const Color(0xFF141414)), greaterThanOrEqualTo(3));
    }
    expect(ZChartColors.exchangeIn, isNot(ZChartColors.exchangeOut));
  });
}
