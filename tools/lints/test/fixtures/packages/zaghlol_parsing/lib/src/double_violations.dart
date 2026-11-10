// Fixture for no_double_money inside package zaghlol_parsing (not a money/
// directory): any double use is reported.

class DoubleViolations {
  int a(String s) {
    // expect_lint: no_double_money
    final v = double.parse(s);
    return v.toInt();
  }

  // expect_lint: no_double_money
  double? b(String s) => double.tryParse(s);

  Object c(String s) {
    // expect_lint: no_double_money
    return num.parse(s);
  }

  Object d(String s) {
    // expect_lint: no_double_money
    return num.tryParse(s) ?? 0;
  }

  int e(int minor) {
    // expect_lint: no_double_money
    final d = minor.toDouble();
    return d.round();
  }

  Object f() {
    // expect_lint: no_double_money
    final x = 12.5;
    // expect_lint: no_double_money
    final r = 7 / 2;
    var n = 10;
    // expect_lint: no_double_money
    n /= 4;
    return [x, r, n];
  }
}
