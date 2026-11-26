// T-272: when an unexplained balance rise is worth one question. Synthetic.

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final kwd = Currency.of('KWD');
final jpy = Currency.of('JPY');

void main() {
  test('PO case: EGP 1,000 -> 30,200 after 500 of card spending: rise '
      '29,700', () {
    expect(
      unexplainedBalanceRise(
        previous: Money(egp, 100000),
        countedEffectMinor: -50000,
        reported: Money(egp, 3020000),
      ),
      Money(egp, 2970000),
    );
  });

  test('explained by counted transactions: none', () {
    expect(
      unexplainedBalanceRise(
        previous: Money(egp, 100000),
        countedEffectMinor: 2970000,
        reported: Money(egp, 3070000),
      ),
      isNull,
    );
  });

  test('threshold is 500 major units in each exponent', () {
    expect(balanceJumpMinMinor(egp), 50000);
    expect(balanceJumpMinMinor(kwd), 500000);
    expect(balanceJumpMinMinor(jpy), 500);
    expect(
      unexplainedBalanceRise(
        previous: Money(egp, 0),
        countedEffectMinor: 0,
        reported: Money(egp, 49999),
      ),
      isNull,
    );
    expect(
      unexplainedBalanceRise(
        previous: Money(egp, 0),
        countedEffectMinor: 0,
        reported: Money(egp, 50000),
      ),
      Money(egp, 50000),
    );
  });

  test('a fall, a negative balance or another currency: none', () {
    expect(
      unexplainedBalanceRise(
        previous: Money(egp, 100000),
        countedEffectMinor: 0,
        reported: Money(egp, -100000),
      ),
      isNull,
    );
    expect(
      unexplainedBalanceRise(
        previous: Money(usd, 0),
        countedEffectMinor: 0,
        reported: Money(egp, 9000000),
      ),
      isNull,
    );
  });
}
