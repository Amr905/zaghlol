import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final gbp = Currency.of('GBP');

CashEvent w(String id, int minor, int at, [Currency? c]) => CashEvent(
  id: id,
  kind: CashEventKind.withdrawal,
  amount: Money(c ?? egp, minor),
  localMs: at,
);
CashEvent p(String id, int minor, int at, [Currency? c]) => CashEvent(
  id: id,
  kind: CashEventKind.payment,
  amount: Money(c ?? egp, minor),
  localMs: at,
);

final cycle = Cycle(
  start: CivilDate(2026, 10, 25),
  end: CivilDate(2026, 11, 24),
);
final inCycle = CivilDate(2026, 11, 3);

CycleTxn txn(
  String id,
  int minor, {
  String? cat,
  int covered = 0,
  Currency? cur,
  CivilDate? date,
}) => CycleTxn(
  id: id,
  direction: CycleDirection.expense,
  status: CycleStatus.posted,
  amount: Money(cur ?? egp, minor),
  date: date ?? inCycle,
  categoryId: cat,
  cashCoveredMinor: covered,
);

void main() {
  group('allocateCashPool', () {
    test('pay inside the pool is fully covered', () {
      final c = allocateCashPool([w('w', 1000, 1), p('p', 300, 2)]);
      expect(c, {'p': Money(egp, 300)});
    });

    test('pay beyond the pool: only the pool is covered', () {
      final c = allocateCashPool([w('w', 1000, 1), p('p', 1200, 2)]);
      expect(c['p'], Money(egp, 1000));
    });

    test('payment before any withdrawal is new spending', () {
      expect(allocateCashPool([p('p', 300, 1), w('w', 1000, 2)]), isEmpty);
    });

    test('the pool runs down across payments and refills', () {
      final c = allocateCashPool([
        w('w1', 500, 1),
        p('a', 300, 2),
        p('b', 300, 3), // 200 left -> 200 covered
        w('w2', 100, 4),
        p('c', 50, 5),
      ]);
      expect(c['a'], Money(egp, 300));
      expect(c['b'], Money(egp, 200));
      expect(c['c'], Money(egp, 50));
    });

    test('currencies are separate', () {
      final c = allocateCashPool([
        w('w', 1000, 1),
        p('g', 500, 2, gbp),
        p('e', 400, 3),
      ]);
      expect(c.containsKey('g'), isFalse);
      expect(c['e'], Money(egp, 400));
    });

    test('same instant: withdrawal first; input order does not matter', () {
      final a = allocateCashPool([p('p', 100, 5), w('w', 100, 5)]);
      final b = allocateCashPool([w('w', 100, 5), p('p', 100, 5)]);
      expect(a, b);
      expect(a['p'], Money(egp, 100));
    });

    test('removing a payment restores the pool for the next one', () {
      final both = allocateCashPool([
        w('w', 1000, 1),
        p('a', 800, 2),
        p('b', 800, 3),
      ]);
      expect(both['b'], Money(egp, 200));
      final without = allocateCashPool([w('w', 1000, 1), p('b', 800, 3)]);
      expect(without['b'], Money(egp, 800));
    });

    test('zero and negative amounts are ignored', () {
      expect(allocateCashPool([w('w', 0, 1), p('p', 0, 2)]), isEmpty);
    });
  });

  group('aggregateCycle with cash cover', () {
    Map<String, int> by(List<CycleTxn> x) =>
        aggregateCycle(cycle, x, const [])[egp]!.byCategoryMinor;
    int spend(List<CycleTxn> x) =>
        aggregateCycle(cycle, x, const [])[egp]!.spend.minor;

    test('withdraw 1000, pay 300: total 1000, Cash 700, Food 300', () {
      final x = [
        txn('w', 1000, cat: kCashCategoryId),
        txn('p', 300, cat: 'sys:food', covered: 300),
      ];
      expect(spend(x), 1000);
      expect(by(x), {kCashCategoryId: 700, 'sys:food': 300});
    });

    test('pay 1200 of 1000: total 1200, Cash 0, Food 1200', () {
      final x = [
        txn('w', 1000, cat: kCashCategoryId),
        txn('p', 1200, cat: 'sys:food', covered: 1000),
      ];
      expect(spend(x), 1200);
      expect(by(x), {kCashCategoryId: 0, 'sys:food': 1200});
    });

    test('two currencies stay separate', () {
      final x = [
        txn('w', 1000, cat: kCashCategoryId),
        txn('p', 300, cat: 'sys:food', covered: 300),
        txn('g', 300, cat: 'sys:food', cur: gbp),
      ];
      final r = aggregateCycle(cycle, x, const []);
      expect(r[egp]!.spend.minor, 1000);
      expect(r[gbp]!.spend.minor, 300);
    });

    test('withdraw 1000, pay 300 with 200 split back, pay 800: spend 900', () {
      final x = [
        txn('w', 1000, cat: kCashCategoryId),
        txn('p', 300, cat: 'sys:food', covered: 300),
        txn('q', 800, cat: 'sys:fun', covered: 700),
      ];
      final links = [
        CycleOffset(
          expenseId: 'p',
          sourceId: 'r',
          amount: Money(egp, 200),
          isActive: true,
        ),
      ];
      final t = aggregateCycle(cycle, x, links)[egp]!;
      expect(t.spend.minor, 900);
      expect(t.byCategoryMinor['sys:food'], 100);
      expect(t.byCategoryMinor['sys:fun'], 800);
      expect(t.byCategoryMinor[kCashCategoryId], 0);
    });

    test('a later cycle: spend 0, Food shows it, Cash floors at 0', () {
      final later = [
        txn('p', 300, cat: 'sys:food', covered: 300, date: inCycle),
      ];
      final t = aggregateCycle(cycle, later, const [])[egp]!;
      expect(t.spend.minor, 0);
      expect(t.byCategoryMinor['sys:food'], 300);
      expect(t.byCategoryMinor[kCashCategoryId], 0);
      expect(t.byCategoryMinor.values.any((v) => v < 0), isFalse);
      expect(t.coveredEarlier.minor, 300);
    });

    test('same-cycle cover leaves nothing to explain', () {
      final x = [
        txn('w', 1000, cat: kCashCategoryId),
        txn('p', 300, cat: 'sys:food', covered: 300),
      ];
      expect(aggregateCycle(cycle, x, const [])[egp]!.coveredEarlier.minor, 0);
    });

    test('part this cycle, part earlier', () {
      final x = [
        txn('w', 500, cat: kCashCategoryId),
        txn('p', 800, cat: 'sys:food', covered: 800),
      ];
      final t = aggregateCycle(cycle, x, const [])[egp]!;
      expect(t.spend.minor, 500);
      expect(t.byCategoryMinor[kCashCategoryId], 0);
      expect(t.coveredEarlier.minor, 300);
    });

    test('netSpendByDay counts the uncovered part only', () {
      final x = [txn('p', 300, cat: 'sys:food', covered: 100)];
      expect(netSpendByDay(cycle, x, const [], egp), {10: 200});
    });
  });
}
