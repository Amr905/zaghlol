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
  group('detectRecurring (T-196, D-72)', () {
    // Monthly charges: three are needed.
    List<RecurringChain> detect(
      List<RecurringCharge> charges, {
      CivilDate? today,
      Set<String> exclude = const {},
    }) => detectRecurring(
      charges,
      today: today ?? CivilDate(2026, 10, 20),
      exclude: exclude,
    );

    test('Netflix-like history yields exactly one monthly chain', () {
      final out = detect([
        ch('c1', CivilDate(2026, 8, 5), 19900),
        ch('c2', CivilDate(2026, 9, 5), 19900),
        ch('c3', CivilDate(2026, 10, 5), 21000),
        ch('noise', CivilDate(2026, 10, 7), 5000, merchant: 'cafe'),
      ]);
      expect(out, hasLength(1));
      final s = out.single;
      expect(s.merchantNorm, 'streamco');
      expect(s.cadence, RecurrenceCadence.monthly);
      expect(s.chargeIds, ['c1', 'c2', 'c3']);
      expect(s.amount, m(21000));
      expect(s.annualCost, m(21000 * 12));
      expect(s.nextDue, CivilDate(2026, 11, 5));
      expect(s.dueDay, 5);
    });

    test('monthly needs 3 charges; 2 are not enough', () {
      expect(
        detect([
          ch('c1', CivilDate(2026, 9, 5), 100),
          ch('c2', CivilDate(2026, 10, 5), 100),
        ]),
        isEmpty,
      );
      expect(detect([ch('c1', CivilDate(2026, 10, 5), 100)]), isEmpty);
    });

    test('3-month chain: 3 charges, next due 3 months on, x4 a year', () {
      final out = detect([
        ch('a', CivilDate(2026, 1, 10), 30000),
        ch('b', CivilDate(2026, 4, 10), 30000), // 90 days
        ch('c', CivilDate(2026, 7, 10), 30000), // 91 days
      ], today: CivilDate(2026, 8, 1));
      final s = out.single;
      expect(s.cadence, RecurrenceCadence.quarterly);
      expect(s.nextDue, CivilDate(2026, 10, 10));
      expect(s.annualCost, m(120000));
      expect(s.chargeIds, ['a', 'b', 'c']);
    });

    test('3-month: two charges are not enough', () {
      expect(
        detect([
          ch('b', CivilDate(2026, 4, 10), 30000),
          ch('c', CivilDate(2026, 7, 10), 30000),
        ], today: CivilDate(2026, 8, 1)),
        isEmpty,
      );
    });

    test('6-month chain: 2 charges are enough, x2 a year', () {
      final out = detect([
        ch('a', CivilDate(2026, 1, 15), 90000),
        ch('b', CivilDate(2026, 7, 15), 90000), // 181 days
      ], today: CivilDate(2026, 8, 1));
      final s = out.single;
      expect(s.cadence, RecurrenceCadence.semiAnnual);
      expect(s.nextDue, CivilDate(2027, 1, 15));
      expect(s.annualCost, m(180000));
    });

    test('12-month chain: 2 charges are enough, x1 a year, leap year', () {
      final out = detect([
        ch('a', CivilDate(2024, 3, 3), 250000),
        ch('b', CivilDate(2025, 3, 3), 250000), // 365 days
        ch('c', CivilDate(2026, 3, 3), 260000),
      ], today: CivilDate(2026, 10, 1));
      final s = out.single;
      expect(s.cadence, RecurrenceCadence.yearly);
      expect(s.chargeIds, ['a', 'b', 'c']);
      expect(s.nextDue, CivilDate(2027, 3, 3));
      expect(s.annualCost, m(260000));
      // A 366-day gap (over a leap day) is still yearly.
      expect(
        detect([
          ch('x', CivilDate(2023, 3, 3), 1000),
          ch('y', CivilDate(2024, 3, 3), 1000),
        ], today: CivilDate(2025, 3, 1)).single.cadence,
        RecurrenceCadence.yearly,
      );
    });

    test('FU-143: 31st charges that landed on the 28th keep anchor 31', () {
      final out = detect([
        ch('c0', CivilDate(2025, 12, 31), 10000),
        ch('c1', CivilDate(2026, 1, 31), 10000),
        ch('c2', CivilDate(2026, 2, 28), 10000),
      ], today: CivilDate(2026, 3, 5));
      expect(out.single.dueDay, 31);
      expect(out.single.nextDue, CivilDate(2026, 3, 31));
    });

    test('charge on the 31st: next due clamps to month end', () {
      final out = detect([
        ch('a', CivilDate(2026, 1, 31), 1000),
        ch('b', CivilDate(2026, 2, 28), 1000), // 28 days
        ch('c', CivilDate(2026, 3, 31), 1000), // 31 days
      ], today: CivilDate(2026, 4, 5));
      expect(out.single.nextDue, CivilDate(2026, 4, 30));
      expect(out.single.dueDay, 31);
    });

    test('gap windows: monthly 25..35, quarterly 84..97, 6-month 176..189, '
        'yearly 360..371; anything between is not a chain', () {
      final base = CivilDate(2025, 1, 1);
      RecurrenceCadence? cadenceOf(int gap) {
        // Enough earlier charges for the 3-charge cadences.
        final a = base;
        final b = a.plusDays(gap);
        final c = b.plusDays(gap);
        final out = detectRecurring([
          ch('a', a, 1000),
          ch('b', b, 1000),
          ch('c', c, 1000),
        ], today: c.plusDays(1));
        return out.isEmpty ? null : out.single.cadence;
      }

      for (final (gap, want) in <(int, RecurrenceCadence?)>[
        (24, null),
        (25, RecurrenceCadence.monthly),
        (35, RecurrenceCadence.monthly),
        (36, null),
        (60, null),
        (83, null),
        (84, RecurrenceCadence.quarterly),
        (97, RecurrenceCadence.quarterly),
        (98, null),
        (175, null),
        (176, RecurrenceCadence.semiAnnual),
        (189, RecurrenceCadence.semiAnnual),
        (190, null),
        (359, null),
        (360, RecurrenceCadence.yearly),
        (371, RecurrenceCadence.yearly),
        (372, null),
      ]) {
        expect(cadenceOf(gap), want, reason: 'gap $gap');
      }
    });

    test('irregular gaps are not a chain', () {
      expect(
        detect([
          ch('a', CivilDate(2026, 3, 1), 1000),
          ch('b', CivilDate(2026, 4, 20), 1000), // 50 days
          ch('c', CivilDate(2026, 5, 25), 1000), // 35 days
          ch('d', CivilDate(2026, 8, 1), 1000), // 68 days
        ]),
        isEmpty,
      );
    });

    test('mixed gaps stop the walk at the first gap outside the window', () {
      // Quarterly latest gap, then a monthly-sized gap before it: only 2
      // charges are in the chain, so no 3-month chain.
      expect(
        detect([
          ch('a', CivilDate(2026, 3, 1), 1000),
          ch('b', CivilDate(2026, 4, 1), 1000),
          ch('c', CivilDate(2026, 7, 1), 1000),
        ], today: CivilDate(2026, 8, 1)),
        isEmpty,
      );
    });

    test('amount tolerance is 10% inclusive, integer math', () {
      bool hit(int third) => detect([
        ch('a', CivilDate(2026, 8, 1), 10000),
        ch('b', CivilDate(2026, 9, 1), 10000),
        ch('c', CivilDate(2026, 10, 2), third),
      ]).isNotEmpty;
      expect(hit(11000), isTrue);
      expect(hit(9000), isTrue);
      expect(hit(11001), isFalse);
      expect(hit(8999), isFalse);
    });

    test('a chain that broke before the latest charge gives nothing', () {
      expect(
        detect([
          ch('a', CivilDate(2026, 1, 1), 1000),
          ch('b', CivilDate(2026, 2, 1), 1000),
          ch('c', CivilDate(2026, 3, 1), 1000),
          ch('d', CivilDate(2026, 6, 20), 1000), // 111 days later
        ]),
        isEmpty,
      );
    });

    test('stale chains (stopped plans) are not added', () {
      final charges = [
        ch('a', CivilDate(2025, 1, 5), 1000),
        ch('b', CivilDate(2026, 1, 5), 1000),
      ];
      // Next due 2027-01-05: fine in 2026, but a plan last seen 18 months ago
      // has lapsed.
      expect(detect(charges, today: CivilDate(2026, 10, 1)), hasLength(1));
      expect(detect(charges, today: CivilDate(2027, 1, 15)), hasLength(1));
      expect(detect(charges, today: CivilDate(2027, 1, 16)), isEmpty);
      final monthly = [
        ch('a', CivilDate(2026, 1, 5), 1000),
        ch('b', CivilDate(2026, 2, 5), 1000),
        ch('c', CivilDate(2026, 3, 5), 1000),
      ];
      expect(detect(monthly, today: CivilDate(2026, 4, 15)), hasLength(1));
      expect(detect(monthly, today: CivilDate(2026, 4, 16)), isEmpty);
    });

    test('different merchants do not chain together', () {
      expect(
        detect([
          ch('a', CivilDate(2026, 8, 1), 1000, merchant: 'one'),
          ch('b', CivilDate(2026, 9, 1), 1000, merchant: 'two'),
          ch('c', CivilDate(2026, 10, 1), 1000, merchant: 'three'),
        ]),
        isEmpty,
      );
    });

    test('input order does not matter', () {
      final a = ch('a', CivilDate(2026, 8, 1), 1000);
      final b = ch('b', CivilDate(2026, 9, 1), 1000);
      final c = ch('c', CivilDate(2026, 10, 1), 1000);
      expect(
        detect([c, a, b]).single.chargeIds,
        detect([a, b, c]).single.chargeIds,
      );
    });

    test('currencies and accounts never mix', () {
      final out = detect([
        ch('a', CivilDate(2026, 8, 1), 1000),
        ch('b', CivilDate(2026, 9, 1), 1000, currency: usd),
        ch('c', CivilDate(2026, 10, 1), 1000, account: 'a2'),
      ]);
      expect(out, isEmpty);
      // Same merchant in two currencies: one chain each, never summed.
      final both = detect([
        for (var i = 0; i < 3; i++) ch('e$i', CivilDate(2026, 8 + i, 1), 1000),
        for (var i = 0; i < 3; i++)
          ch('u$i', CivilDate(2026, 8 + i, 1), 900, currency: usd),
      ]);
      expect(both, hasLength(2));
      expect({for (final s in both) s.amount.currency.code}, {'EGP', 'USD'});
    });

    test('excluded keys (existing, dismissed or undone) stay quiet', () {
      final charges = [
        ch('a', CivilDate(2026, 8, 1), 1000),
        ch('b', CivilDate(2026, 9, 1), 1000),
        ch('c', CivilDate(2026, 10, 1), 1000),
      ];
      expect(detect(charges), hasLength(1));
      expect(
        detect(charges, exclude: {recurringKey('streamco', 'a1', 'EGP')}),
        isEmpty,
      );
      // An entry without an account blocks every account of that merchant
      // and currency, but not another currency.
      expect(
        detect(charges, exclude: {recurringKey('streamco', '', 'EGP')}),
        isEmpty,
      );
      expect(
        detect(charges, exclude: {recurringKey('streamco', '', 'USD')}),
        hasLength(1),
      );
    });

    test('rent, electricity, installments, insurance, subscriptions ARE '
        'added; groceries, dining, transport, cash, income are not', () {
      RecurringCharge withCat(String id, CivilDate d, String? cat) =>
          RecurringCharge(
            id: id,
            merchantNorm: 'landlord',
            accountId: 'a1',
            amount: m(500000),
            date: d,
            categoryId: cat,
          );
      List<RecurringCharge> three(String? cat) => [
        withCat('a', CivilDate(2026, 8, 1), cat),
        withCat('b', CivilDate(2026, 9, 1), cat),
        withCat('c', CivilDate(2026, 10, 1), cat),
      ];
      for (final cat in [
        'sys:rent',
        'sys:housing',
        'sys:bills',
        'sys:utilities',
        'sys:electricity',
        'sys:installments',
        'sys:education',
        'sys:insurance',
        'sys:subscriptions',
        'sys:entertainment',
        'sys:instapay', // rent and bills are often paid by InstaPay
        null,
      ]) {
        expect(detect(three(cat)), hasLength(1), reason: '$cat');
      }
      for (final cat in [
        'sys:groceries',
        'dining',
        'sys:transport',
        'sys:cash',
        'sys:income',
      ]) {
        expect(detect(three(cat)), isEmpty, reason: cat);
      }
    });

    test('zero amounts and unstorable merchant keys are ignored', () {
      expect(
        detect([
          for (var i = 0; i < 3; i++) ch('z$i', CivilDate(2026, 8 + i, 1), 0),
          for (var i = 0; i < 3; i++)
            ch('b$i', CivilDate(2026, 8 + i, 1), 5, merchant: 'Bad Name'),
        ]),
        isEmpty,
      );
    });

    test('annual cost uses the currency exponent (KWD has 3)', () {
      final kwd = Currency.of('KWD');
      final out = detect([
        for (var i = 0; i < 3; i++)
          ch('k$i', CivilDate(2026, 8 + i, 1), 1500, currency: kwd),
      ]);
      expect(out.single.annualCost, Money(kwd, 18000));
    });
  });

  group('advanceDue for the months cadences (T-196)', () {
    CivilDate next(RecurrenceCadence c, CivilDate from, [int? day]) =>
        advanceDue(from, cadence: c, dueDay: day ?? from.day);

    test('quarterly: month ends clamp, year rolls over', () {
      expect(
        next(RecurrenceCadence.quarterly, CivilDate(2026, 11, 30)),
        CivilDate(2027, 2, 28),
      );
      expect(
        next(RecurrenceCadence.quarterly, CivilDate(2026, 11, 30), 31),
        CivilDate(2027, 2, 28),
      );
      expect(
        next(RecurrenceCadence.quarterly, CivilDate(2027, 2, 28), 31),
        CivilDate(2027, 5, 31),
      );
      expect(
        next(RecurrenceCadence.quarterly, CivilDate(2028, 11, 30), 30),
        CivilDate(2029, 2, 28),
      );
      expect(
        next(RecurrenceCadence.quarterly, CivilDate(2027, 11, 29), 29),
        CivilDate(2028, 2, 29),
      );
      expect(
        next(RecurrenceCadence.quarterly, CivilDate(2026, 1, 31), 31),
        CivilDate(2026, 4, 30),
      );
    });

    test('semi-annual: 31st goes to 30th and 28th, year rolls over', () {
      expect(
        next(RecurrenceCadence.semiAnnual, CivilDate(2026, 8, 31), 31),
        CivilDate(2027, 2, 28),
      );
      expect(
        next(RecurrenceCadence.semiAnnual, CivilDate(2027, 2, 28), 31),
        CivilDate(2027, 8, 31),
      );
      expect(
        next(RecurrenceCadence.semiAnnual, CivilDate(2026, 10, 31), 31),
        CivilDate(2027, 4, 30),
      );
      expect(
        next(RecurrenceCadence.semiAnnual, CivilDate(2026, 12, 15)),
        CivilDate(2027, 6, 15),
      );
      expect(
        next(RecurrenceCadence.semiAnnual, CivilDate(2027, 8, 31), 31),
        CivilDate(2028, 2, 29),
      );
    });

    test('yearly with an anchor of 29 returns to 29 after a leap year', () {
      expect(
        next(RecurrenceCadence.yearly, CivilDate(2028, 2, 29), 29),
        CivilDate(2029, 2, 28),
      );
      expect(
        next(RecurrenceCadence.yearly, CivilDate(2029, 2, 28), 29),
        CivilDate(2030, 2, 28),
      );
      expect(
        next(RecurrenceCadence.yearly, CivilDate(2027, 2, 28), 29),
        CivilDate(2028, 2, 29),
      );
    });

    test('monthsPerCycle', () {
      expect(
        {for (final c in RecurrenceCadence.values) c: c.monthsPerCycle},
        {
          RecurrenceCadence.monthly: 1,
          RecurrenceCadence.quarterly: 3,
          RecurrenceCadence.semiAnnual: 6,
          RecurrenceCadence.yearly: 12,
          RecurrenceCadence.weekly: null,
          RecurrenceCadence.customDays: null,
        },
      );
    });

    test('progressAfterPayment moves a quarterly item on by 3 months', () {
      final p = progressAfterPayment(
        paidCount: 0,
        totalCount: null,
        dueDate: CivilDate(2026, 11, 30),
        cadence: RecurrenceCadence.quarterly,
        dueDay: 30,
      );
      expect(p.nextDue, CivilDate(2027, 2, 28));
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
