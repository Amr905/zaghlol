// The shared formatter itself is exempt from no_unmasked_amount.

class Money {
  String toCanonicalString() => '';
}

class NumberFormat {
  NumberFormat(String p);
  String format(num n) => '';
}

abstract final class MoneyFormat {
  static String format(Money m, {required bool hidden}) =>
      hidden ? '****' : NumberFormat('#').format(1) + m.toCanonicalString();

  static String again(Money m) => format(m, hidden: false);
}
