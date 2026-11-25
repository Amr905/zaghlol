import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

PaydayCredit c(int y, int m, int d, [String cur = 'EGP']) =>
    PaydayCredit(CivilDate(y, m, d), cur);

PaydayDetection run(
  List<PaydayCredit> credits, {
  int? current,
  bool typed = false,
}) => detectPayday(
  credits: credits,
  currency: 'EGP',
  currentPayday: current,
  typedByUser: typed,
);

void main() {
  group('detectPayday', () {
    test('24 Sep, 23 Oct, 24 Nov -> 23 (earliest wins)', () {
      final r = run([c(2026, 9, 24), c(2026, 10, 23), c(2026, 11, 24)]);
      expect(r, const PaydayDetection(day: 23, apply: true, salaryDay: 23));
    });

    test('25 and 5 of the next month are one month: 25 wins', () {
      final r = run([
        c(2026, 8, 25),
        c(2026, 9, 5),
        c(2026, 9, 25),
        c(2026, 10, 5),
        c(2026, 10, 25),
        c(2026, 11, 5),
      ]);
      expect(r.day, 25);
    });

    test('several salaries in a month: only the first counts', () {
      final r = run([
        c(2026, 9, 10),
        c(2026, 9, 18),
        c(2026, 10, 10),
        c(2026, 10, 19),
        c(2026, 11, 11),
        c(2026, 11, 20),
      ]);
      expect(r.day, 10);
    });

    test('30 Oct, 31 Nov(30), 29 Dec -> 28', () {
      final r = run([c(2026, 10, 30), c(2026, 11, 30), c(2026, 12, 29)]);
      expect(r, const PaydayDetection(day: 28, apply: true, salaryDay: 29));
    });

    test('typed 1 with 23/24/23 -> 23', () {
      final r = run(
        [c(2026, 9, 23), c(2026, 10, 24), c(2026, 11, 23)],
        current: 1,
        typed: true,
      );
      expect(r, const PaydayDetection(day: 23, apply: true, salaryDay: 23));
    });

    test('FU-296 m-3: month-end weekend shifts 28 / 30 / 1 agree', () {
      // 28 Oct (30th was a Friday off), 30 Nov, 1 Jan: capped 28, 28, 1.
      final r = run([c(2026, 10, 28), c(2026, 11, 30), c(2027, 1, 1)]);
      expect(r, const PaydayDetection(day: 28, apply: true, salaryDay: 28));
    });

    test('FU-296 m-3: 31 / 1 / 2 agree and the 28 start wins', () {
      final r = run([c(2026, 8, 31), c(2026, 10, 1), c(2026, 11, 2)]);
      expect(r.day, 28);
      expect(r.apply, isTrue);
    });

    test('FU-296 m-3: 26 and 3 are too far apart across the month end', () {
      expect(
        run([c(2026, 9, 26), c(2026, 10, 26), c(2026, 12, 3)]),
        const PaydayDetection(),
      );
    });

    test('FU-296 m-3: typed 28 with 1/1/2 agrees across the month end', () {
      final r = run(
        [c(2026, 9, 1), c(2026, 10, 1), c(2026, 11, 2)],
        current: 28,
        typed: true,
      );
      expect(r.apply, isFalse);
    });

    test('FU-296 m-6: salaryDay is the real day behind a capped payday', () {
      final r = run([c(2026, 10, 31), c(2026, 11, 30), c(2026, 12, 30)]);
      expect(r.day, 28);
      expect(r.salaryDay, 30);
    });

    test('typed 1 with 23/1/24 stays 1', () {
      final r = run(
        [c(2026, 9, 23), c(2026, 11, 1), c(2026, 11, 24)],
        current: 1,
        typed: true,
      );
      expect(r.apply, isFalse);
    });

    test('typed 1 with 1/2/23 disagreeing months: no pattern, stays', () {
      final r = run(
        [c(2026, 9, 1), c(2026, 10, 2), c(2026, 11, 23)],
        current: 1,
        typed: true,
      );
      expect(r.apply, isFalse);
    });

    test('typed 25 and pattern 23/24/23 agrees (within 2): stays', () {
      final r = run(
        [c(2026, 9, 23), c(2026, 10, 24), c(2026, 11, 23)],
        current: 25,
        typed: true,
      );
      expect(r.apply, isFalse);
    });

    test('two months and never set -> set', () {
      final r = run([c(2026, 10, 23), c(2026, 11, 24)]);
      expect(r, const PaydayDetection(day: 23, apply: true, salaryDay: 23));
    });

    test('one month and never set -> set', () {
      expect(run([c(2026, 11, 5)]).apply, isTrue);
    });

    test('two months but a payday exists: wait for the pattern', () {
      final r = run([c(2026, 10, 23), c(2026, 11, 24)], current: 1);
      expect(r.apply, isFalse);
    });

    test('auto/default payday follows a 3-month pattern', () {
      final r = run([
        c(2026, 9, 10),
        c(2026, 10, 10),
        c(2026, 11, 10),
      ], current: 1);
      expect(r, const PaydayDetection(day: 10, apply: true, salaryDay: 10));
    });

    test('auto payday within 2 days of the pattern is not flipped', () {
      final r = run([
        c(2026, 9, 10),
        c(2026, 10, 10),
        c(2026, 11, 10),
      ], current: 11);
      expect(r.apply, isFalse);
    });

    test('only the latest 3 months count', () {
      final r = run([
        c(2026, 5, 3),
        c(2026, 6, 3),
        c(2026, 9, 12),
        c(2026, 10, 12),
        c(2026, 11, 12),
      ]);
      expect(r.day, 12);
    });

    test('other currencies are ignored; none -> nothing', () {
      expect(run([c(2026, 11, 5, 'USD')]), const PaydayDetection());
      expect(run(const []), const PaydayDetection());
    });

    test('property: detected day is always 1..28 and apply implies day', () {
      for (var d1 = 1; d1 <= 31; d1++) {
        for (var d2 = 1; d2 <= 31; d2++) {
          final r = run([
            c(2026, 8, d1.clamp(1, 31)),
            c(2026, 10, d2.clamp(1, 30)),
            c(2026, 12, d1.clamp(1, 31)),
          ]);
          if (r.apply) {
            expect(r.day, allOf(greaterThanOrEqualTo(1), lessThan(29)));
          }
          if (r.day != null) {
            expect(r.day, inInclusiveRange(1, 28));
          }
        }
      }
    });
  });

  group('PaydayAutoState', () {
    test('json round trip and bad input', () {
      const s = PaydayAutoState(
        autoDay: 23,
        previous: 1,
        bannerPending: true,
        suppressed: [5, 7],
      );
      final back = PaydayAutoState.fromJson(s.toJson())!;
      expect(back.autoDay, 23);
      expect(back.previous, 1);
      expect(back.bannerPending, isTrue);
      expect(back.suppressed, [5, 7]);
      expect(back.salaryDay, isNull);
      final withDay = PaydayAutoState.fromJson(
        const PaydayAutoState(autoDay: 28, salaryDay: 30).toJson(),
      )!;
      expect(withDay.salaryDay, 30);
      expect(
        PaydayAutoState.fromJson('{"v":1,"a":28,"d":32,"b":true,"s":[]}'),
        isNull,
      );
      expect(PaydayAutoState.fromJson('nope'), isNull);
      expect(
        PaydayAutoState.fromJson('{"v":1,"a":40,"b":true,"s":[]}'),
        isNull,
      );
    });

    test('typedBy and suppression cap', () {
      const s = PaydayAutoState(autoDay: 23);
      expect(s.typedBy(23), isFalse);
      expect(s.typedBy(1), isTrue);
      expect(s.typedBy(null), isFalse);
      var x = PaydayAutoState.empty;
      for (var i = 1; i <= 12; i++) {
        x = x.withSuppressed(i);
      }
      expect(x.suppressed.length, paydayMaxSuppressed);
      expect(x.suppressed.last, 12);
    });
  });
}
