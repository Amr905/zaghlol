import 'dart:math';

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final gbp = Currency.of('GBP');
final kwd = Currency.of('KWD');
final jpy = Currency.of('JPY');

CivilDate d(int y, int m, int day) => CivilDate(y, m, day);
Money m(int minor, [Currency? c]) => Money(c ?? egp, minor);

final cycle = Cycle(start: d(2026, 10, 25), end: d(2026, 11, 24));
final inCycle = d(2026, 11, 3);

CycleTxn t(
  String id,
  int minor, {
  CycleDirection dir = CycleDirection.expense,
  CycleStatus st = CycleStatus.posted,
  Currency? cur,
  String? cat,
  CivilDate? date,
  bool internal = false,
  bool deleted = false,
}) => CycleTxn(
  id: id,
  direction: dir,
  status: st,
  amount: m(minor, cur),
  date: date ?? inCycle,
  categoryId: cat,
  isInternal: internal,
  isDeleted: deleted,
);

CycleOffset o(String exp, String src, int minor, {bool valid = true}) =>
    CycleOffset(
      expenseId: exp,
      sourceId: src,
      amount: m(minor),
      sourceValid: valid,
    );

CycleTotals egpOf(
  Iterable<CycleTxn> txns, [
  Iterable<CycleOffset> offs = const [],
]) => aggregateCycle(cycle, txns, offs)[egp]!;

