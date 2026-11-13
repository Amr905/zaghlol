// T-091: split and reimbursement rules, synthetic data only.
import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final kwd = Currency.of('KWD');
Money e(int m) => Money(egp, m);

ExpenseRoom room(String id, int rem, {Map<String, int> parts = const {}}) =>
    ExpenseRoom(
      expenseId: id,
      remaining: e(rem),
      participantRemaining: {for (final p in parts.entries) p.key: e(p.value)},
    );

AllocationRequest req(String id, int m, {String? p}) =>
    AllocationRequest(expenseId: id, amount: e(m), participantId: p);

void main() {
  group('AC1 1,200 bill + 400 + 400 -> net 400', () {
    test('two friends repay, net personal spend is 400', () {
      final first = planReimbursement(
        sourceRemaining: e(40000),
        requests: [req('bill', 40000)],
        rooms: [room('bill', 120000)],
      );
      expect(first.grants.single.granted, e(40000));
      final second = planReimbursement(
        sourceRemaining: e(40000),
        requests: [req('bill', 40000)],
        rooms: [room('bill', 120000 - 40000)],
      );
      expect(second.grants.single.granted, e(40000));
      expect(netOfOffsets(e(120000), e(80000)), e(40000));
    });

    test('shares: own share is the rest and equal split adds up', () {
      expect(ownShare(e(120000), [e(40000), e(40000)]), e(40000));
      final s = equalSplit(e(10000), 3);
      expect(s, [e(3334), e(3333), e(3333)]);
      expect(s.fold<int>(0, (a, b) => a + b.minor), 10000);
      expect(() => equalSplit(e(100), 0), throwsArgumentError);
    });

    test('three-decimal currency stays exact', () {
      final s = equalSplit(Money(kwd, 1000), 3);
      expect(s.map((m) => m.minor), [334, 333, 333]);
    });
  });

  group('BR-XFR-04 net never below zero', () {
    test('offsets above the amount floor at zero', () {
      expect(netOfOffsets(e(100), e(150)), e(0));
      expect(netOfOffsets(e(100), e(0)), e(100));
    });
    test('unsettled share floors at zero', () {
      expect(unsettledShare(e(400), e(150)), e(250));
      expect(unsettledShare(e(400), e(500)), e(0));
    });
  });

  group('shares validation', () {
    test('ok, exceeds, negative, currency', () {
      expect(checkShares(e(1000), [e(400), e(600)]), isNull);
      expect(
        checkShares(e(1000), [e(400), e(601)]),
        ShareProblem.exceedsExpense,
      );
      expect(checkShares(e(1000), [Money(egp, 0)]), isNull);
      expect(
        checkShares(e(1000), [Money(usd, 1)]),
        ShareProblem.currencyMismatch,
      );
    });
    test('negative share rejected', () {
      expect(checkShares(e(1000), [e(-1)]), ShareProblem.negative);
    });
    test('ownShare with shares above amount is zero', () {
      expect(ownShare(e(100), [e(80), e(80)]), e(0));
    });
  });

  group('BR-XFR-06 caps; excess stays income', () {
    test('transfer larger than the expense remaining: excess is income', () {
      final p = planReimbursement(
        sourceRemaining: e(50000),
        requests: [req('a', 50000)],
        rooms: [room('a', 30000)],
      );
      expect(p.grants.single.granted, e(30000));
      expect(p.grants.single.clamped, isTrue);
      expect(p.incomeRemainder, e(20000));
    });

    test('unallocated part of the transfer stays income', () {
      final p = planReimbursement(
        sourceRemaining: e(50000),
        requests: [req('a', 10000)],
        rooms: [room('a', 30000)],
      );
      expect(p.incomeRemainder, e(40000));
      expect(p.grants.single.clamped, isFalse);
    });

    test('EC-39 one transfer across two expenses, in order, capped', () {
      final p = planReimbursement(
        sourceRemaining: e(50000),
        requests: [req('a', 30000), req('b', 30000)],
        rooms: [room('a', 30000), room('b', 40000)],
      );
      expect(p.grants.map((g) => g.granted.minor), [30000, 20000]);
      expect(p.incomeRemainder, e(0));
      final total = p.grants.fold<int>(
        0,
        (int a, GrantedLink g) => a + g.granted.minor,
      );
      expect(total, lessThanOrEqualTo(50000));
    });

    test('source already used up grants nothing', () {
      final p = planReimbursement(
        sourceRemaining: e(0),
        requests: [req('a', 100)],
        rooms: [room('a', 100)],
      );
      expect(p.grants, isEmpty);
      expect(p.rejected.single.reason, RejectReason.noRoom);
    });

    test('expense already fully offset grants nothing', () {
      final p = planReimbursement(
        sourceRemaining: e(100),
        requests: [req('a', 100)],
        rooms: [room('a', 0)],
      );
      expect(p.rejected.single.reason, RejectReason.noRoom);
      expect(p.incomeRemainder, e(100));
    });
  });

  group('EC-37 participant share caps', () {
    test('friend pays more than their share: excess stays income', () {
      final p = planReimbursement(
        sourceRemaining: e(60000),
        requests: [req('a', 60000, p: 'ali')],
        rooms: [
          room('a', 120000, parts: {'ali': 40000}),
        ],
      );
      expect(p.grants.single.granted, e(40000));
      expect(p.incomeRemainder, e(20000));
    });

    test('unknown participant is rejected', () {
      final p = planReimbursement(
        sourceRemaining: e(100),
        requests: [req('a', 100, p: 'zed')],
        rooms: [room('a', 100)],
      );
      expect(p.rejected.single.reason, RejectReason.unknownParticipant);
    });
  });

  group('rejections never rewrite', () {
    test('zero, negative, wrong currency, unknown, duplicate', () {
      final p = planReimbursement(
        sourceRemaining: e(1000),
        requests: [
          req('a', 0),
          req('a', -5),
          AllocationRequest(expenseId: 'a', amount: Money(usd, 5)),
          req('nope', 5),
          req('a', 100),
          req('a', 100),
        ],
        rooms: [room('a', 1000)],
      );
      expect(p.rejected.map((RejectedRequest r) => r.reason), [
        RejectReason.nonPositive,
        RejectReason.nonPositive,
        RejectReason.currencyMismatch,
        RejectReason.unknownExpense,
        RejectReason.duplicateExpense,
      ]);
      expect(p.grants.single.granted, e(100));
      expect(p.incomeRemainder, e(900));
    });

    test('room in another currency is rejected', () {
      final p = planReimbursement(
        sourceRemaining: e(1000),
        requests: [req('a', 100)],
        rooms: [ExpenseRoom(expenseId: 'a', remaining: Money(usd, 1000))],
      );
      expect(p.rejected.single.reason, RejectReason.currencyMismatch);
    });
  });

  group('EC-40 repair removes the newest links first', () {
    LinkFact l(String id, int m, int t) =>
        LinkFact(id: id, amountMinor: m, createdAtMs: t);

    test('nothing to remove when it still fits', () {
      expect(linksToRemove(800, [l('a', 400, 1), l('b', 400, 2)]), isEmpty);
    });
    test('newest goes first until valid', () {
      final links = [l('a', 400, 1), l('b', 400, 2), l('c', 300, 3)];
      expect(linksToRemove(800, links), ['c']);
      expect(linksToRemove(700, links), ['c', 'b']);
      expect(linksToRemove(0, links), ['c', 'b', 'a']);
    });
    test('same time: higher id first, stable', () {
      expect(linksToRemove(400, [l('a', 400, 1), l('b', 400, 1)]), ['b']);
    });
    test('negative new amount treated as zero', () {
      expect(linksToRemove(-1, [l('a', 1, 1)]), ['a']);
    });
  });
}
