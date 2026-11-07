// Fixture for no_double_money. Every violation is announced by expect_lint.

class MoneyViolations {
  // expect_lint: no_double_money
  double ratio = 1;

  // expect_lint: no_double_money
  num? scale;

  // expect_lint: no_double_money
  final List<double> history = const [];

  // expect_lint: no_double_money
  double halve(int minor) => minor / 2;

  int scaled(int minor) {
    // expect_lint: no_double_money
    return minor * 2.5 ~/ 1;
  }
}
