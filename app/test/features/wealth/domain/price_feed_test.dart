// T-112: pure price/FX logic. Synthetic data only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/wealth/domain/price_feed.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final sar = Currency.of('SAR');
final kwd = Currency.of('KWD');
final jpy = Currency.of('JPY');

const int h = 3600000;
const int now = 1793527200000;

Map<String, Object?> block({
  String asOf = '2026-11-03T15:00:00Z',
  Object? stale = false,
  Object? gold,
  Object? fx,
}) => {
  'asOf': asOf,
  'stale': stale,
  'gold':
      gold ??
      [
        {'symbol': 'XAU24_G', 'currency': 'EGP', 'price': '4820.00'},
        {'symbol': 'XAU21_G', 'currency': 'EGP', 'price': '4217.5'},
        {'symbol': 'XAU24_G', 'currency': 'USD', 'price': '98.40'},
      ],
  'fx':
      fx ??
      {
        'base': 'USD',
        'rates': {'EGP': '48.9500', 'SAR': '3.7500', 'KWD': '0.3070'},
      },
};

void expectMalformed(Object? raw) => expect(
  () => parsePriceBlock(raw),
  throwsA(
    isA<PricesRejected>().having(
      (e) => e.code,
      'code',
      PricesRejected.malformed,
    ),
  ),
);

FxQuote q(Currency b, Currency c, int r, {int asOf = now}) =>
    FxQuote(base: b, quote: c, rateE9: r, asOfMs: asOf);

