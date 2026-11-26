// T-272 (D-86, multi-currency plan §2): an exchange is counted once, in each
// currency, as "exchanged in/out" — never as income or spending. All
// amounts are synthetic.

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final kwd = Currency.of('KWD');
final jpy = Currency.of('JPY');

CivilDate d(int y, int m, int day) => CivilDate(y, m, day);

// The PO's month: payday 24, the month that starts on 24 Nov.
final cycle = Cycle(start: d(2026, 11, 24), end: d(2026, 12, 23));

CycleTxn t(
  String id,
  Currency cur,
  int minor,
  CycleDirection dir, {
  CivilDate? date,
  bool internal = false,
  bool exchange = false,
  bool deleted = false,
  CycleStatus st = CycleStatus.posted,
  String? cat,
}) => CycleTxn(
  id: id,
  direction: dir,
  status: st,
  amount: Money(cur, minor),
  date: date ?? d(2026, 11, 26),
  isInternal: internal,
  isExchange: exchange,
  isDeleted: deleted,
  categoryId: cat,
);

/// The PO's story: USD 1,000 salary on 24 Nov; on 26 Nov USD 600 is
/// exchanged to EGP 29,700 (one exchange pair, both legs internal).
List<CycleTxn> story() => [
  t(
    'salary',
    usd,
    100000,
    CycleDirection.income,
    date: d(2026, 11, 24),
    cat: 'sys:income',
  ),
  t(
    'x-out',
    usd,
    60000,
    CycleDirection.transferOut,
    internal: true,
    exchange: true,
  ),
  t(
    'x-in',
    egp,
    2970000,
    CycleDirection.transferIn,
    internal: true,
    exchange: true,
  ),
];

