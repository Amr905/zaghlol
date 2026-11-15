import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
Money e(int pounds) => Money(egp, pounds * 100);
int pounds(Money m) => m.minor ~/ 100;

RoiSuggestion? one(RoiSignals s, RoiRule rule, [RoiAssumptions? a]) {
  final r = RoiEngine.evaluate(s, a ?? RoiAssumptions.egp());
  return r.where((x) => x.rule == rule).firstOrNull;
}

void main() {
  group('spec section 12 numbers', () {
    test('1 coffee machine: 2,450/mo -> 29,400 habit, +14,400, +24,000', () {
      final r = one(
        RoiSignals(currency: egp, coffeeMonthly: e(2450)),
        RoiRule.coffeeMachine,
      )!;
      expect(pounds(r.habitYear), 29400);
      expect(pounds(r.year1Saving), 14400);
      expect(pounds(r.year2Saving), 24000);
      expect(pounds(r.altMonthly!), 1250);
      expect(pounds(r.twoYearSaving), 38400);
    });

    test('2 cooking appliance: 3,800/mo -> 45,600 habit, year 2 +27,600', () {
      final r = one(
        RoiSignals(currency: egp, deliveryMonthly: e(3800)),
        RoiRule.cookingAppliance,
      )!;
      expect(pounds(r.habitYear), 45600);
      expect(pounds(r.year2Saving), 27600);
      // The spec prints +19,500 for year 1, which does not follow from its
      // own inputs (45,600 - 5,400 - 12 x 1,500 = 22,200). See the task file.
      expect(pounds(r.year1Saving), 22200);
    });

    test('3 water filter: 700/mo -> 8,400 habit, +3,400, +7,600', () {
      final r = one(
        RoiSignals(currency: egp, waterMonthly: e(700)),
        RoiRule.waterFilter,
      )!;
      expect(pounds(r.habitYear), 8400);
      expect(pounds(r.year1Saving), 3400);
      expect(pounds(r.year2Saving), 7600);
    });

    test('4 idle cash: 35,000 at 22% example -> +7,700 in year 1', () {
      final r = one(
        RoiSignals(currency: egp, idleSurplus: e(35000), idleDays: 21),
        RoiRule.idleCash,
      )!;
      expect(pounds(r.year1Saving), 7700);
      expect(r.exampleRateBp, 2200);
      // Year 2 earns on principal plus year 1: 42,700 x 22% = 9,394.
      expect(pounds(r.year2Saving), 9394);
      expect(r.habitYear.minor, 0);
    });

    test('5 regular rides: 4,800/mo -> 57,600 habit, +28,200', () {
      final r = one(
        RoiSignals(currency: egp, commuteMonthly: e(4800)),
        RoiRule.regularRides,
      )!;
      expect(pounds(r.habitYear), 57600);
      expect(pounds(r.year1Saving), 28200);
      // Vehicle paid off after 12 months: year 2 keeps only transit.
      expect(pounds(r.year2Saving), 48000);
    });

    test('6 card interest: 12,000 at 3.5%/mo -> 5,040 a year', () {
      final r = one(
        RoiSignals(currency: egp, cardBalance: e(12000), cashOnHand: e(20000)),
        RoiRule.cardInterest,
      )!;
      expect(pounds(r.year1Saving), 5040);
      expect(pounds(r.habitYear), 5040);
      expect(r.exampleRateBp, 350);
    });

    test('7 subscriptions: 11,400/yr -> +5,400 (threshold lowered to 900)', () {
      // The spec example (950/mo) sits on the strict ">950" boundary.
      final a = RoiAssumptions.egp().copyWith(subscriptionsThreshold: e(900));
      final r = one(
        RoiSignals(
          currency: egp,
          subscriptionsMonthly: e(950),
          subscriptionCount: 4,
        ),
        RoiRule.subscriptions,
        a,
      )!;
      expect(pounds(r.habitYear), 11400);
      expect(pounds(r.year1Saving), 5400);
      expect(pounds(r.altMonthly!), 500);
    });

    test('8 bulk staples: 4,200/mo -> 50,400 habit, +8,400', () {
      final r = one(
        RoiSignals(currency: egp, staplesMonthly: e(4200), staplesRuns: 6),
        RoiRule.bulkStaples,
      )!;
      expect(pounds(r.habitYear), 50400);
      expect(pounds(r.year1Saving), 8400);
      expect(pounds(r.altMonthly!), 3500);
    });
  });

  group('thresholds', () {
    test('strictly above the threshold qualifies', () {
      expect(
        one(
          RoiSignals(currency: egp, coffeeMonthly: e(2000)),
          RoiRule.coffeeMachine,
        ),
        isNull,
      );
      expect(
        one(
          RoiSignals(currency: egp, coffeeMonthly: Money(egp, 200001)),
          RoiRule.coffeeMachine,
        ),
        isNotNull,
      );
      expect(
        one(
          RoiSignals(currency: egp, coffeeMonthly: e(2100)),
          RoiRule.coffeeMachine,
        ),
        isNotNull,
      );
    });

    test('idle cash needs more than 20 days', () {
      final s = e(35000);
      expect(
        one(
          RoiSignals(currency: egp, idleSurplus: s, idleDays: 20),
          RoiRule.idleCash,
        ),
        isNull,
      );
      expect(
        one(RoiSignals(currency: egp, idleSurplus: s), RoiRule.idleCash),
        isNull,
      );
      expect(
        one(
          RoiSignals(currency: egp, idleSurplus: e(30000), idleDays: 30),
          RoiRule.idleCash,
        ),
        isNull,
      );
    });

    test('card rule needs cash above 15,000 and at least the balance', () {
      RoiSignals sig(int bal, int cash) =>
          RoiSignals(currency: egp, cardBalance: e(bal), cashOnHand: e(cash));
      expect(one(sig(12000, 15000), RoiRule.cardInterest), isNull);
      expect(one(sig(20000, 18000), RoiRule.cardInterest), isNull);
      expect(one(sig(0, 20000), RoiRule.cardInterest), isNull);
      expect(one(sig(12000, 15001), RoiRule.cardInterest), isNotNull);
    });

    test('subscriptions and staples need enough items', () {
      expect(
        one(
          RoiSignals(
            currency: egp,
            subscriptionsMonthly: e(1000),
            subscriptionCount: 3,
          ),
          RoiRule.subscriptions,
        ),
        isNull,
      );
      expect(
        one(
          RoiSignals(
            currency: egp,
            subscriptionsMonthly: e(950),
            subscriptionCount: 4,
          ),
          RoiRule.subscriptions,
        ),
        isNull,
        reason: 'strict > 950',
      );
      expect(
        one(
          RoiSignals(currency: egp, staplesMonthly: e(4200), staplesRuns: 5),
          RoiRule.bulkStaples,
        ),
        isNull,
      );
    });
  });

  group('per currency', () {
    test('no assumptions for the currency means no suggestions', () {
      final r = RoiEngine.evaluate(
        RoiSignals(currency: usd, coffeeMonthly: Money(usd, 500000)),
        RoiAssumptionsTable.builtIn().forCurrency(usd),
      );
      expect(r, isEmpty);
    });

    test('assumptions of another currency are not used', () {
      final r = RoiEngine.evaluate(
        RoiSignals(currency: usd, coffeeMonthly: Money(usd, 500000)),
        RoiAssumptions.egp(),
      );
      expect(r, isEmpty);
    });

    test('signals refuse a mixed-currency amount', () {
      expect(
        () => RoiSignals(currency: egp, coffeeMonthly: Money(usd, 500000)),
        throwsA(isA<CurrencyMismatch>()),
      );
    });

    test('evaluateAll keeps one list per currency, never summed', () {
      final res = RoiEngine.evaluateAll([
        RoiSignals(currency: egp, coffeeMonthly: e(2450)),
        RoiSignals(currency: usd, coffeeMonthly: Money(usd, 500000)),
      ], RoiAssumptionsTable.builtIn());
      expect(res.keys, ['EGP', 'USD']);
      expect(res['EGP'], hasLength(1));
      expect(res['EGP']!.single.year1Saving.currency, egp);
      expect(res['USD'], isEmpty);
    });

    test('a currency table with a bad entry is ignored', () {
      final good = RoiAssumptions.egp();
      final bad = RoiAssumptions.egp().copyWith(idleRateBp: -1);
      expect(RoiAssumptionsTable([bad]).forCurrency(egp), isNull);
      expect(RoiAssumptionsTable([good]).forCurrency(egp), isNotNull);
    });
  });

  group('ordering and output', () {
    test('best year-1 saving first, ties by rule order', () {
      final r = RoiEngine.evaluate(
        RoiSignals(
          currency: egp,
          coffeeMonthly: e(2450),
          commuteMonthly: e(4800),
          waterMonthly: e(700),
        ),
        RoiAssumptions.egp(),
      );
      expect(r.map((x) => x.rule), [
        RoiRule.regularRides,
        RoiRule.coffeeMachine,
        RoiRule.waterFilter,
      ]);
    });

    test('no signals, no suggestions', () {
      expect(
        RoiEngine.evaluate(RoiSignals(currency: egp), RoiAssumptions.egp()),
        isEmpty,
      );
    });

    test('every rule has copy keys and kinds only', () {
      for (final rule in RoiRule.values) {
        expect(rule.titleKey, startsWith('roi_rule'));
        expect(rule.bodyKey, endsWith('_body'));
      }
      expect(RoiRule.values, hasLength(8));
    });

    test('Arabic digits are not involved: figures are integers', () {
      final r = one(
        RoiSignals(currency: egp, coffeeMonthly: e(2450)),
        RoiRule.coffeeMachine,
      )!;
      expect(r.year1Saving.minor, isA<int>());
    });
  });
}
