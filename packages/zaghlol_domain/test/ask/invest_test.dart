import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
Money e(String s) => Money.parse(s, egp);
final now = DateTime.utc(2026, 11, 26, 12);
final fresh = now.subtract(const Duration(hours: 1));

GoldQuote g(String price, {int karat = 21, DateTime? at, Currency? c}) =>
    GoldQuote(
      karat: karat,
      pricePerGram: Money.parse(price, c ?? egp),
      asOf: at ?? fresh,
    );

final th = InvestThresholds.defaults();

InvestBand band(String s, GoldQuote? q, [InvestThresholds? t]) =>
    investBand(e(s), q, t ?? th);

InvestIllustration ill(
  Money s, {
  List<GoldQuote>? gold,
  InvestFxQuote? fx,
  int months = 12,
  InvestThresholds? t,
}) => illustrate(
  saved: s,
  prices: InvestPrices(
    gold: gold ?? [g('4000.00')],
    usdEgp: fx ?? InvestFxQuote(egpPerUsd: e('50.00'), asOf: fresh),
    certificateRateBp: 2000,
  ),
  instruments: InvestInstrument.values.toSet(),
  horizonMonths: months,
  now: now,
  thresholds: t ?? th,
);

void main() {
  group('AC1 worked example', () {
    test('1.12 g, USD 90.00, certificate EGP 900.00', () {
      final r = ill(e('4500.00'));
      expect(r.band, InvestBand.gold);
      final gold = r.rows.whereType<GoldRow>().single;
      expect(gold.centigrams, 112);
      expect(gold.karat, 21);
      final u = r.rows.whereType<UsdRow>().single;
      expect(u.amount, Money.parse('90.00', usd));
      expect(u.approximate, isTrue);
      final c = r.rows.whereType<CertificateRow>().single;
      expect(c.payout, e('900.00'));
    });
    test('24K row too, when a 24K price exists', () {
      final r = ill(
        e('4500.00'),
        gold: [g('4000.00'), g('4600.00', karat: 24)],
      );
      expect(r.rows.whereType<GoldRow>().map((x) => x.karat), [21, 24]);
    });
  });

  group('AC2 bands, G = 1000.00', () {
    final q = g('4000.00'); // 0.25 g = 1000.00
    test('S <= 0', () {
      expect(band('0.00', q), InvestBand.nothingSaved);
      expect(band('-5.00', q), InvestBand.nothingSaved);
    });
    test('100.00 small, 100.01 stocks', () {
      expect(band('100.00', q), InvestBand.small);
      expect(band('100.01', q), InvestBand.stocks);
      expect(band('0.01', q), InvestBand.small);
    });
    test('999.99 stocks, 1000.00 gold', () {
      expect(band('999.99', q), InvestBand.stocks);
      expect(band('1000.00', q), InvestBand.gold);
      expect(band('1000.01', q), InvestBand.gold);
    });
    test('FU-407 minEgp must be EGP', () {
      expect(
        () => InvestThresholds(minEgp: Money.parse('100.00', usd)),
        throwsArgumentError,
      );
    });
    test('configurable minimum', () {
      final t = InvestThresholds(minEgp: e('200.00'));
      expect(band('150.00', q, t), InvestBand.small);
      expect(band('200.01', q, t), InvestBand.stocks);
    });
    test('configurable gold weight', () {
      final t = InvestThresholds(minEgp: e('100.00'), goldMinCentigrams: 50);
      expect(band('1999.99', q, t), InvestBand.stocks);
      expect(band('2000.00', q, t), InvestBand.gold);
    });
    test('stocks band: no gold row, USD + certificate kept, flag set', () {
      final r = ill(e('500.00'));
      expect(r.stocksInGeneral, isTrue);
      expect(r.rows.whereType<GoldRow>(), isEmpty);
      expect(r.rows.whereType<NoPriceRow>(), isEmpty);
      expect(r.rows.whereType<UsdRow>(), hasLength(1));
      expect(r.rows.whereType<CertificateRow>(), hasLength(1));
    });
    test('small and nothingSaved: no rows', () {
      for (final s in ['100.00', '0.00']) {
        final r = ill(e(s));
        expect(r.rows, isEmpty);
        expect(r.stocksInGeneral, isFalse);
      }
    });
    test('no gold price ever: neither stocks nor gold, USD/cert kept', () {
      final r = ill(e('500.00'), gold: const []);
      expect(r.band, InvestBand.goldUnknown);
      expect(r.stocksInGeneral, isFalse);
      expect(r.rows.whereType<GoldRow>(), isEmpty);
      expect(r.rows.whereType<UsdRow>(), hasLength(1));
      expect(r.rows.whereType<CertificateRow>(), hasLength(1));
    });
    test('only a 24K price: G unknown (karat mismatch)', () {
      expect(band('500.00', g('4600.00', karat: 24)), InvestBand.goldUnknown);
    });
  });

  group('AC3 non-EGP', () {
    test('USD source: gold in USD, no band, USD as is, no certificate', () {
      final s = Money.parse('50.00', usd);
      final r = ill(s, gold: [g('80.00', c: usd)]);
      expect(r.band, InvestBand.gold);
      expect(
        r.rows.whereType<GoldRow>().single.centigrams,
        62,
      ); // 0.625 -> even
      final u = r.rows.whereType<UsdRow>().single;
      expect(u.amount, s);
      expect(u.approximate, isFalse);
      expect(r.rows.whereType<CertificateRow>(), isEmpty);
    });
    test('USD source never compared to EGP gold price', () {
      final s = Money.parse('1.00', usd);
      final r = ill(s); // only an EGP quote
      expect(r.band, InvestBand.gold);
      expect(r.rows.whereType<GoldRow>(), isEmpty);
      expect(
        r.rows.whereType<NoPriceRow>().map((x) => x.instrument),
        contains(InvestInstrument.gold),
      );
    });
    test('SAR: noPrice for gold and usd', () {
      final r = ill(Money.parse('100.00', Currency.of('SAR')));
      final np = r.rows.whereType<NoPriceRow>().toList();
      expect(np.map((x) => x.instrument), [
        InvestInstrument.gold,
        InvestInstrument.usd,
      ]);
      expect(np.first.currency.code, 'SAR');
    });
    test('EGP with no FX rate: usd noPrice(EGP)', () {
      final r = illustrate(
        saved: e('500.00'),
        prices: InvestPrices(gold: [g('4000.00')], certificateRateBp: 2000),
        instruments: {InvestInstrument.usd},
        horizonMonths: 12,
        now: now,
        thresholds: th,
      );
      expect(r.rows.single, isA<NoPriceRow>());
    });
    test('3-decimal currency exponents', () {
      final kwd = Currency.of('KWD');
      // 10.000 KWD at 20.000 KWD/g -> 0.50 g
      final r = ill(Money.parse('10.000', kwd), gold: [g('20.000', c: kwd)]);
      // KWD is neither EGP nor USD: gold not supported -> noPrice
      expect(r.rows.whereType<GoldRow>(), isEmpty);
    });
  });

  group('AC4 stale', () {
    test('older than 24 h is flagged but still used', () {
      final old = now.subtract(const Duration(hours: 25));
      final r = ill(
        e('4500.00'),
        gold: [g('4000.00', at: old)],
        fx: InvestFxQuote(egpPerUsd: e('50.00'), asOf: old),
      );
      expect(r.rows.whereType<GoldRow>().single.stale, isTrue);
      expect(r.rows.whereType<GoldRow>().single.centigrams, 112);
      expect(r.rows.whereType<UsdRow>().single.stale, isTrue);
    });
    test('exactly 24 h is not stale', () {
      final at = now.subtract(const Duration(hours: 24));
      final r = ill(e('4500.00'), gold: [g('4000.00', at: at)]);
      expect(r.rows.whereType<GoldRow>().single.stale, isFalse);
    });
  });

  group('rounding and ranges', () {
    test('half-even centigrams', () {
      // 0.625 g -> 62.5 cg -> 62 (even); 0.635 -> 63.5 -> 64
      expect(
        (ill(e('2500.00'), gold: [g('4000.00')]).rows.first as GoldRow)
            .centigrams,
        62,
      );
      final r = illustrate(
        saved: e('1000.00'),
        prices: InvestPrices(gold: [g('1600.00')], certificateRateBp: 1),
        instruments: {InvestInstrument.gold},
        horizonMonths: 1,
        now: now,
        thresholds: th,
      );
      expect((r.rows.single as GoldRow).centigrams, 62);
      final r2 = illustrate(
        saved: e('1016.00'),
        prices: InvestPrices(gold: [g('1600.00')], certificateRateBp: 1),
        instruments: {InvestInstrument.gold},
        horizonMonths: 1,
        now: now,
        thresholds: th,
      );
      expect((r2.rows.single as GoldRow).centigrams, 64); // 63.5 -> even
    });
    test('certificate rounds half-even once', () {
      // 0.05 EGP * 1 bp * 1 month / 120000 -> 5*1/120000 ~ 0
      final r = ill(e('1000.00'), months: 1);
      // 100000 * 2000 * 1 / 120000 = 1666.67 -> 1667
      expect(r.rows.whereType<CertificateRow>().single.payout, e('16.67'));
    });
    test('horizon out of 1..24 throws', () {
      expect(() => ill(e('500.00'), months: 0), throwsRangeError);
      expect(() => ill(e('500.00'), months: 25), throwsRangeError);
    });
    test('exact 0.25 g price is gold at exact comparison', () {
      // Price that would mis-round in floating point: 3999.99/g
      final q = g('3999.99');
      // G = 999.9975 -> 1000.00 >= G gold; 999.99 < G stocks
      expect(band('999.99', q), InvestBand.stocks);
      expect(band('1000.00', q), InvestBand.gold);
      // 4000.04/g: G = 1000.01 exactly
      final q2 = g('4000.04');
      expect(band('1000.00', q2), InvestBand.stocks);
      expect(band('1000.01', q2), InvestBand.gold);
    });
  });

  group('negative proofs', () {
    test('NP1: no double in lib/ask/', () {
      final files = Directory('lib/ask')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      expect(files, isNotEmpty);
      for (final f in files) {
        final code = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(
          RegExp(r'\bdouble\b|\.toDouble\(|\bnum\b').hasMatch(code),
          isFalse,
          reason: f.path,
        );
      }
    });
    test('NP2: instruments are a closed enum of gold, usd, certificate', () {
      expect(InvestInstrument.values.map((v) => v.name), [
        'gold',
        'usd',
        'certificate',
      ]);
      final r = ill(e('4500.00'));
      for (final row in r.rows) {
        expect(InvestInstrument.values, contains(row.instrument));
      }
    });
  });
}
