import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  final egp = Currency.of('EGP');
  final usd = Currency.of('USD');
  final kwd = Currency.of('KWD');

  GoldPrice? prices(String s) => s == 'XAU21_G'
      ? GoldPrice(price: Money(egp, 421750))
      : s == 'XAU24_G'
      ? GoldPrice(price: Money(egp, 480000), stale: true)
      : null;

  group('gold valuation', () {
    test('AC: 24 g of 21K is valued at the current 21K price', () {
      final w = computeNetWorth(
        money: const [],
        gold: [GoldLine('XAU21_G', 24000)],
        goldPrice: prices,
      );
      expect(w.valuedGold.single.value, Money(egp, 10122000));
      expect(w.valuedGold.single.stale, isFalse);
      // native unit is kept, in milligrams
      expect(w.unit('XAU21_G')!.assetsMinor, 24000);
    });

    test('fractions of a gram round half-even once', () {
      // 0.5 minor unit: 1 minor x 500 / 1000 -> 0 (even); 3 x 500/1000 = 1.5 -> 2
      expect(valueGold(Money(egp, 1), 500), Money(egp, 0));
      expect(valueGold(Money(egp, 3), 500), Money(egp, 2));
      expect(valueGold(Money(egp, 421750), 5500), Money(egp, 2319625));
    });

    test('no price: stays native, never zero or guessed (EC-35)', () {
      final w = computeNetWorth(
        money: const [],
        gold: [GoldLine('XAU18_G', 3000)],
        goldPrice: prices,
      );
      expect(w.valuedGold, isEmpty);
      expect(w.unit('XAU18_G')!.assetsMinor, 3000);
      expect(w.currencyTotalsWithGoldValued.currencies, isEmpty);
    });

    test('stale price is flagged; same symbol lines are merged', () {
      final w = computeNetWorth(
        money: const [],
        gold: [GoldLine('XAU24_G', 1000), GoldLine('XAU24_G', 4000)],
        goldPrice: prices,
      );
      expect(w.valuedGold.single.quantityMilli, 5000);
      expect(w.valuedGold.single.stale, isTrue);
    });

    test('invalid gold lines are refused', () {
      expect(() => GoldLine('EGP', 1), throwsArgumentError);
      expect(() => GoldLine('XAU21_G', 0), throwsArgumentError);
      expect(GoldSymbols.forKarat(21), 'XAU21_G');
      expect(GoldSymbols.forKarat(14), isNull);
    });
  });

  group('per unit', () {
    test('AC: never sums across currencies', () {
      final w = computeNetWorth(
        money: [
          MoneyLine(Money(egp, 5400000)),
          MoneyLine(Money(usd, 120000)),
          MoneyLine(Money(egp, 100000), isLiability: true),
        ],
        gold: [GoldLine('XAU21_G', 24000)],
        goldPrice: prices,
      );
      expect(w.units.map((u) => u.unit), ['EGP', 'USD', 'XAU21_G']);
      expect(w.unit('EGP')!.netMinor, 5300000);
      expect(w.unit('USD')!.netMinor, 120000);
      expect(w.unit('EGP')!.liabilitiesMinor, 100000);
      // valued gold does not leak into the currency bucket
      expect(w.unit('EGP')!.assetsMinor, 5400000);
      // the ≈ feed has EGP net + valued gold, USD separate
      expect(
        w.currencyTotalsWithGoldValued[egp],
        Money(egp, 5300000 + 10122000),
      );
      expect(w.currencyTotalsWithGoldValued[usd], Money(usd, 120000));
    });

    test(
      'liabilities above assets give a negative net; negative liability',
      () {
        final w = computeNetWorth(
          money: [
            MoneyLine(Money(egp, 1000)),
            MoneyLine(Money(egp, 5000), isLiability: true),
            MoneyLine(Money(usd, 700), isLiability: true),
            MoneyLine(Money(usd, -200), isLiability: true),
          ],
        );
        expect(w.unit('EGP')!.netMinor, -4000);
        expect(w.unit('USD')!.liabilitiesMinor, 500);
      },
    );

    test('zero units are left out; 3-decimal currency exact', () {
      final w = computeNetWorth(
        money: [
          MoneyLine(Money(usd, 0)),
          MoneyLine(Money(kwd, 1234)),
          MoneyLine(Money(kwd, 1), isLiability: true),
        ],
      );
      expect(w.units.map((u) => u.unit), ['KWD']);
      expect(w.unit('KWD')!.netMinor, 1233);
    });

    test('empty input is empty', () {
      final w = computeNetWorth(money: const []);
      expect(w.units, isEmpty);
      expect(snapshotRows(w), isEmpty);
    });

    test('overflow is a typed code, not an amount', () {
      expect(
        () => computeNetWorth(
          money: [
            MoneyLine(Money(egp, Money.maxMinor)),
            MoneyLine(Money(egp, 1)),
          ],
        ),
        throwsA(
          isA<NetWorthOverflow>().having(
            (e) => e.toString(),
            'text',
            'NET_WORTH_OVERFLOW',
          ),
        ),
      );
    });

    test('snapshot rows are native (gold in milligrams, not valued)', () {
      final w = computeNetWorth(
        money: [MoneyLine(Money(egp, 100))],
        gold: [GoldLine('XAU21_G', 24000)],
        goldPrice: prices,
      );
      expect(snapshotRows(w), [
        (unit: 'EGP', assetsMinor: 100, liabilitiesMinor: 0),
        (unit: 'XAU21_G', assetsMinor: 24000, liabilitiesMinor: 0),
      ]);
    });
  });

  group('snapshotDue', () {
    final start = CivilDate(2026, 11, 28);
    test('none yet, new cycle, same cycle, older than a month', () {
      expect(
        snapshotDue(
          last: null,
          today: CivilDate(2026, 11, 29),
          currentCycleStart: start,
        ),
        isTrue,
      );
      expect(
        snapshotDue(
          last: CivilDate(2026, 11, 27),
          today: CivilDate(2026, 11, 28),
          currentCycleStart: start,
        ),
        isTrue,
      );
      expect(
        snapshotDue(
          last: CivilDate(2026, 11, 28),
          today: CivilDate(2026, 12, 10),
          currentCycleStart: start,
        ),
        isFalse,
      );
      expect(
        snapshotDue(
          last: CivilDate(2026, 11, 28),
          today: CivilDate(2026, 12, 30),
          currentCycleStart: start,
        ),
        isTrue,
      );
    });
  });

  group('certificate payouts', () {
    final p = Money(egp, 50000000); // 500,000.00

    test('AC: monthly 8.1 % pays 3,375.00 on the maturity day', () {
      final e = certificatePayouts(
        assetId: 'a',
        principal: p,
        rateBp: 810,
        payout: PayoutFrequency.monthly,
        maturity: CivilDate(2027, 11, 28),
        from: CivilDate(2026, 11, 20),
        to: CivilDate(2027, 1, 31),
      );
      expect(e.map((x) => x.date.toIso()), [
        '2026-11-28',
        '2026-12-28',
        '2027-01-28',
      ]);
      expect(e.first.amount, Money(egp, 337500));
      expect(e.first.isMaturity, isFalse);
    });

    test('day 31 clamps to short months; leap February', () {
      final e = certificatePayouts(
        assetId: 'a',
        principal: p,
        rateBp: 1200,
        payout: PayoutFrequency.monthly,
        maturity: CivilDate(2028, 5, 31),
        from: CivilDate(2028, 1, 1),
        to: CivilDate(2028, 5, 31),
      );
      expect(e.map((x) => x.date.toIso()), [
        '2028-01-31',
        '2028-02-29',
        '2028-03-31',
        '2028-04-30',
        '2028-05-31',
      ]);
      expect(e.last.isMaturity, isTrue);
    });

    test('quarterly, annual and semi-annual amounts', () {
      List<CertificatePayoutEvent> run(PayoutFrequency f) => certificatePayouts(
        assetId: 'a',
        principal: p,
        rateBp: 1000,
        payout: f,
        maturity: CivilDate(2027, 6, 15),
        from: CivilDate(2026, 6, 1),
        to: CivilDate(2027, 6, 30),
      );
      expect(run(PayoutFrequency.quarterly).length, 5);
      expect(run(PayoutFrequency.quarterly).first.amount, Money(egp, 1250000));
      expect(run(PayoutFrequency.semiAnnual).first.amount, Money(egp, 2500000));
      expect(run(PayoutFrequency.annual).map((x) => x.date.toIso()), [
        '2026-06-15',
        '2027-06-15',
      ]);
    });

    test('start date bounds the schedule; from/to filter', () {
      final e = certificatePayouts(
        assetId: 'a',
        principal: p,
        rateBp: 1200,
        payout: PayoutFrequency.monthly,
        maturity: CivilDate(2027, 3, 10),
        startDate: CivilDate(2026, 12, 10),
        from: CivilDate(2026, 1, 1),
        to: CivilDate(2030, 1, 1),
      );
      expect(e.map((x) => x.date.toIso()), [
        '2027-01-10',
        '2027-02-10',
        '2027-03-10',
      ]);
    });

    test('at maturity: whole months of interest; unknown without a start', () {
      final with0 = certificatePayouts(
        assetId: 'a',
        principal: p,
        rateBp: 1200,
        payout: PayoutFrequency.atMaturity,
        maturity: CivilDate(2027, 6, 15),
        startDate: CivilDate(2026, 6, 16),
        from: CivilDate(2027, 1, 1),
        to: CivilDate(2027, 12, 31),
      );
      expect(with0.single.amount, Money(egp, 50000000 * 1200 * 11 ~/ 120000));
      final without = certificatePayouts(
        assetId: 'a',
        principal: p,
        rateBp: 1200,
        payout: PayoutFrequency.atMaturity,
        maturity: CivilDate(2027, 6, 15),
        from: CivilDate(2027, 1, 1),
        to: CivilDate(2027, 12, 31),
      );
      expect(without.single.amount, isNull);
      expect(
        certificatePayouts(
          assetId: 'a',
          principal: p,
          rateBp: 1200,
          payout: PayoutFrequency.atMaturity,
          maturity: CivilDate(2027, 6, 15),
          from: CivilDate(2027, 7, 1),
          to: CivilDate(2027, 12, 31),
        ),
        isEmpty,
      );
    });

    test('zero rate pays zero; bad rate refused; slugs', () {
      final e = certificatePayouts(
        assetId: 'a',
        principal: p,
        rateBp: 0,
        payout: PayoutFrequency.annual,
        maturity: CivilDate(2027, 6, 15),
        from: CivilDate(2027, 1, 1),
        to: CivilDate(2027, 12, 31),
      );
      expect(e.single.amount, Money(egp, 0));
      expect(
        () => certificatePayouts(
          assetId: 'a',
          principal: p,
          rateBp: 100001,
          payout: PayoutFrequency.annual,
          maturity: CivilDate(2027, 6, 15),
          from: CivilDate(2027, 1, 1),
          to: CivilDate(2027, 12, 31),
        ),
        throwsArgumentError,
      );
      expect(
        PayoutFrequency.fromSlug('semi_annual'),
        PayoutFrequency.semiAnnual,
      );
      expect(PayoutFrequency.fromSlug('weekly'), isNull);
    });
  });
}
