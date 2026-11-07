// Outside money/: only declarations named like amounts are checked.

class AmountNames {
  const AmountNames(this.amountMinor, this.minorUnits, this.opacity);

  // expect_lint: no_double_money
  final double amountMinor;

  // expect_lint: no_double_money
  final num? minorUnits;

  // Not a money name: double is fine outside money/.
  final double opacity;

  // expect_lint: no_double_money
  double get amount => 0;

  double get ratio => opacity * 2;

  // expect_lint: no_double_money
  static int convert(double amountInput) => amountInput.toInt();
}
