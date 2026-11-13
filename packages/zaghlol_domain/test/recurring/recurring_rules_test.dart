// T-096: domain rules for recurring money. Synthetic data only.

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

Money m(int minor, [Currency? c]) => Money(c ?? egp, minor);

RecurringCharge ch(
  String id,
  CivilDate d,
  int minor, {
  String merchant = 'streamco',
  String account = 'a1',
  Currency? currency,
}) => RecurringCharge(
  id: id,
  merchantNorm: merchant,
  accountId: account,
  amount: m(minor, currency),
  date: d,
);

void main() {
  group('detectSubscriptions', () {
    test('Netflix-like history yields exactly one suggestion', () {
      final out = detectSubscriptions([
        ch('c1', CivilDate(2026, 8, 5), 19900),
        ch('c2', CivilDate(2026, 9, 5), 19900),
        ch('c3', CivilDate(2026, 10, 5), 21000),
        ch('noise', CivilDate(2026, 10, 7), 5000, merchant: 'cafe'),
      ]);
      expect(out, hasLength(1));
      final s = out.single;
      expect(s.merchantNorm, 'streamco');
      expect(s.chargeIds, ['c1', 'c2', 'c3']);
      expect(s.amount, m(21000));
      expect(s.annualCost, m(21000 * 12));
      expect(s.nextDue, CivilDate(2026, 11, 5));
      expect(s.dueDay, 5);
    });

    test('one charge is not enough; two are', () {
      expect(
        detectSubscriptions([ch('c1', CivilDate(2026, 9, 5), 100)]),
        isEmpty,
      );
      expect(
        detectSubscriptions([
          ch('c1', CivilDate(2026, 9, 5), 100),
          ch('c2', CivilDate(2026, 10, 5), 100),
        ]),
        hasLength(1),
      );
    });

    test('gap boundaries 25 and 35 days are in; 24 and 36 are out', () {
      final base = CivilDate(2026, 1, 1);
      bool hit(int gap) => detectSubscriptions([
        ch('a', base, 1000),
        ch('b', base.plusDays(gap), 1000),
      ]).isNotEmpty;
      expect(hit(24), isFalse);
      expect(hit(25), isTrue);
      expect(hit(35), isTrue);
      expect(hit(36), isFalse);
    });

    test('amount tolerance is 10% inclusive, integer math', () {
      bool hit(int second) => detectSubscriptions([
        ch('a', CivilDate(2026, 1, 1), 10000),
        ch('b', CivilDate(2026, 2, 1), second),
      ]).isNotEmpty;
      expect(hit(11000), isTrue);
      expect(hit(9000), isTrue);
      expect(hit(11001), isFalse);
      expect(hit(8999), isFalse);
    });

    test('a chain that broke before the latest charge gives nothing', () {
      final out = detectSubscriptions([
        ch('a', CivilDate(2026, 1, 1), 1000),
        ch('b', CivilDate(2026, 2, 1), 1000),
        ch('c', CivilDate(2026, 6, 1), 1000), // 120 days later
      ]);
      expect(out, isEmpty);
    });

    test('input order does not matter', () {
      final a = ch('a', CivilDate(2026, 1, 1), 1000);
      final b = ch('b', CivilDate(2026, 2, 1), 1000);
      final c = ch('c', CivilDate(2026, 3, 1), 1000);
      expect(
        detectSubscriptions([c, a, b]).single.chargeIds,
        detectSubscriptions([a, b, c]).single.chargeIds,
      );
    });

    test('currencies and accounts never mix', () {
      final out = detectSubscriptions([
        ch('a', CivilDate(2026, 1, 1), 1000),
        ch('b', CivilDate(2026, 2, 1), 1000, currency: usd),
        ch('c', CivilDate(2026, 2, 1), 1000, account: 'a2'),
      ]);
      expect(out, isEmpty);
    });

    test('excluded keys (existing or dismissed items) stay quiet', () {
      final charges = [
        ch('a', CivilDate(2026, 1, 1), 1000),
        ch('b', CivilDate(2026, 2, 1), 1000),
      ];
      expect(
        detectSubscriptions(
          charges,
          exclude: {recurringKey('streamco', 'a1', 'EGP')},
        ),
        isEmpty,
      );
    });

    test('zero amounts and unstorable merchant keys are ignored', () {
      expect(
        detectSubscriptions([
          ch('a', CivilDate(2026, 1, 1), 0),
          ch('b', CivilDate(2026, 2, 1), 0),
          ch('c', CivilDate(2026, 1, 1), 5, merchant: 'Bad Name'),
          ch('d', CivilDate(2026, 2, 1), 5, merchant: 'Bad Name'),
        ]),
        isEmpty,
      );
    });

    test('annual cost uses the currency exponent (KWD has 3)', () {
      final kwd = Currency.of('KWD');
      final out = detectSubscriptions([
        ch('a', CivilDate(2026, 1, 1), 1500, currency: kwd),
        ch('b', CivilDate(2026, 2, 1), 1500, currency: kwd),
      ]);
      expect(out.single.annualCost, Money(kwd, 18000));
    });

    test('charge on the 31st: next due clamps to month end', () {
      final out = detectSubscriptions([
        ch('a', CivilDate(2026, 1, 31), 1000),
        ch('b', CivilDate(2026, 2, 28), 1000), // 28 days
        ch('c', CivilDate(2026, 3, 31), 1000), // 31 days
      ]);
      expect(out.single.nextDue, CivilDate(2026, 4, 30));
      expect(out.single.dueDay, 31);
    });
  });

  group('advanceDue / nextDueOnOrAfter', () {
    test('monthly keeps the anchor day and clamps', () {
      expect(
        advanceDue(
          CivilDate(2026, 1, 31),
          cadence: RecurrenceCadence.monthly,
          dueDay: 31,
        ),
        CivilDate(2026, 2, 28),
      );
      expect(
        advanceDue(
          CivilDate(2026, 2, 28),
          cadence: RecurrenceCadence.monthly,
          dueDay: 31,
        ),
        CivilDate(2026, 3, 31),
      );
      expect(
        advanceDue(
          CivilDate(2028, 1, 30),
          cadence: RecurrenceCadence.monthly,
          dueDay: 30,
        ),
        CivilDate(2028, 2, 29),
      );
      expect(
        advanceDue(
          CivilDate(2026, 12, 15),
          cadence: RecurrenceCadence.monthly,
          dueDay: 15,
        ),
        CivilDate(2027, 1, 15),
      );
    });

    test('yearly, weekly and custom days', () {
      expect(
        advanceDue(CivilDate(2028, 2, 29), cadence: RecurrenceCadence.yearly),
        CivilDate(2029, 2, 28),
      );
      expect(
        advanceDue(CivilDate(2026, 12, 28), cadence: RecurrenceCadence.weekly),
        CivilDate(2027, 1, 4),
      );
      expect(
        advanceDue(
          CivilDate(2026, 1, 1),
          cadence: RecurrenceCadence.customDays,
          days: 45,
        ),
        CivilDate(2026, 2, 15),
      );
      expect(
        () => advanceDue(
          CivilDate(2026, 1, 1),
          cadence: RecurrenceCadence.customDays,
        ),
        throwsArgumentError,
      );
    });

    test('card statement due day', () {
      expect(
        nextDueOnOrAfter(CivilDate(2026, 11, 13), 20),
        CivilDate(2026, 11, 20),
      );
      expect(
        nextDueOnOrAfter(CivilDate(2026, 11, 20), 20),
        CivilDate(2026, 11, 20),
      );
      expect(
        nextDueOnOrAfter(CivilDate(2026, 11, 21), 20),
        CivilDate(2026, 12, 20),
      );
      expect(
        nextDueOnOrAfter(CivilDate(2026, 2, 10), 31),
        CivilDate(2026, 2, 28),
      );
      expect(
        nextDueOnOrAfter(CivilDate(2026, 12, 31), 5),
        CivilDate(2027, 1, 5),
      );
      expect(
        () => nextDueOnOrAfter(CivilDate(2026, 1, 1), 32),
        throwsArgumentError,
      );
    });
  });

  group('matchPayment', () {
    final item = DueItem(
      id: 'i1',
      amount: m(100000),
      dueDate: CivilDate(2026, 11, 10),
      merchantNorm: 'tvshop',
    );
    PaymentCandidate pay(
      String id,
      CivilDate d,
      int minor, {
      String? merchant = 'tvshop',
      Currency? currency,
    }) => PaymentCandidate(
      id: id,
      amount: m(minor, currency),
      date: d,
      merchantNorm: merchant,
    );

    test('a matching payment is found', () {
      expect(
        matchPayment(item, [pay('p', CivilDate(2026, 11, 11), 100000)])!.id,
        'p',
      );
    });

    test('window is 5 days, tolerance 2%, both inclusive', () {
      expect(
        matchPayment(item, [pay('p', CivilDate(2026, 11, 15), 102000)]),
        isNotNull,
      );
      expect(
        matchPayment(item, [pay('p', CivilDate(2026, 11, 5), 98000)]),
        isNotNull,
      );
      expect(
        matchPayment(item, [pay('p', CivilDate(2026, 11, 16), 100000)]),
        isNull,
      );
      expect(
        matchPayment(item, [pay('p', CivilDate(2026, 11, 10), 102001)]),
        isNull,
      );
    });

    test('other merchant, other currency: no match', () {
      expect(
        matchPayment(item, [
          pay('p', CivilDate(2026, 11, 10), 100000, merchant: 'other'),
        ]),
        isNull,
      );
      expect(
        matchPayment(item, [
          pay('p', CivilDate(2026, 11, 10), 100000, currency: usd),
        ]),
        isNull,
      );
    });

    test('closest date wins, independent of input order', () {
      final a = pay('a', CivilDate(2026, 11, 13), 100000);
      final b = pay('b', CivilDate(2026, 11, 11), 100000);
      expect(matchPayment(item, [a, b])!.id, 'b');
      expect(matchPayment(item, [b, a])!.id, 'b');
    });

    test('account rule for an item without a merchant key (card due)', () {
      final card = DueItem(
        id: 'c',
        amount: m(0),
        dueDate: CivilDate(2026, 11, 20),
        accountId: 'card1',
        cardDue: true,
      );
      final p = PaymentCandidate(
        id: 'p',
        amount: m(345600),
        date: CivilDate(2026, 11, 19),
        accountId: 'card1',
        inbound: true,
      );
      expect(matchPayment(card, [p])!.id, 'p');
      expect(
        matchPayment(card, [
          PaymentCandidate(
            id: 'q',
            amount: m(345600),
            date: CivilDate(2026, 11, 19),
            accountId: 'card2',
            inbound: true,
          ),
        ]),
        isNull,
      );
    });

    test('a card due rejects outbound matches, even with amount 0', () {
      final card = DueItem(
        id: 'c',
        amount: m(0),
        dueDate: CivilDate(2026, 11, 20),
        accountId: 'card1',
        cardDue: true,
      );
      final purchase = PaymentCandidate(
        id: 'p',
        amount: m(4500),
        date: CivilDate(2026, 11, 19),
        accountId: 'card1',
      );
      expect(matchPayment(card, [purchase]), isNull);
    });

    test('an unknown amount never matches by merchant alone', () {
      final unknown = DueItem(
        id: 'u',
        amount: m(0),
        dueDate: CivilDate(2026, 11, 10),
        merchantNorm: 'tvshop',
      );
      expect(
        matchPayment(unknown, [pay('p', CivilDate(2026, 11, 10), 5)]),
        isNull,
      );
    });
  });

  group('progressAfterPayment', () {
    test('counts and advances; completes at the total', () {
      final p = progressAfterPayment(
        paidCount: 1,
        totalCount: 3,
        dueDate: CivilDate(2026, 11, 30),
        cadence: RecurrenceCadence.monthly,
        dueDay: 30,
      );
      expect(p.paidCount, 2);
      expect(p.completed, isFalse);
      expect(p.nextDue, CivilDate(2026, 12, 30));
      final last = progressAfterPayment(
        paidCount: 2,
        totalCount: 3,
        dueDate: CivilDate(2026, 12, 30),
        cadence: RecurrenceCadence.monthly,
        dueDay: 30,
      );
      expect(last.completed, isTrue);
      expect(last.paidCount, 3);
      expect(last.nextDue, isNull);
    });

    test('open-ended items never complete', () {
      final p = progressAfterPayment(
        paidCount: 40,
        totalCount: null,
        dueDate: CivilDate(2026, 1, 31),
        cadence: RecurrenceCadence.monthly,
        dueDay: 31,
      );
      expect(p.completed, isFalse);
      expect(p.nextDue, CivilDate(2026, 2, 28));
    });
  });

  group('reminderIsDue', () {
    final due = CivilDate(2026, 11, 20);
    bool at(CivilDate today, int min, {int days = 3}) => reminderIsDue(
      dueDate: due,
      reminderDays: days,
      localToday: today,
      localMinuteOfDay: min,
    );
    test('fires from three days before at 10:00 local', () {
      expect(at(CivilDate(2026, 11, 16), 600), isFalse);
      expect(at(CivilDate(2026, 11, 17), 599), isFalse);
      expect(at(CivilDate(2026, 11, 17), 600), isTrue);
      expect(at(CivilDate(2026, 11, 19), 0), isTrue);
      expect(at(CivilDate(2026, 11, 20), 0), isTrue);
      expect(at(CivilDate(2026, 11, 21), 700), isFalse);
    });
    test('zero reminder days fires on the due day at 10:00', () {
      expect(at(CivilDate(2026, 11, 20), 599, days: 0), isFalse);
      expect(at(CivilDate(2026, 11, 20), 600, days: 0), isTrue);
    });
  });
}
