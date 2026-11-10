// Outside the strict scope only amount-named declarations are checked, now
// including inferred doubles.

class AmountInferred {
  // expect_lint: no_double_money
  final amountA = 12.5;

  // expect_lint: no_double_money
  final minorB = 7 / 2;

  // expect_lint: no_double_money
  final amountC = double.parse('1');

  // Non-money doubles stay allowed here (UI geometry).
  final opacity = 0.5;
  final ratio = 3 / 4;
  final amountOk = 5;

  Object amountOf(int x) {
    // expect_lint: no_double_money
    return x * 1.5;
  }

  // expect_lint: no_double_money
  Object minorFrom(int x) => x / 2;

  int minorInt(int x) => (x / 2) ~/ 1;

  double scale(int x) => x / 3;
}
