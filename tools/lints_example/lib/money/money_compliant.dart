// Compliant: integer minor units only. No lint may fire here.

class CompliantMoney {
  const CompliantMoney(this.minorUnits, this.currency);

  final int minorUnits;
  final String currency;

  int get amount => minorUnits;

  CompliantMoney add(CompliantMoney other) {
    if (other.currency != currency) {
      throw ArgumentError('currency mismatch');
    }
    return CompliantMoney(minorUnits + other.minorUnits, currency);
  }

  BigInt get wide => BigInt.from(minorUnits);
}

class NegativeControl {
  double x = 1;
}
