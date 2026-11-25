// T-245: the pure card-due rules. Synthetic amounts and dates.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/accounts/domain/card_due.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

CardDue due({
  int at = 1000,
  int? amt = 10000,
  int? min = 4000,
  CivilDate? date,
  CivilDate? stmt,
  String cur = 'EGP',
  int paid = 0,
}) => CardDue(
  currency: cur,
  noticeAtMs: at,
  amountDueMinor: amt,
  minDueMinor: min,
  dueDate: date ?? CivilDate(2026, 11, 25),
  statementDate: stmt ?? CivilDate(2026, 11, 1),
  paidMinor: paid,
);

CardDue? pay(
  CardDue d,
  int minor, {
  String id = 't1',
  CivilDate? on,
  String cur = 'EGP',
}) => applyPayment(
  d,
  txnId: id,
  amountMinor: minor,
  currency: cur,
  paidOn: on ?? CivilDate(2026, 11, 10),
  noticeDay: CivilDate(2026, 11, 2),
);

void main() {
  group('mergeNotice', () {
    test('first notice is stored', () {
      expect(mergeNotice(null, due())!.noticeAtMs, 1000);
    });

    test('a newer notice replaces an older one', () {
      final m = mergeNotice(
        due(),
        due(at: 2000, amt: 20000, date: CivilDate(2026, 12, 25)),
      )!;
      expect(m.amountDueMinor, 20000);
      expect(m.dueDate, CivilDate(2026, 12, 25));
    });

    test('an older notice never replaces a newer one', () {
      expect(mergeNotice(due(at: 2000), due(at: 1999, amt: 1)), isNull);
    });

    test('an equal-time notice is a duplicate and is rejected', () {
      expect(mergeNotice(due(), due(amt: 5)), isNull);
    });

    test('a newer reminder for the same due date keeps min, statement date '
        'and the payments counted', () {
      final m = mergeNotice(
        due(paid: 1500),
        CardDue(
          currency: 'EGP',
          noticeAtMs: 3000,
          amountDueMinor: 10000,
          dueDate: CivilDate(2026, 11, 25),
        ),
      )!;
      expect(m.minDueMinor, 4000);
      expect(m.statementDate, CivilDate(2026, 11, 1));
      expect(m.paidMinor, 1500);
      expect(m.applied, isFalse);
    });

    test('a newer notice for another due date starts clean', () {
      final m = mergeNotice(
        due(paid: 4000),
        due(at: 3000, date: CivilDate(2026, 12, 25)),
      )!;
      expect(m.paidMinor, 0);
    });
  });

  group('applyPayment', () {
    test('a payment below the minimum is recorded but not paid', () {
      final d = pay(due(), 1000)!;
      expect(d.paidMinor, 1000);
      expect(d.isPaid, isFalse);
      expect(d.remainingMinor, 3000);
    });

    test('payments add up to the minimum, then it is paid', () {
      final a = pay(due(), 1000)!;
      final b = pay(a, 3000, id: 't2')!;
      expect(b.isPaid, isTrue);
      expect(b.remainingMinor, isNull);
    });

    test('covering the minimum only is paid; the total is not required', () {
      expect(pay(due(), 4000)!.isPaid, isTrue);
    });

    test('with no minimum the total must be covered', () {
      final d = due(min: null);
      expect(pay(d, 4000)!.isPaid, isFalse);
      expect(pay(d, 10000)!.isPaid, isTrue);
    });

    test('with neither amount known it is never paid', () {
      final d = due(amt: null, min: null);
      expect(pay(d, 99999999)!.isPaid, isFalse);
      expect(d.remainingMinor, isNull);
    });

    test('before the statement date it does not count', () {
      expect(pay(due(), 5000, on: CivilDate(2026, 10, 31)), isNull);
      expect(pay(due(), 5000, on: CivilDate(2026, 11, 1)), isNotNull);
    });

    test('without a statement date the notice day is the start', () {
      final d = CardDue(
        currency: 'EGP',
        noticeAtMs: 1,
        minDueMinor: 100,
        dueDate: CivilDate(2026, 11, 25),
      );
      expect(pay(d, 100, on: CivilDate(2026, 11, 1)), isNull);
      expect(pay(d, 100, on: CivilDate(2026, 11, 2)), isNotNull);
    });

    test('another currency, zero, a repeated txn and a paid due do not '
        'count', () {
      expect(pay(due(), 5000, cur: 'USD'), isNull);
      expect(pay(due(), 0), isNull);
      final once = pay(due(), 1000)!;
      expect(pay(once, 1000), isNull);
      expect(pay(due(paid: 4000), 100, id: 'x'), isNull);
    });
  });

  group('codec', () {
    test('round trips', () {
      final d = due(paid: 5).copyWith(paidTxnIds: ['a'], applied: true);
      final back = CardDue.decode(d.encode())!;
      expect(back.encode(), d.encode());
      expect(back.dueDate, CivilDate(2026, 11, 25));
    });

    test('garbage reads as no due', () {
      for (final s in [null, '', 'x', '[]', '{"v":2}', '{"v":1,"cur":"x"}']) {
        expect(CardDue.decode(s), isNull);
      }
    });

    test('key is settings-safe', () {
      expect(cardDueKey('CIB', '1234'), 'card_due.cib.1234');
      expect(cardDueKey('a-b c', '12'), 'card_due.a_b_c.12');
      expect(cardDueKey('x' * 80, '1234').length, lessThanOrEqualTo(64));
    });
  });
}
