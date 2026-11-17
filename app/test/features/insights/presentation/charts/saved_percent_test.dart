// FU-169b: the saved percent is integer math, rounded half away from zero.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_bodies.dart';

void main() {
  test('rounds half away from zero without doubles', () {
    expect(CashFlowBody.savedPercent(1, 8), 13); // 12.5
    expect(CashFlowBody.savedPercent(-1, 8), -13);
    expect(CashFlowBody.savedPercent(38, 100), 38);
    expect(CashFlowBody.savedPercent(1, 3), 33);
  });
}
