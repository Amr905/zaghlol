// T-280: the Home "≈ money in" figure. Synthetic data only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/wealth/domain/income_approx.dart';
import 'package:zaghlol/features/wealth/domain/price_feed.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final kwd = Currency.of('KWD');
final jpy = Currency.of('JPY');

const int now = 1793527200000;
const int h = 3600000;

FxQuote q(Currency b, Currency c, int rateE9, int asOf) =>
    FxQuote(base: b, quote: c, rateE9: rateE9, asOfMs: asOf);

IncomeApprox build(
  List<IncomeApproxInput> inputs,
  List<FxQuote> rates, {
  Currency? target,
}) => buildIncomeApprox(
  target: target ?? egp,
  inputs: inputs,
  rates: FxTable(rates, reportedStale: false),
  nowMs: now,
);

IncomeApproxLine line(IncomeApprox a) => a as IncomeApproxLine;

IncomeApproxInput inp(Currency c, int moneyIn, int out, {int? bank}) =>
    IncomeApproxInput(
      moneyIn: Money(c, moneyIn),
      exchangedOut: Money(c, out),
      bankRateE9: bank,
    );

void main() {
  final usdEgp = q(usd, egp, 49600000000, now - h);

  test('PO story: 29,700 + 400 x 49.60 = 49,540 EGP in minor units', () {
    final a = line(
      build(
        [
          // EGP money in = the 29,700 received by the exchange (no salary).
          inp(egp, 2970000, 0),
          // USD: salary 1,000 in, 600 exchanged out.
          inp(usd, 100000, 60000, bank: 49500000000),
        ],
        [usdEgp],
      ),
    );
    expect(a.total, Money(egp, 4954000));
    expect(a.rows.single.held, Money(usd, 40000));
    expect(a.rows.single.heldInTarget, Money(egp, 1984000));
    expect(a.rows.single.dailyRatePerUnit, Money(egp, 4960));
    expect(a.usesBankRate, isTrue);
    expect(a.usesDailyRate, isTrue);
    expect(a.stale, isFalse);
  });

  test('negative proof: the exchanged part is never counted twice', () {
    // Converting the whole USD money in (not only the held part) would give
    // 29,700 + 1,000 x 49.60 = 79,300.
    final a = line(
      build([inp(egp, 2970000, 0), inp(usd, 100000, 60000)], [usdEgp]),
    );
    expect(a.total, isNot(Money(egp, 7930000)));
    expect(a.total, Money(egp, 4954000));
  });

  test('negative proof: target exchanged out is not counted twice', () {
    final r = q(usd, egp, 50000000000, now - h);
    final a = line(
      build([inp(egp, 5000000, 1000000), inp(usd, 20000, 0)], [r]),
    );
    expect(a.total.minor, 5000000);
  });

  test('everything exchanged: no daily rate needed, total is EGP money in', () {
    final a = line(
      build([
        inp(egp, 2970000, 0),
        inp(usd, 60000, 60000, bank: 49500000000),
      ], const []),
    );
    expect(a.total, Money(egp, 2970000));
    expect(a.rows.single.held.isZero, isTrue);
    expect(a.usesDailyRate, isFalse);
    expect(a.usesBankRate, isTrue);
  });

  test('exchanged out above money in floors the held part at zero', () {
    final a = line(build([inp(egp, 100, 0), inp(usd, 1000, 5000)], const []));
    expect(a.rows.single.held, Money(usd, 0));
    expect(a.total, Money(egp, 100));
  });

  test('negative proof: a missing rate gives no line, never a partial', () {
    final a = build(
      [inp(egp, 2970000, 0), inp(usd, 100000, 0), inp(kwd, 5000, 0)],
      [usdEgp], // no KWD rate
    );
    expect(a, isA<IncomeApproxNone>());
  });

  test('EGP only gives no line', () {
    expect(build([inp(egp, 100, 0)], [usdEgp]), isA<IncomeApproxNone>());
    expect(build(const [], [usdEgp]), isA<IncomeApproxNone>());
  });

  test('a stale rate is flagged and its date is the oldest used', () {
    final old = q(usd, egp, 49600000000, now - 30 * h);
    final a = line(build([inp(egp, 0, 0), inp(usd, 100, 0)], [old]));
    expect(a.stale, isTrue);
    expect(a.rateAsOfMs, now - 30 * h);
  });

  test('KWD (3 decimals): 10.500 KWD at 160.250 EGP', () {
    final r = q(kwd, egp, 160250000000, now - h);
    final a = line(build([inp(kwd, 10500, 0)], [r]));
    // 10.5 x 160.25 = 1682.625 -> 1682.62 (half-even to 2 decimals).
    expect(a.total, Money(egp, 168262));
    expect(a.rows.single.dailyRatePerUnit, Money(egp, 16025));
  });

  test('JPY (0 decimals): 10,000 JPY at 0.33 EGP', () {
    final r = q(jpy, egp, 330000000, now - h);
    final a = line(build([inp(jpy, 10000, 0)], [r]));
    expect(a.total, Money(egp, 330000)); // 3,300.00 EGP
    expect(a.rows.single.dailyRatePerUnit, Money(egp, 33));
  });

  test('a foreign target works the other way (EGP held into USD)', () {
    final r = q(egp, usd, 20000000, now - h); // 1 EGP = 0.02 USD
    final a = line(
      build([inp(usd, 100, 0), inp(egp, 5000, 0)], [r], target: usd),
    );
    expect(a.total, Money(usd, 200));
  });

  test('overflow gives no line', () {
    final r = q(usd, egp, Money.maxMinor, now - h);
    final a = build([inp(usd, Money.maxMinor, 0)], [r]);
    expect(a, isA<IncomeApproxNone>());
  });

  test('Q2 trigger: two active currencies, once', () {
    expect(
      shouldAutoEnableApprox(activeCurrencies: 2, alreadyDone: false),
      isTrue,
    );
    expect(
      shouldAutoEnableApprox(activeCurrencies: 1, alreadyDone: false),
      isFalse,
    );
    expect(
      shouldAutoEnableApprox(activeCurrencies: 3, alreadyDone: true),
      isFalse,
    );
  });
}
