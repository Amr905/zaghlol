import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final _egp = Currency.of('EGP');
final _usd = Currency.of('USD');
final _t0 = DateTime.utc(2026, 11, 1, 10);
final _now = DateTime.utc(2026, 11, 20, 10);

Money _m(int minor, [Currency? c]) => Money(c ?? _egp, minor);

BreakdownLine _line({
  required BalanceAnchor? anchor,
  TxnTotals totals = const TxnTotals(),
  bool liability = false,
  Currency? currency,
  DateTime? now,
}) => resolveAccountLine(
  accountId: 'a',
  label: 'A',
  accountKind: liability ? 'credit' : 'debit',
  currency: currency ?? _egp,
  isLiability: liability,
  now: now ?? _now,
  anchor: anchor,
  totals: totals,
);

void main() {
  group('cashSignOfDirection', () {
    test('every stored direction, unknown moves nothing', () {
      expect(cashSignOfDirection('income'), 1);
      expect(cashSignOfDirection('refund'), 1);
      expect(cashSignOfDirection('transfer_in'), 1);
      expect(cashSignOfDirection('expense'), -1);
      expect(cashSignOfDirection('fee'), -1);
      expect(cashSignOfDirection('transfer_out'), -1);
      expect(cashSignOfDirection('mystery'), 0);
    });
  });

  group('pickAnchor', () {
    test('no figures: no anchor', () {
      expect(pickAnchor(currency: _egp, isLiability: false), isNull);
    });

    test('reported only', () {
      final a = pickAnchor(
        currency: _egp,
        isLiability: false,
        reportedBalance: _m(1000),
        reportedAsOf: _t0,
      )!;
      expect(a.amount.minor, 1000);
      expect(a.userEntered, isFalse);
    });

    test('asset with only an available figure anchors on it, own basis', () {
      final a = pickAnchor(
        currency: _egp,
        isLiability: false,
        reportedAvailable: _m(500),
        reportedAsOf: _t0,
      )!;
      expect(a.amount.minor, 500);
      expect(a.effectiveBasis, AnchorBasis.reportedAvailable);
      final both = pickAnchor(
        currency: _egp,
        isLiability: false,
        reportedBalance: _m(700),
        reportedAvailable: _m(500),
        reportedAsOf: _t0,
      )!;
      expect(both.amount.minor, 700);
      expect(both.effectiveBasis, AnchorBasis.reportedBalance);
      expect(
        pickAnchor(
          currency: _egp,
          isLiability: false,
          reportedAvailable: _m(500, _usd),
          reportedAsOf: _t0,
        ),
        isNull,
      );
    });

    test('user entry newer than the reported one wins', () {
      final a = pickAnchor(
        currency: _egp,
        isLiability: false,
        reportedBalance: _m(1000),
        reportedAsOf: _t0,
        userBalance: _m(2000),
        userAsOf: _t0.add(const Duration(days: 1)),
      )!;
      expect(a.amount.minor, 2000);
      expect(a.userEntered, isTrue);
    });

    test('reported newer than the user entry wins; a tie goes to reported', () {
      final newer = pickAnchor(
        currency: _egp,
        isLiability: false,
        reportedBalance: _m(1000),
        reportedAsOf: _t0.add(const Duration(days: 1)),
        userBalance: _m(2000),
        userAsOf: _t0,
      )!;
      expect(newer.amount.minor, 1000);
      final tie = pickAnchor(
        currency: _egp,
        isLiability: false,
        reportedBalance: _m(1000),
        reportedAsOf: _t0,
        userBalance: _m(2000),
        userAsOf: _t0,
      )!;
      expect(tie.userEntered, isFalse);
    });

    test('a figure in another currency is ignored, never converted', () {
      expect(
        pickAnchor(
          currency: _egp,
          isLiability: false,
          reportedBalance: _m(1000, _usd),
          reportedAsOf: _t0,
          userBalance: _m(5, _usd),
          userAsOf: _t0,
        ),
        isNull,
      );
    });

    test('credit: balance is never the owed amount (it is "Avl bal")', () {
      // limit 2000, stored balance 1500 means 1500 available: owed 500.
      final a = pickAnchor(
        currency: _egp,
        isLiability: true,
        reportedBalance: _m(1500),
        reportedAvailable: _m(1000),
        creditLimit: _m(2000),
        reportedAsOf: _t0,
      )!;
      expect(a.amount.minor, 500);
      expect(a.effectiveBasis, AnchorBasis.limitMinusAvailable);
      // Spending raises owed, never lowers it.
      final l = _line(
        anchor: a,
        liability: true,
        totals: const TxnTotals(cashEffectMinor: -300, count: 1),
      );
      expect(l.amount!.minor, 800);
    });

    test('credit with a balance but no limit: unknown, not owed', () {
      expect(
        pickAnchor(
          currency: _egp,
          isLiability: true,
          reportedBalance: _m(1500),
          reportedAsOf: _t0,
        ),
        isNull,
      );
    });

    test('a typed owed amount works as a card anchor without a limit', () {
      final a = pickAnchor(
        currency: _egp,
        isLiability: true,
        userBalance: _m(700),
        userAsOf: _t0,
      )!;
      expect(a.amount.minor, 700);
      expect(a.userEntered, isTrue);
    });

    test('a typed balance dated in the future is dated now', () {
      final a = pickAnchor(
        currency: _egp,
        isLiability: false,
        userBalance: _m(700),
        userAsOf: _now.add(const Duration(days: 400)),
        reportedBalance: _m(5),
        reportedAsOf: _now.subtract(const Duration(hours: 1)),
        now: _now,
      )!;
      expect(a.asOf, _now);
      expect(a.amount.minor, 700); // dated now: newer than the bank figure
      // ...but a bank message dated at/after now still wins.
      final b = pickAnchor(
        currency: _egp,
        isLiability: false,
        userBalance: _m(700),
        userAsOf: _now.add(const Duration(days: 400)),
        reportedBalance: _m(5),
        reportedAsOf: _now,
        now: _now,
      )!;
      expect(b.amount.minor, 5);
    });

    test('credit: owed = limit - available; floored at 0', () {
      final used = pickAnchor(
        currency: _egp,
        isLiability: true,
        reportedAvailable: _m(1500),
        creditLimit: _m(2000),
        reportedAsOf: _t0,
      )!;
      expect(used.amount.minor, 500);
      final over = pickAnchor(
        currency: _egp,
        isLiability: true,
        reportedAvailable: _m(2500),
        creditLimit: _m(2000),
        reportedAsOf: _t0,
      )!;
      expect(over.amount.minor, 0);
      final overLimit = pickAnchor(
        currency: _egp,
        isLiability: true,
        reportedAvailable: _m(-300),
        creditLimit: _m(2000),
        reportedAsOf: _t0,
      )!;
      expect(overLimit.amount.minor, 2300);
    });

    test('credit without a limit or in another currency: unknown', () {
      expect(
        pickAnchor(
          currency: _egp,
          isLiability: true,
          reportedAvailable: _m(1500),
          reportedAsOf: _t0,
        ),
        isNull,
      );
      expect(
        pickAnchor(
          currency: _egp,
          isLiability: true,
          reportedAvailable: _m(1500),
          creditLimit: _m(2000, _usd),
          reportedAsOf: _t0,
        ),
        isNull,
      );
    });

    test('an asset account never derives from a limit', () {
      final a = pickAnchor(
        currency: _egp,
        isLiability: false,
        reportedAvailable: _m(1500),
        creditLimit: _m(2000),
        reportedAsOf: _t0,
      )!;
      expect(a.amount.minor, 1500);
      expect(a.effectiveBasis, AnchorBasis.reportedAvailable);
    });
  });

  group('resolveAccountLine', () {
    final reported = BalanceAnchor(
      amount: _m(10000),
      asOf: _t0,
      userEntered: false,
    );

    test('no anchor: unknown, no amount', () {
      final l = _line(anchor: null);
      expect(l.source, BalanceSource.unknown);
      expect(l.isExcluded, isTrue);
      expect(l.amount, isNull);
    });

    test('anchor without later transactions keeps its source', () {
      final l = _line(anchor: reported);
      expect(l.source, BalanceSource.reported);
      expect(l.amount!.minor, 10000);
      final u = _line(
        anchor: BalanceAnchor(amount: _m(7), asOf: _t0, userEntered: true),
      );
      expect(u.source, BalanceSource.userEntered);
    });

    test('asset: cash-side effect is added', () {
      final l = _line(
        anchor: reported,
        totals: const TxnTotals(cashEffectMinor: -2500, count: 2),
      );
      expect(l.source, BalanceSource.computed);
      expect(l.amount!.minor, 7500);
      expect(l.sinceCount, 2);
      expect(l.asOf, _t0);
    });

    test('asset may go negative (overdraft), signed', () {
      final l = _line(
        anchor: reported,
        totals: const TxnTotals(cashEffectMinor: -12000, count: 1),
      );
      expect(l.amount!.minor, -2000);
      expect(l.group, BreakdownGroup.accounts);
    });

    test('liability: an expense raises what is owed, a payment lowers it', () {
      final spend = _line(
        anchor: reported,
        liability: true,
        totals: const TxnTotals(cashEffectMinor: -3000, count: 1),
      );
      expect(spend.amount!.minor, 13000);
      expect(spend.group, BreakdownGroup.liabilities);
      final pay = _line(
        anchor: reported,
        liability: true,
        totals: const TxnTotals(cashEffectMinor: 15000, count: 1),
      );
      expect(pay.amount!.minor, -5000); // overpaid: negative liability
    });

    test('stale only without later transactions and past 30 days', () {
      final old = _line(
        anchor: reported,
        now: _t0.add(const Duration(days: 31)),
      );
      expect(old.stale, isTrue);
      final fresh = _line(
        anchor: reported,
        now: _t0.add(const Duration(days: 30)),
      );
      expect(fresh.stale, isFalse);
      final computed = _line(
        anchor: reported,
        totals: const TxnTotals(cashEffectMinor: 1, count: 1),
        now: _t0.add(const Duration(days: 90)),
      );
      expect(computed.stale, isFalse);
    });

    test('overflow throws a code, no amount', () {
      expect(
        () => _line(
          anchor: BalanceAnchor(
            amount: _m(Money.maxMinor),
            asOf: _t0,
            userEntered: false,
          ),
          totals: const TxnTotals(cashEffectMinor: 1, count: 1),
        ),
        throwsA(isA<NetWorthOverflow>()),
      );
    });
  });

  group('breakdown', () {
    BreakdownLine acct(
      String id,
      String inst,
      int minor, {
      Currency? cur,
      bool liability = false,
    }) => BreakdownLine(
      group: liability ? BreakdownGroup.liabilities : BreakdownGroup.accounts,
      unit: (cur ?? _egp).code,
      label: id,
      source: BalanceSource.reported,
      refId: id,
      institutionCode: inst,
      accountKind: liability ? 'credit' : 'debit',
      amount: _m(minor, cur),
    );

    test(
      'unit totals equal computeNetWorth per currency; unknown excluded',
      () {
        final lines = [
          acct('a1', 'cib', 10000),
          acct('a2', 'cib', 5000),
          acct('a3', 'nbe', 2000),
          acct('c1', 'cib', 4000, liability: true),
          acct('w1', 'wise', 300, cur: _usd),
          BreakdownLine(
            group: BreakdownGroup.assets,
            unit: 'EGP',
            label: 'Cert',
            source: BalanceSource.asset,
            amount: _m(20000),
          ),
          BreakdownLine(
            group: BreakdownGroup.assets,
            unit: 'XAU21_G',
            label: 'Gold',
            source: BalanceSource.asset,
            quantityMilli: 24000,
          ),
          const BreakdownLine(
            group: BreakdownGroup.accounts,
            unit: 'EGP',
            label: 'Unknown',
            source: BalanceSource.unknown,
            refId: 'u',
            accountKind: 'debit',
          ),
          const BreakdownLine(
            group: BreakdownGroup.accounts,
            unit: 'USD',
            label: 'UnknownUsd',
            source: BalanceSource.unknown,
            refId: 'u2',
            accountKind: 'cash',
          ),
        ];
        final units = buildUnitBreakdowns(lines);
        expect([for (final u in units) u.unit], ['EGP', 'USD', 'XAU21_G']);
        final worth = computeNetWorth(
          money: moneyLinesOf(lines),
          gold: goldLinesOf(lines),
        );
        for (final u in units) {
          final w = worth.unit(u.unit)!;
          expect(u.assetsMinor, w.assetsMinor, reason: u.unit);
          expect(u.liabilitiesMinor, w.liabilitiesMinor, reason: u.unit);
          expect(u.netMinor, w.netMinor, reason: u.unit);
        }
        final egp = units.first;
        expect(egp.assetsMinor, 10000 + 5000 + 2000 + 20000);
        expect(egp.liabilitiesMinor, 4000);
        expect(egp.netMinor, 33000);
        expect(egp.excluded.map((l) => l.label), ['Unknown']);
        expect(egp.accounts.length, 3);
        expect(egp.assets.length, 1);
        expect(egp.liabilities.length, 1);
        // Never summed across currencies: USD stays its own unit.
        expect(units[1].netMinor, 300);
        expect(units[1].excluded.single.label, 'UnknownUsd');
      },
    );

    test(
      'groupByBank: bank total = sum of its accounts, none-institution alone',
      () {
        final lines = [
          acct('a1', 'cib', 10000),
          acct('a2', 'cib', 5000),
          acct('a3', 'nbe', 2000),
          BreakdownLine(
            group: BreakdownGroup.accounts,
            unit: 'EGP',
            label: 'Cash',
            source: BalanceSource.reported,
            refId: 'cash',
            accountKind: 'cash',
            amount: _m(100),
          ),
        ];
        final banks = groupByBank(lines);
        expect([for (final b in banks) b.key], ['cib', 'nbe', 'acct:cash']);
        expect(banks.first.totalMinor, 15000);
        expect(banks.first.lines.length, 2);
        expect(banks.last.totalMinor, 100);
      },
    );

    test('a bank total with an unknown account adds nothing for it', () {
      final lines = [
        acct('a1', 'cib', 10000),
        const BreakdownLine(
          group: BreakdownGroup.accounts,
          unit: 'EGP',
          label: 'B',
          source: BalanceSource.unknown,
          refId: 'b',
          institutionCode: 'cib',
          accountKind: 'debit',
        ),
      ];
      final bank = groupByBank(lines).single;
      expect(bank.totalMinor, 10000);
      expect(bank.lines.length, 2);
    });

    test('overflow of a unit total throws', () {
      expect(
        () => buildUnitBreakdowns([
          acct('a', 'x', Money.maxMinor),
          acct('b', 'x', 1),
        ]),
        throwsA(isA<NetWorthOverflow>()),
      );
    });
  });
}
