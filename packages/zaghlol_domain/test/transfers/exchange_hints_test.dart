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

  group('FU-366 per-currency threshold', () {
    test('no rate or EGP: 500 major units as before', () {
      expect(balanceJumpMinMinor(jpy), 500);
      expect(balanceJumpMinMinor(kwd, egpPerUnitE9: null), 500000);
      expect(balanceJumpMinMinor(egp, egpPerUnitE9: 1000000000), 50000);
      expect(balanceJumpMinMinor(usd, egpPerUnitE9: 0), 50000);
    });

    test('KWD at 160 EGP: 500 EGP = 3.125 KWD', () {
      expect(balanceJumpMinMinor(kwd, egpPerUnitE9: 160000000000), 3125);
    });

    test('JPY at 0.33 EGP: 500 EGP = 1516 JPY (rounded up)', () {
      expect(balanceJumpMinMinor(jpy, egpPerUnitE9: 330000000), 1516);
    });

    test('USD at 50 EGP: 10 USD', () {
      expect(balanceJumpMinMinor(usd, egpPerUnitE9: 50000000000), 1000);
    });

    test('a huge rate never goes under the floor', () {
      expect(
        balanceJumpMinMinor(usd, egpPerUnitE9: 9000000000000000),
        balanceJumpFloorMinor(usd),
      );
      expect(balanceJumpFloorMinor(jpy), 100);
      expect(balanceJumpFloorMinor(kwd), 1000);
    });

    test('rise of 4 KWD asked with a rate, not without', () {
      Money? rise(int? rate) => unexplainedBalanceRise(
        previous: Money(kwd, 10000),
        countedEffectMinor: 0,
        reported: Money(kwd, 14000),
        egpPerUnitE9: rate,
      );
      expect(rise(160000000000), Money(kwd, 4000));
      expect(rise(null), isNull);
    });
  });
}
