import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/features/zakah/presentation/zakah_screen.dart';

void main() {
  test('Z3 the 2.5% rate follows the digit mode, sign included', () {
    expect(zakahRateLabel(DigitsMode.arabicIndic), '٢٫٥٪');
    expect(zakahRateLabel(DigitsMode.western), '2.5%');
  });
}
