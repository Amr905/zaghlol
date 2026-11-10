// Fixture: package zaghlol_domain is in the strict double scope too.

class DomainDoubleViolations {
  // expect_lint: no_double_money
  final double total = 0;

  // expect_lint: no_double_money
  num? price;
}
