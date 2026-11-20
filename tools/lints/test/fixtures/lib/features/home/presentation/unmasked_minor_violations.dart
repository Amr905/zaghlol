// D-67: minor units must not be printed outside the shared formatter.

class Row {
  int get netMinor => 0;
  int get quantityMilli => 0;
  int get inMilliseconds => 0;
  int get minor => 0;
}

class Screen {
  String interpolated(Row r) =>
      // expect_lint: no_unmasked_amount
      '${r.minor} EGP';

  String interpolatedMilli(Row r) =>
      // expect_lint: no_unmasked_amount
      'grams: ${r.quantityMilli}';

  String arithmetic(Row r) =>
      // expect_lint: no_unmasked_amount
      '${r.netMinor ~/ 1000}';

  String viaToString(Row r) =>
      // expect_lint: no_unmasked_amount
      r.netMinor.toString();

  String parenthesizedFalse(dynamic m) =>
      // expect_lint: no_unmasked_amount
      MoneyFormat.format(m, hidden: (false));

  // Time is not money.
  String ttl(Row r) => '${r.inMilliseconds}';

  // A dedupe key is allowed with a reason.
  String key(Row r) =>
      // ignore: no_unmasked_amount - duplicate-detection key, never shown
      '${r.minor}';
}

abstract final class MoneyFormat {
  static String format(Object? m, {required bool hidden}) => '';
}