void main() {
  group('what counts (design note §3)', () {
    test('empty cycle has no keys; zero totals via absent', () {
      expect(aggregateCycle(cycle, [], []), isEmpty);
    });
    test('declined, reversed, internal, deleted are excluded', () {
      final r = egpOf([
        t('a', 100),
        t('b', 200, st: CycleStatus.declined),
        t('c', 400, st: CycleStatus.reversed),
        t('d', 800, internal: true),
        t('e', 1600, deleted: true),
      ]);
      expect(r.spend.minor, 100);
    });
    test('pending counts and is reported separately', () {
      final r = egpOf([t('a', 100), t('b', 50, st: CycleStatus.pending)]);
      expect(r.spend.minor, 150);
      expect(r.pendingSpend.minor, 50);
    });
    test('fee and unpaired transfer_out are spend; transfer_in/income/refund '
        'are income', () {
      final r = egpOf([
        t('a', 10, dir: CycleDirection.fee),
        t('b', 20, dir: CycleDirection.transferOut),
        t('c', 1000, dir: CycleDirection.income),
        t('d', 300, dir: CycleDirection.transferIn),
        t('e', 5, dir: CycleDirection.refund),
      ]);
      expect(r.spend.minor, 30);
      expect(r.income.minor, 1305);
    });
    test('rows outside the cycle are ignored; boundaries are inclusive', () {
      final r = egpOf([
        t('a', 1, date: d(2026, 10, 24)),
        t('b', 2, date: d(2026, 10, 25)),
        t('c', 4, date: d(2026, 11, 24)),
        t('d', 8, date: d(2026, 11, 25)),
      ]);
      expect(r.spend.minor, 6);
    });
    test('zero amount counts 0; currency still appears', () {
      expect(egpOf([t('a', 0)]).spend.minor, 0);
    });
    test('partial refund reduces spend and the refund income by the link', () {
      final r = egpOf(
        [t('x', 1000, cat: 'food'), t('r', 300, dir: CycleDirection.refund)],
        [o('x', 'r', 300)],
      );
      expect(r.spend.minor, 700);
      expect(r.byCategoryMinor, {'food': 700});
      expect(r.income.minor, 0, reason: 'fully matched refund is not income');
    });
    test('half-matched refund leaves the rest as income', () {
      final r = egpOf(
        [t('x', 1000), t('r', 500, dir: CycleDirection.refund)],
        [o('x', 'r', 200)],
      );
      expect(r.spend.minor, 800);
      expect(r.income.minor, 300);
    });
    test('reimbursement in a later cycle restates the old cycle only', () {
      final later = Cycle(start: d(2026, 11, 25), end: d(2026, 12, 24));
      final exp = t('x', 1000, cat: 'food');
      final src = t(
        's',
        400,
        dir: CycleDirection.transferIn,
        date: d(2026, 11, 28),
      );
      final off = [o('x', 's', 400)];
      final old = aggregateCycle(cycle, [exp, src], off)[egp]!;
      final next = aggregateCycle(later, [exp, src], off)[egp]!;
      expect(old.spend.minor, 600);
      expect(old.income.minor, 0);
      expect(next.spend.minor, 0, reason: 'no spend row in the later cycle');
      expect(next.income.minor, 0, reason: 'income net of the reimbursement');
    });
    test('a soft-deleted or declined source no longer offsets', () {
      final r = egpOf(
        [t('x', 1000), t('r', 300, dir: CycleDirection.refund, deleted: true)],
        [o('x', 'r', 300, valid: false)],
      );
      expect(r.spend.minor, 1000);
      expect(r.income.minor, 0);
    });
    test('an offset on an excluded expense does nothing', () {
      final r = egpOf(
        [t('x', 1000, st: CycleStatus.declined), t('y', 5)],
        [o('x', 'r', 300)],
      );
      expect(r.spend.minor, 5);
    });
    test('uncategorized goes to _none and categories sum to spend', () {
      final r = egpOf([t('a', 5), t('b', 7, cat: 'c1'), t('c', 11, cat: 'c1')]);
      expect(r.byCategoryMinor, {'_none': 5, 'c1': 18});
    });
    test('KWD (3) and JPY (0) exponents are plain minor units', () {
      final res = aggregateCycle(cycle, [
        t('a', 1500, cur: kwd),
        t('b', 300, cur: jpy),
      ], []);
      expect(res[kwd]!.spend.minor, 1500);
      expect(res[jpy]!.spend.minor, 300);
    });
    test('GBP rows never change EGP numbers (isolation)', () {
      final base = [
        t('a', 100, cat: 'c'),
        t('i', 900, dir: CycleDirection.income),
      ];
      final before = egpOf(base);
      final res = aggregateCycle(cycle, [
        ...base,
        t('g', 5000, cur: gbp),
        t('h', 70, cur: gbp, dir: CycleDirection.income),
      ], []);
      expect(res[egp]!.spend, before.spend);
      expect(res[egp]!.income, before.income);
      expect(res[egp]!.byCategoryMinor, before.byCategoryMinor);
      expect(res[gbp]!.spend.minor, 5000);
    });
    test('overflow propagates', () {
      expect(
        () => egpOf([t('a', Money.maxMinor), t('b', 1)]),
        throwsA(isA<MoneyOverflow>()),
      );
    });
    test('offset in another currency throws instead of mixing', () {
      expect(
        () => aggregateCycle(
          cycle,
          [t('x', 100)],
          [
            CycleOffset(
              expenseId: 'x',
              sourceId: 's',
              amount: Money(gbp, 1),
              sourceValid: true,
            ),
          ],
        ),
        throwsA(isA<CurrencyMismatch>()),
      );
    });
  });

  group('DST days (Cairo +120 / +180)', () {
    // 2025: Cairo DST starts Fri 25 Apr (00:00 -> 01:00), ends Thu 30 Oct
    // (24:00 -> 23:00). Dates come from the stored offset only.
    int utc(int y, int mo, int dd, int h, [int mi = 0]) =>
        DateTime.utc(y, mo, dd, h, mi).millisecondsSinceEpoch;
    final s = PaydaySchedule.single(25);

    test('01:00 local on spring-forward day belongs to that local day', () {
      final date = CivilDate.fromLocalMs(utc(2025, 4, 24, 22), 180);
      expect(date, d(2025, 4, 25));
      expect(s.cycleOn(date).start, d(2025, 4, 25), reason: 'payday 25');
      // UTC bucketing would have put it on 24 Apr, the previous cycle.
      expect(
        s.cycleOn(CivilDate.fromLocalMs(utc(2025, 4, 24, 22), 0)).start,
        d(2025, 3, 25),
      );
    });
    test('fall-back day: both +180 and +120 stamps stay on 30 Oct', () {
      expect(
        CivilDate.fromLocalMs(utc(2025, 10, 29, 21, 30), 180),
        d(2025, 10, 30),
      );
      expect(
        CivilDate.fromLocalMs(utc(2025, 10, 30, 22), 120),
        d(2025, 10, 31),
      );
      expect(
        CivilDate.fromLocalMs(utc(2025, 10, 30, 21, 59), 120),
        d(2025, 10, 30),
      );
    });
    test('daysRemaining is date arithmetic, immune to 23/25 hour days', () {
      final c = s.cycleOn(d(2025, 10, 27));
      expect(
        c.daysRemaining(d(2025, 10, 30)),
        c.end.difference(d(2025, 10, 30)) + 1,
      );
      expect(Cycle(start: d(2025, 10, 25), end: d(2025, 11, 24)).length, 31);
    });
  });

  group('properties', () {
    test('(c) conservation over all cycles; byCategory sums to spend', () {
      for (var seed = 0; seed < 200; seed++) {
        final r = Random(seed);
        final s = PaydaySchedule.single(1 + r.nextInt(28));
        final txns = <CycleTxn>[];
        var globalSpend = 0;
        var globalIncome = 0;
        for (var i = 0; i < 60; i++) {
          final dir = CycleDirection.values[r.nextInt(6)];
          final st = CycleStatus.values[r.nextInt(4)];
          final internal = r.nextInt(8) == 0;
          final deleted = r.nextInt(8) == 0;
          final amt = r.nextInt(100000);
          final date = d(2026, 1, 1).plusDays(r.nextInt(400));
          txns.add(
            t(
              'x$i',
              amt,
              dir: dir,
              st: st,
              internal: internal,
              deleted: deleted,
              date: date,
              cat: r.nextBool() ? 'c${r.nextInt(4)}' : null,
            ),
          );
          final counts =
              !internal &&
              !deleted &&
              (st == CycleStatus.posted || st == CycleStatus.pending);
          if (counts) {
            if ({
              CycleDirection.expense,
              CycleDirection.fee,
              CycleDirection.transferOut,
            }.contains(dir)) {
              globalSpend += amt;
            } else {
              globalIncome += amt;
            }
          }
        }
        // Walk every cycle from the one holding 1 Jan 2026 (the earliest
        // row) far enough to pass the latest row.
        var spend2 = 0;
        var income2 = 0;
        var cc = s.cycleOn(d(2026, 1, 1));
        for (var i = 0; i < 20; i++) {
          final tot = aggregateCycle(cc, txns, [])[egp];
          if (tot != null) {
            spend2 += tot.spend.minor;
            income2 += tot.income.minor;
            expect(
              tot.byCategoryMinor.values.fold<int>(0, (a, b) => a + b),
              tot.spend.minor,
            );
          }
          cc = s.after(cc);
        }
        expect(spend2, globalSpend, reason: 'seed $seed');
        expect(income2, globalIncome, reason: 'seed $seed');
      }
    });

    test('(d) safe x days <= remaining < (safe+1) x days; floor', () {
      for (var seed = 0; seed < 200; seed++) {
        final r = Random(seed);
        final budget = 1 + r.nextInt(100000000);
        final spend = r.nextInt(120000000);
        final cyc = Cycle(start: d(2026, 10, 25), end: d(2026, 11, 24));
        final today = cyc.start.plusDays(r.nextInt(31));
        final safe = safeToSpend(
          budget: m(budget),
          spend: m(spend),
          cycle: cyc,
          today: today,
        )!;
        final days = cyc.daysRemaining(today);
        final remaining = max(0, budget - spend);
        expect(safe.minor * days <= remaining, isTrue);
        expect(remaining < (safe.minor + 1) * days, isTrue);
      }
    });

    test('(e) idealBurn monotone, 0 at 0, budget at length, BigInt oracle', () {
      final big = BigInt.from(Money.maxMinor);
      for (var seed = 0; seed < 200; seed++) {
        final r = Random(seed);
        final budget = seed < 50
            ? Money.maxMinor - r.nextInt(1000)
            : r.nextInt(1 << 31) * 1000;
        final len = 28 + r.nextInt(4);
        var prev = -1;
        for (var day = 0; day <= len; day++) {
          final v = idealBurn(m(budget), day, len).minor;
          expect(v, greaterThanOrEqualTo(prev));
          final oracle =
              (BigInt.from(budget) * BigInt.from(day)) ~/ BigInt.from(len);
          expect(BigInt.from(v), oracle);
          expect(oracle <= big, isTrue);
          prev = v;
        }
        expect(idealBurn(m(budget), 0, len).minor, 0);
        expect(idealBurn(m(budget), len, len).minor, budget);
      }
    });

    test('(f) another currency leaves the first identical', () {
      for (var seed = 0; seed < 200; seed++) {
        final r = Random(seed);
        final base = [
          for (var i = 0; i < 10; i++)
            t(
              'e$i',
              r.nextInt(5000),
              dir: CycleDirection.values[r.nextInt(6)],
              cat: 'c${r.nextInt(3)}',
            ),
        ];
        final extra = [
          for (var i = 0; i < 10; i++)
            t(
              'g$i',
              r.nextInt(5000),
              cur: gbp,
              dir: CycleDirection.values[r.nextInt(6)],
            ),
        ];
        final a = aggregateCycle(cycle, base, [])[egp];
        final b = aggregateCycle(cycle, [...base, ...extra], [])[egp];
        expect(b!.spend, a!.spend);
        expect(b.income, a.income);
        expect(b.pendingSpend, a.pendingSpend);
        expect(b.byCategoryMinor, a.byCategoryMinor);
      }
    });
  });

  group('safe-to-spend and burn line', () {
    test('spec example: 2,200 left, 7 days = 31 428 minor (314 whole)', () {
      final cyc = Cycle(start: d(2026, 11, 1), end: d(2026, 11, 30));
      final safe = safeToSpend(
        budget: m(500000),
        spend: m(280000),
        cycle: cyc,
        today: d(2026, 11, 24),
      )!;
      expect(cyc.daysRemaining(d(2026, 11, 24)), 7);
      expect(safe.minor, 31428);
      expect(safe.minor ~/ 100, 314);
    });
    test('null for no / zero budget; 0 when overspent', () {
      final cyc = cycle;
      expect(
        safeToSpend(budget: null, spend: m(5), cycle: cyc, today: inCycle),
        isNull,
      );
      expect(
        safeToSpend(budget: m(0), spend: m(5), cycle: cyc, today: inCycle),
        isNull,
      );
      expect(
        safeToSpend(
          budget: m(100),
          spend: m(500),
          cycle: cyc,
          today: inCycle,
        )!.minor,
        0,
      );
    });
    test('last day: 1 day remaining; payday: full length', () {
      final cyc = cycle;
      expect(
        safeToSpend(
          budget: m(1000),
          spend: m(0),
          cycle: cyc,
          today: cyc.end,
        )!.minor,
        1000,
      );
      expect(
        safeToSpend(
          budget: m(3100),
          spend: m(0),
          cycle: cyc,
          today: cyc.start,
        )!.minor,
        100,
      );
    });
    test('currency mismatch throws', () {
      expect(
        () => safeToSpend(
          budget: m(100),
          spend: Money(gbp, 1),
          cycle: cycle,
          today: inCycle,
        ),
        throwsA(isA<CurrencyMismatch>()),
      );
    });
    test('budgetBasis: overall wins, else the category sum (A-16)', () {
      expect(budgetBasis(m(10), [m(3), m(4)])!.minor, 10);
      expect(budgetBasis(null, [m(3), m(4)])!.minor, 7);
      expect(budgetBasis(null, []), isNull);
    });
    test(
      'burnLine: origin 0, cumulative actual cut at today, end = budget',
      () {
        final cyc = Cycle(start: d(2026, 11, 1), end: d(2026, 11, 30));
        final txns = [
          t('a', 100, date: d(2026, 11, 1)),
          t('b', 50, date: d(2026, 11, 3)),
          t('r', 20, dir: CycleDirection.refund, date: d(2026, 11, 9)),
          t('c', 999, date: d(2026, 11, 20)),
        ];
        final byDay = netSpendByDay(cyc, txns, [o('a', 'r', 20)], egp);
        expect(byDay, {1: 80, 3: 50, 20: 999});
        final line = burnLine(
          budget: m(3000),
          cycle: cyc,
          today: d(2026, 11, 5),
          spendByDay: byDay,
        );
        expect(line.length, 31);
        expect(line.first.day, 0);
        expect(line.first.ideal.minor, 0);
        expect(line.first.actual!.minor, 0);
        expect(line[1].actual!.minor, 80);
        expect(line[3].actual!.minor, 130);
        expect(line[5].actual!.minor, 130);
        expect(line[6].actual, isNull);
        expect(line.last.ideal.minor, 3000);
      },
    );
    test('isUnderIdealLine boundary', () {
      final cyc = Cycle(start: d(2026, 11, 1), end: d(2026, 11, 30));
      final today = d(2026, 11, 15); // day 15 -> 1500 of 3000
      expect(
        isUnderIdealLine(
          budget: m(3000),
          spend: m(1500),
          cycle: cyc,
          today: today,
        ),
        isTrue,
      );
      expect(
        isUnderIdealLine(
          budget: m(3000),
          spend: m(1501),
          cycle: cyc,
          today: today,
        ),
        isFalse,
      );
    });
    test('truncated cycle uses its real length (EC-21), not prorated', () {
      final cyc = Cycle(start: d(2026, 10, 25), end: d(2026, 11, 9));
      expect(cyc.length, 16);
      expect(idealBurn(m(1600), 16, cyc.length).minor, 1600);
      expect(() => idealBurn(m(1600), 17, 16), throwsRangeError);
    });
  });
}