void main() {
  group('parsePriceBlock', () {
    test('parses the documented example exactly', () {
      final b = parsePriceBlock(block());
      expect(b.asOfMs, DateTime.utc(2026, 11, 3, 15).millisecondsSinceEpoch);
      expect(b.reportedStale, isFalse);
      expect(b.gold[0].price, Money(egp, 482000));
      expect(b.gold[1].price, Money(egp, 421750));
      expect(b.gold[2].price, Money(usd, 9840));
      expect(b.gold.every((g) => g.perUnit == 'g'), isTrue);
      expect(b.fxBase, usd);
      expect(b.fxRates[egp], 48950000000);
      expect(b.fxRates[sar], 3750000000);
      expect(b.fxRates[kwd], 307000000);
    });

    test('a price with extra trailing zeros is exact, extra digits reject', () {
      final ok = parsePriceBlock(
        block(
          gold: [
            {'symbol': 'XAU24_G', 'currency': 'EGP', 'price': '4820.000000'},
          ],
        ),
      );
      expect(ok.gold.single.price, Money(egp, 482000));
      expectMalformed(
        block(
          gold: [
            {'symbol': 'XAU24_G', 'currency': 'EGP', 'price': '4820.005'},
          ],
        ),
      );
    });

    test('exponent 0 and 3 currencies', () {
      final b = parsePriceBlock(
        block(
          gold: [
            {'symbol': 'XAU24_G', 'currency': 'JPY', 'price': '15000.0'},
            {'symbol': 'XAU24_G', 'currency': 'KWD', 'price': '30.125'},
          ],
        ),
      );
      expect(b.gold[0].price, Money(jpy, 15000));
      expect(b.gold[1].price, Money(kwd, 30125));
    });

    test('rejects malformed shapes and values', () {
      expectMalformed(null);
      expectMalformed('x');
      expectMalformed(block(asOf: '2026-11-03T15:00:00')); // not UTC
      expectMalformed(block(asOf: 'yesterday'));
      expectMalformed(block(stale: 'no'));
      expectMalformed(block(gold: <Object?>[]));
      expectMalformed(block(gold: 'x'));
      expectMalformed(
        block(
          gold: [
            {'symbol': 'xau', 'currency': 'EGP', 'price': '1'},
          ],
        ),
      );
      for (final p in [
        '0',
        '0.00',
        '-1',
        '1e3',
        '١٢٣',
        ' 5',
        '5,0',
        '',
        '1.',
      ]) {
        expectMalformed(
          block(
            gold: [
              {'symbol': 'XAU24_G', 'currency': 'EGP', 'price': p},
            ],
          ),
        );
      }
      expectMalformed(
        block(
          gold: [
            {'symbol': 'XAU24_G', 'currency': 'EGP', 'price': 4820.0},
          ],
        ),
      ); // JSON number, never a double
      expectMalformed(
        block(
          gold: [
            {'symbol': 'XAU24_G', 'currency': 'ZZZ', 'price': '1'},
          ],
        ),
      );
      expectMalformed(
        block(
          gold: [
            {'symbol': 'XAU24_G', 'currency': 'EGP', 'price': '1'},
            {'symbol': 'XAU24_G', 'currency': 'EGP', 'price': '2'},
          ],
        ),
      ); // duplicate
    });

    test('rejects bad FX', () {
      expectMalformed(block(fx: {'base': 'USD', 'rates': <String, Object?>{}}));
      expectMalformed(
        block(
          fx: {
            'base': 'USD',
            'rates': {'USD': '1'},
          },
        ),
      );
      for (final r in ['0', '0.0000000004', '48.95e0', '-3', '1.0000000001']) {
        expectMalformed(
          block(
            fx: {
              'base': 'USD',
              'rates': {'EGP': r},
            },
          ),
        );
      }
      // Above 2^53 - 1 in e9 units.
      expectMalformed(
        block(
          fx: {
            'base': 'USD',
            'rates': {'EGP': '9007199.254740992'},
          },
        ),
      );
      expectMalformed(
        block(
          fx: {
            'base': 'USD',
            'rates': {'EGP': 48.95},
          },
        ),
      );
    });

    test('9007199.254740991 is the largest accepted rate', () {
      final b = parsePriceBlock(
        block(
          fx: {
            'base': 'USD',
            'rates': {'EGP': '9007199.254740991'},
          },
        ),
      );
      expect(b.fxRates[egp], Money.maxMinor);
    });

    test('count caps', () {
      expectMalformed(
        block(
          gold: [
            for (var i = 0; i <= maxGoldQuotes; i++)
              {'symbol': 'S$i', 'currency': 'EGP', 'price': '1'},
          ],
        ),
      );
    });

    test('errors never echo the input', () {
      try {
        parsePriceBlock(block(asOf: 'SENTINEL'));
        fail('should throw');
      } on PricesRejected catch (e) {
        expect(e.toString(), isNot(contains('SENTINEL')));
      }
    });
  });

  group('staleness (EC-34)', () {
    test('exactly 24 h is fresh, one ms more is stale', () {
      expect(isPriceStale(asOfMs: now - 24 * h, nowMs: now), isFalse);
      expect(isPriceStale(asOfMs: now - 24 * h - 1, nowMs: now), isTrue);
    });
    test('backend-reported stale wins over a recent asOf', () {
      expect(
        isPriceStale(asOfMs: now - h, nowMs: now, reportedStale: true),
        isTrue,
      );
    });
    test('future asOf: small skew fine, large is unverifiable (stale)', () {
      expect(isPriceStale(asOfMs: now + 60000, nowMs: now), isFalse);
      expect(isPriceStale(asOfMs: now + 10 * 60000, nowMs: now), isTrue);
    });
  });

  group('resolvePrice', () {
    StoredQuote sq(PriceOrigin o, int minor, int asOf) => StoredQuote(
      symbol: 'XAU21_G',
      price: Money(egp, minor),
      perUnit: 'g',
      asOfMs: asOf,
      origin: o,
    );

    test('override beats backend price, marked manual, not stale', () {
      final r = resolvePrice(
        [
          sq(PriceOrigin.backend, 421750, now - 100 * h),
          sq(PriceOrigin.manual, 430000, now - 100 * h),
        ],
        nowMs: now,
        reportedStale: true,
      )!;
      expect(r.price, Money(egp, 430000));
      expect(r.isManual, isTrue);
      expect(r.stale, isFalse);
    });

    test('backend price older than 24 h is labelled stale, still returned', () {
      final r = resolvePrice(
        [sq(PriceOrigin.backend, 421750, now - 25 * h)],
        nowMs: now,
        reportedStale: false,
      )!;
      expect(r.price, Money(egp, 421750));
      expect(r.stale, isTrue);
      expect(r.isManual, isFalse);
    });

    test('fresh backend price is not stale; none gives null (EC-35)', () {
      final fresh = resolvePrice(
        [sq(PriceOrigin.backend, 1, now - h)],
        nowMs: now,
        reportedStale: false,
      )!;
      expect(fresh.stale, isFalse);
      expect(resolvePrice([], nowMs: now, reportedStale: false), isNull);
    });
  });

  group('convertApprox (the ≈ view)', () {
    // 1 USD = 48.95 EGP; 1 USD = 3.75 SAR; 1 USD = 0.307 KWD.
    final table = FxTable([
      q(usd, egp, 48950000000),
      q(usd, sar, 3750000000),
      q(usd, kwd, 307000000),
      q(usd, jpy, 150500000000),
    ], reportedStale: false);

    Approx ok(ApproxResult r) => r as Approx;

    test('direct: 10.00 USD = 489.50 EGP', () {
      final r = ok(table.convertApprox(Money(usd, 1000), egp, nowMs: now));
      expect(r.amount, Money(egp, 48950));
      expect(r.identity, isFalse);
      expect(r.stale, isFalse);
    });

    test('inverse: 489.50 EGP = 10.00 USD', () {
      final r = ok(table.convertApprox(Money(egp, 48950), usd, nowMs: now));
      expect(r.amount, Money(usd, 1000));
    });

    test('cross via USD: 100.00 EGP to SAR = 100 * 3.75 / 48.95', () {
      final r = ok(table.convertApprox(Money(egp, 10000), sar, nowMs: now));
      // 7.6608... SAR -> 7.66
      expect(r.amount, Money(sar, 766));
    });

    test('exponent differences: 1.000 KWD to EGP and 1 JPY-priced', () {
      // 1 KWD = 48.95 / 0.307 EGP = 159.4462... -> 159.45
      expect(
        ok(table.convertApprox(Money(kwd, 1000), egp, nowMs: now)).amount,
        Money(egp, 15945),
      );
      // 100 JPY to USD = 0.6644... -> 0.66
      expect(
        ok(table.convertApprox(Money(jpy, 100), usd, nowMs: now)).amount,
        Money(usd, 66),
      );
    });

    test('rounding is half-even, once', () {
      // 1 USD = 2.5 SAR style: 0.01 USD * 3.75 = 0.0375 -> 0.04
      expect(
        ok(table.convertApprox(Money(usd, 1), sar, nowMs: now)).amount,
        Money(sar, 4),
      );
      final half = FxTable([q(usd, sar, 2500000000)], reportedStale: false);
      // 0.01 USD * 2.5 = 0.025 -> tie -> even 0.02; 0.03 * 2.5 = 0.075 -> 0.08
      expect(
        ok(half.convertApprox(Money(usd, 1), sar, nowMs: now)).amount,
        Money(sar, 2),
      );
      expect(
        ok(half.convertApprox(Money(usd, 3), sar, nowMs: now)).amount,
        Money(sar, 8),
      );
    });

    test('zero and negative amounts', () {
      expect(
        ok(table.convertApprox(Money.zero(usd), egp, nowMs: now)).amount,
        Money.zero(egp),
      );
      expect(
        ok(table.convertApprox(Money(usd, -1000), egp, nowMs: now)).amount,
        Money(egp, -48950),
      );
    });

    test('same currency is identity, exact, never stale', () {
      final r = ok(
        FxTable(
          [],
          reportedStale: true,
        ).convertApprox(Money(egp, 5), egp, nowMs: now),
      );
      expect(r.identity, isTrue);
      expect(r.amount, Money(egp, 5));
      expect(r.stale, isFalse);
    });

    test('missing rate gives MissingRate, never a guess (EC-35)', () {
      final r = table.convertApprox(
        Money(egp, 100),
        Currency.of('GBP'),
        nowMs: now,
      );
      expect(r, isA<MissingRate>());
      expect(
        FxTable(
          [],
          reportedStale: false,
        ).convertApprox(Money(egp, 1), usd, nowMs: now),
        isA<MissingRate>(),
      );
    });

    test('stale label: old rate, reported stale, any stale leg', () {
      final old = FxTable([
        q(usd, egp, 48950000000, asOf: now - 25 * h),
        q(usd, sar, 3750000000),
      ], reportedStale: false);
      final r = ok(old.convertApprox(Money(egp, 100), sar, nowMs: now));
      expect(r.stale, isTrue);
      expect(r.asOfMs, now - 25 * h);
      final rep = FxTable([q(usd, egp, 48950000000)], reportedStale: true);
      expect(
        ok(rep.convertApprox(Money(usd, 100), egp, nowMs: now)).stale,
        isTrue,
      );
      expect(
        ok(table.convertApprox(Money(usd, 100), egp, nowMs: now)).stale,
        isFalse,
      );
    });

    test('overflow throws instead of wrapping', () {
      expect(
        () => table.convertApprox(Money(usd, Money.maxMinor), egp, nowMs: now),
        throwsA(isA<MoneyOverflow>()),
      );
    });
  });
}
