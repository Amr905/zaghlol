// D-67: amount formatting must go through the shared, maskable formatter.

class Money {}

abstract final class MoneyFormat {
  static String format(
    Money m, {
    required String languageCode,
    required Object digits,
    required bool hidden,
  }) => '';
}

class NumberFormat {
  NumberFormat(String p);
  NumberFormat.currency({String? symbol});
  String format(num n) => '';
}

class Screen {
  String shown(Money m, Object digits, bool hide) =>
      MoneyFormat.format(m, languageCode: 'en', digits: digits, hidden: hide);

  String alwaysShown(Money m, Object digits) =>
      // expect_lint: no_unmasked_amount
      MoneyFormat.format(m, languageCode: 'en', digits: digits, hidden: false);

  String viaNumberFormat(num n) =>
      // expect_lint: no_unmasked_amount
      NumberFormat('#,##0').format(n);

  String viaCurrency(num n) =>
      // expect_lint: no_unmasked_amount
      NumberFormat.currency(symbol: 'EGP').format(n);

  String fixed(num n) =>
      // expect_lint: no_unmasked_amount
      n.toStringAsFixed(2);

  String canonical(dynamic m) =>
      // expect_lint: no_unmasked_amount
      m.toCanonicalString();

  // A field the user types the number into is allowed with a reason.
  String prefill(dynamic m) =>
      // ignore: no_unmasked_amount - edit field, the user is typing the number
      m.toCanonicalString();
}