void main() {
  group('PO story (plan §2)', () {
    final totals = aggregateCycle(cycle, story(), const []);

    test('USD: income 1,000, exchanged out 600, left 400', () {
      final u = totals[usd]!;
      expect(u.income, Money(usd, 100000));
      expect(u.spend, Money.zero(usd));
      expect(u.exchangedIn, Money.zero(usd));
      expect(u.exchangedOut, Money(usd, 60000));
      expect(u.moneyIn, Money(usd, 100000));
      expect(u.left, Money(usd, 40000));
    });

    test('EGP: money in 29,700 (all exchanged in), no income, no spend', () {
      final e = totals[egp]!;
      expect(e.income, Money.zero(egp));
      expect(e.spend, Money.zero(egp));
      expect(e.exchangedIn, Money(egp, 2970000));
      expect(e.exchangedOut, Money.zero(egp));
      expect(e.moneyIn, Money(egp, 2970000));
      expect(e.left, Money(egp, 2970000));
    });

    test('no category total changes; the salary is income once', () {
      final withoutExchange = aggregateCycle(cycle, [story().first], const []);
      expect(totals[usd]!.income, withoutExchange[usd]!.income);
      expect(
        totals[usd]!.byCategoryMinor,
        withoutExchange[usd]!.byCategoryMinor,
      );
      expect(totals[egp]!.byCategoryMinor, isEmpty);
    });

    test('EGP spending after the exchange lowers EGP left only', () {
      final r = aggregateCycle(cycle, [
        ...story(),
        t('food', egp, 50000, CycleDirection.expense, cat: 'dining'),
      ], const []);
      expect(r[egp]!.spend, Money(egp, 50000));
      expect(r[egp]!.left, Money(egp, 2920000));
      expect(r[egp]!.moneyIn, Money(egp, 2970000));
      expect(r[usd]!.left, Money(usd, 40000));
    });

    test('reconciles per currency: opening + in − out = closing', () {
      // Opening balances (synthetic): USD 50, EGP 1,000.
      const usdOpening = 5000;
      const egpOpening = 100000;
      final u = totals[usd]!;
      final e = totals[egp]!;
      final usdClosing =
          usdOpening + 100000 /* salary */ - 60000 /* exchanged */;
      final egpClosing = egpOpening + 2970000;
      expect(usdOpening + u.left.minor, usdClosing);
      expect(egpOpening + e.left.minor, egpClosing);
    });
  });

  group('negative proofs: never counted twice', () {
    test('an exchange is never income and never spending', () {
      final r = aggregateCycle(cycle, story().skip(1), const []);
      expect(r[usd]!.income.minor, 0);
      expect(r[usd]!.spend.minor, 0);
      expect(r[egp]!.income.minor, 0);
      expect(r[egp]!.spend.minor, 0);
      expect(r[usd]!.byCategoryMinor, isEmpty);
    });

    test('unpaired legs are ordinary income/spend, never also exchange', () {
      // Not internal, not in a pair: the transfer counts as it does today.
      final r = aggregateCycle(cycle, [
        t('o', usd, 60000, CycleDirection.transferOut),
        t('i', egp, 2970000, CycleDirection.transferIn),
      ], const []);
      expect(r[usd]!.spend, Money(usd, 60000));
      expect(r[usd]!.exchangedOut, Money.zero(usd));
      expect(r[egp]!.income, Money(egp, 2970000));
      expect(r[egp]!.exchangedIn, Money.zero(egp));
      expect(r[egp]!.moneyIn, Money(egp, 2970000));
    });

    test('an exchange flag without the internal flag counts nowhere twice', () {
      // A stale flag on a freed leg: it is ordinary income, not exchange.
      final r = aggregateCycle(cycle, [
        t('i', egp, 1000, CycleDirection.transferIn, exchange: true),
      ], const []);
      expect(r[egp]!.income, Money(egp, 1000));
      expect(r[egp]!.exchangedIn, Money.zero(egp));
      expect(r[egp]!.moneyIn, Money(egp, 1000));
    });

    test('a same-currency internal transfer is not an exchange', () {
      final r = aggregateCycle(cycle, [
        t('o', egp, 1000, CycleDirection.transferOut, internal: true),
        t('i', egp, 1000, CycleDirection.transferIn, internal: true),
      ], const []);
      expect(r, isEmpty);
    });
  });

  group('edges', () {
    test('declined, reversed and deleted legs do not count', () {
      final r = aggregateCycle(cycle, [
        t(
          'a',
          egp,
          100,
          CycleDirection.transferIn,
          internal: true,
          exchange: true,
          st: CycleStatus.declined,
        ),
        t(
          'b',
          egp,
          200,
          CycleDirection.transferIn,
          internal: true,
          exchange: true,
          deleted: true,
        ),
        t(
          'c',
          egp,
          400,
          CycleDirection.transferIn,
          internal: true,
          exchange: true,
          st: CycleStatus.pending,
        ),
      ], const []);
      expect(r[egp]!.exchangedIn, Money(egp, 400));
    });

    test('a leg outside the month does not count (month boundary)', () {
      final r = aggregateCycle(cycle, [
        t(
          'before',
          egp,
          100,
          CycleDirection.transferIn,
          internal: true,
          exchange: true,
          date: d(2026, 11, 23),
        ),
        t(
          'last',
          egp,
          200,
          CycleDirection.transferIn,
          internal: true,
          exchange: true,
          date: d(2026, 12, 23),
        ),
        t(
          'after',
          egp,
          400,
          CycleDirection.transferIn,
          internal: true,
          exchange: true,
          date: d(2026, 12, 24),
        ),
      ], const []);
      expect(r[egp]!.exchangedIn, Money(egp, 200));
    });

    test('each currency keeps its own exponent (KWD 3, JPY 0)', () {
      final r = aggregateCycle(cycle, [
        t(
          'o',
          kwd,
          1500,
          CycleDirection.transferOut,
          internal: true,
          exchange: true,
        ),
        t(
          'i',
          jpy,
          730,
          CycleDirection.transferIn,
          internal: true,
          exchange: true,
        ),
      ], const []);
      expect(r[kwd]!.exchangedOut, Money(kwd, 1500));
      expect(r[kwd]!.left, Money(kwd, -1500));
      expect(r[jpy]!.exchangedIn, Money(jpy, 730));
    });

    test('totals without exchange figures read as zero (cached rows)', () {
      final c = CycleTotals(
        currency: egp,
        income: Money(egp, 100),
        spend: Money(egp, 40),
        pendingSpend: Money.zero(egp),
        byCategoryMinor: const {},
      );
      expect(c.exchangedIn, Money.zero(egp));
      expect(c.left, Money(egp, 60));
      final w = c.withExchanges(
        exchangedIn: Money(egp, 1000),
        exchangedOut: Money.zero(egp),
      );
      expect(w.moneyIn, Money(egp, 1100));
      expect(w.left, Money(egp, 1060));
      expect(w.income, Money(egp, 100));
    });
  });

  group('impliedRateE9 (bank rate from the two amounts)', () {
    test('USD 600 -> EGP 29,700 is 49.50', () {
      expect(
        impliedRateE9(Money(usd, 60000), Money(egp, 2970000)),
        49500000000,
      );
    });
    test('exponents: KWD 1.500 -> JPY 730 is 486.666666667', () {
      expect(impliedRateE9(Money(kwd, 1500), Money(jpy, 730)), 486666666667);
    });
    test('zero, negative or same currency: null', () {
      expect(impliedRateE9(Money(usd, 0), Money(egp, 1)), isNull);
      expect(impliedRateE9(Money(usd, 1), Money(egp, -1)), isNull);
      expect(impliedRateE9(Money(egp, 1), Money(egp, 1)), isNull);
    });
  });
}
