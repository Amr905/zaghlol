// T-089: matching rules, synthetic data only.
import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final kwd = Currency.of('KWD');
final jpy = Currency.of('JPY');
final t0 = DateTime.utc(2026, 11, 1, 10);

TransferLeg leg(
  String id,
  String acc, {
  required bool out,
  int minor = 100000,
  Currency? cur,
  Duration at = Duration.zero,
}) => TransferLeg(
  id: id,
  accountId: acc,
  isOut: out,
  amount: Money(cur ?? egp, minor),
  occurredAt: t0.add(at),
);

void main() {
  group('same currency', () {
    test('spec example: -1,000 NBE / +1,000 CIB within 2 min pairs', () {
      final o = leg('o', 'nbe', out: true);
      final i = leg('i', 'cib', out: false, at: const Duration(minutes: 2));
      expect((decideSameCurrency(i, [o]) as PairWith).counterpart.id, 'o');
      expect((decideSameCurrency(o, [i]) as PairWith).counterpart.id, 'i');
    });

    test('window is inclusive at 5 min, exclusive past it', () {
      final o = leg('o', 'a', out: true);
      expect(
        decideSameCurrency(
          leg('i', 'b', out: false, at: const Duration(minutes: 5)),
          [o],
        ),
        isA<PairWith>(),
      );
      expect(
        decideSameCurrency(
          leg('i', 'b', out: false, at: const Duration(minutes: 5, seconds: 1)),
          [o],
        ),
        isA<NoMatch>(),
      );
    });

    test('earlier counterpart (late arrival) pairs too', () {
      final o = leg('o', 'a', out: true, at: const Duration(minutes: 4));
      expect(
        decideSameCurrency(leg('i', 'b', out: false), [o]),
        isA<PairWith>(),
      );
    });

    test('two candidates: no auto-pair, both ids listed (EC-16)', () {
      final i = leg('i', 'b', out: false);
      final r = decideSameCurrency(i, [
        leg('o2', 'c', out: true, at: const Duration(minutes: 1)),
        leg('o1', 'a', out: true),
      ]);
      expect((r as AmbiguousMatch).candidateIds, ['o1', 'o2']);
    });

    test('one candidate that has another candidate: ambiguous', () {
      // o1 and i1 look like a pair, but i2 also fits o1.
      final o1 = leg('o1', 'a', out: true);
      final i2 = leg('i2', 'c', out: false);
      final i1 = leg('i1', 'b', out: false);
      final r = decideSameCurrency(o1, [i1]);
      expect(r, isA<PairWith>());
      final r2 = decideSameCurrency(o1, [i1, i2]);
      expect(r2, isA<AmbiguousMatch>());
      // The candidate's view: i1 sees o1 only, but o1 sees i1 and i2.
      final r3 = decideSameCurrency(i1, [o1, i2]);
      expect(r3, isA<AmbiguousMatch>());
    });

    test(
      'same account, same direction, other amount or currency: no match',
      () {
        final o = leg('o', 'a', out: true);
        expect(
          decideSameCurrency(leg('i', 'a', out: false), [o]),
          isA<NoMatch>(),
        );
        expect(
          decideSameCurrency(leg('i', 'b', out: true), [o]),
          isA<NoMatch>(),
        );
        expect(
          decideSameCurrency(leg('i', 'b', out: false, minor: 100001), [o]),
          isA<NoMatch>(),
        );
        expect(
          decideSameCurrency(leg('i', 'b', out: false, cur: usd), [o]),
          isA<NoMatch>(),
        );
      },
    );

    test('zero amount never pairs; leg ignores itself', () {
      final z = leg('o', 'a', out: true, minor: 0);
      expect(
        decideSameCurrency(z, [leg('i', 'b', out: false, minor: 0)]),
        isA<NoMatch>(),
      );
      final o = leg('o', 'a', out: true);
      expect(decideSameCurrency(o, [o]), isA<NoMatch>());
    });

    test('result does not depend on pool order', () {
      final i = leg('i', 'b', out: false);
      final a = leg('o1', 'a', out: true);
      final b = leg('o2', 'c', out: true);
      expect(
        (decideSameCurrency(i, [a, b]) as AmbiguousMatch).candidateIds,
        (decideSameCurrency(i, [b, a]) as AmbiguousMatch).candidateIds,
      );
    });
  });

  group('fx conversion in one account', () {
    test('opposite legs, other currency, same account, in window', () {
      final o = leg('o', 'multi', out: true, cur: usd, minor: 10000);
      final i = leg('i', 'multi', out: false, minor: 480000);
      expect(fxConversionCandidates(o, [i]).single.id, 'i');
    });
    test('other account or same currency or outside window: none', () {
      final o = leg('o', 'multi', out: true, cur: usd);
      expect(fxConversionCandidates(o, [leg('i', 'x', out: false)]), isEmpty);
      expect(
        fxConversionCandidates(o, [leg('i', 'multi', out: false, cur: usd)]),
        isEmpty,
      );
      expect(
        fxConversionCandidates(o, [
          leg('i', 'multi', out: false, at: const Duration(minutes: 6)),
        ]),
        isEmpty,
      );
    });
  });

  group('conversion arithmetic', () {
    test('USD 100.00 at 48.5 EGP = 4,850.00', () {
      expect(
        convertWithRate(Money(usd, 10000), egp, 48500000000),
        Money(egp, 485000),
      );
    });
    test('exponent differences: EGP 1,000.00 to KWD (3) and to JPY (0)', () {
      // 1 EGP = 0.00625 KWD -> 6.250 KWD
      expect(
        convertWithRate(Money(egp, 100000), kwd, 6250000),
        Money(kwd, 6250),
      );
      expect(
        convertWithRate(Money(egp, 100000), jpy, 3000000000),
        Money(jpy, 3000),
      );
    });
    test('rounds half up; bad rate and overflow give null', () {
      expect(convertWithRate(Money(usd, 1), egp, 500000000), Money(egp, 1));
      expect(convertWithRate(Money(usd, 1), egp, 0), isNull);
      expect(
        convertWithRate(Money(egp, Money.maxMinor), egp, 2000000000),
        isNull,
      );
    });
    test('tolerance boundary is exactly 3%', () {
      expect(
        withinTolerance(Money(egp, 10000), Money(egp, 10300), 300),
        isTrue,
      );
      expect(withinTolerance(Money(egp, 10000), Money(egp, 9700), 300), isTrue);
      expect(
        withinTolerance(Money(egp, 10000), Money(egp, 10301), 300),
        isFalse,
      );
      expect(
        withinTolerance(Money(egp, 10000), Money(usd, 10000), 300),
        isFalse,
      );
    });
  });

  group('cross currency suggestion', () {
    int? rate(Currency f, Currency t) =>
        f == usd && t == egp ? 48500000000 : null;

    test('within 3 days and 3%: suggested, never PairWith', () {
      final o = leg('o', 'a', out: true, cur: usd, minor: 10000);
      final i = leg(
        'i',
        'b',
        out: false,
        minor: 472000,
        at: const Duration(days: 3),
      );
      expect(crossCurrencyCandidates(o, [i], rate).single.id, 'i');
    });
    test('outside 3 days, outside 3%, no rate, same account: none', () {
      final o = leg('o', 'a', out: true, cur: usd, minor: 10000);
      expect(
        crossCurrencyCandidates(o, [
          leg('i', 'b', out: false, minor: 472000, at: const Duration(days: 4)),
          leg('j', 'b', out: false, minor: 440000),
          leg('k', 'a', out: false, minor: 485000),
        ], rate),
        isEmpty,
      );
      expect(
        crossCurrencyCandidates(o, [
          leg('i', 'b', out: false, minor: 485000),
        ], (_, _) => null),
        isEmpty,
      );
    });
  });
}
