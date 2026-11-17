import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_palette.dart';

void main() {
  test('spending is neutral, not red (brand rule)', () {
    final hsl = HSLColor.fromColor(ZChartColors.spend);
    expect(hsl.saturation, lessThan(0.2));
    expect(ZChartColors.ramp, isNot(contains(ZChartColors.overLimit)));
  });
}
