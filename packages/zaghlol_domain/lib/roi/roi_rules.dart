// T-169: the 8 Smart ROI rules of spec §12 (FR-ROI-01/05). Pure Dart.
//
// Design note (C3):
// - A rule reads one currency's [RoiSignals] and that currency's example
//   figures ([RoiAssumptions]) and returns a [RoiSuggestion] or nothing.
//   Currencies never mix: signals and assumptions carry one currency, a
//   currency with no assumptions gets nothing, and results are per currency.
// - General advice only (D-38, FR-ROI-05): a suggestion names KINDS of
//   products ([RoiProductKind]) and a copy-deck key; the texts live in the
//   copy deck (`roi_rule<Name>_*`) and never name a bank, fund, brand or
//   product. The "no-names" test checks every rule's copy against the
//   registry and the merchant catalog.
// - Projections: year 1 and year 2 SAVING (not cumulative). Year 1 counts
//   one-off and installment costs; year 2 only the running costs. A rule
//   qualifies only when the habit is above its threshold AND year 1 saves
//   something.
// - Arithmetic is integer on `Money` (half-even, once per figure). The
//   idle-cash yield compounds once: year 2 earns on principal + year 1.
// - Strict ">" thresholds, as in the spec. The spec's subscriptions example
//   (950/month) sits exactly on the boundary; see the T-169 task notes.

import '../money/currency.dart';
import '../money/money.dart';
import '../money/money_errors.dart';
import '../money/rounding.dart';
import 'roi_assumptions.dart';

/// The 8 rules, in spec order. [copyName] is the copy-deck segment
/// (`roi_rule<copyName>_title` / `_body`).
enum RoiRule {
  coffeeMachine('Coffee'),
  cookingAppliance('Delivery'),
  waterFilter('Water'),
  idleCash('IdleCash'),
  regularRides('Commute'),
  cardInterest('CardInterest'),
  subscriptions('Subscriptions'),
  bulkStaples('Staples');

  const RoiRule(this.copyName);
  final String copyName;

  String get titleKey => 'roi_rule${copyName}_title';
  String get bodyKey => 'roi_rule${copyName}_body';
}

/// Kinds of product a suggestion may mention. Never a name.
enum RoiProductKind {
  installmentPlan,
  homeAppliance,
  waterFilter,
  moneyMarketFund,
  savingsCertificate,
  publicTransport,
  fullCardPayment,
  yearlyPlan,
  bulkShopping,
}

/// What the app knows about one currency's habits, as monthly figures. A
/// null field means "no signal": its rule is skipped.
final class RoiSignals {
  RoiSignals({
    required this.currency,
    this.coffeeMonthly,
    this.deliveryMonthly,
    this.waterMonthly,
    this.idleSurplus,
    this.idleDays,
    this.commuteMonthly,
    this.cardBalance,
    this.cashOnHand,
    this.subscriptionsMonthly,
    this.subscriptionCount,
    this.staplesMonthly,
    this.staplesRuns,
  }) {
    for (final m in [
      coffeeMonthly,
      deliveryMonthly,
      waterMonthly,
      idleSurplus,
      commuteMonthly,
      cardBalance,
      cashOnHand,
      subscriptionsMonthly,
      staplesMonthly,
    ]) {
      if (m != null && m.currency != currency) {
        throw CurrencyMismatch(currency, m.currency);
      }
    }
  }

  final Currency currency;

  /// Monthly spend at cafes.
  final Money? coffeeMonthly;

  /// Monthly fast-food and delivery spend.
  final Money? deliveryMonthly;

  /// Monthly bottled water and gallon delivery.
  final Money? waterMonthly;

  /// Cash above the monthly budget, and for how many days it has sat there.
  final Money? idleSurplus;
  final int? idleDays;

  /// Monthly ride-hailing spend.
  final Money? commuteMonthly;

  /// Revolving credit-card balance and the cash held.
  final Money? cardBalance;
  final Money? cashOnHand;

  /// Monthly total of separate media/gym renewals and how many there are.
  final Money? subscriptionsMonthly;
  final int? subscriptionCount;

  /// Monthly convenience-store grocery spend and the number of runs.
  final Money? staplesMonthly;
  final int? staplesRuns;
}

/// One qualifying suggestion. Figures are in [currency] only.
final class RoiSuggestion {
  const RoiSuggestion({
    required this.rule,
    required this.kinds,
    required this.currency,
    required this.habitYear,
    required this.year1Saving,
    required this.year2Saving,
    this.monthly,
    this.altMonthly,
    this.idle,
    this.balance,
    this.exampleRateBp,
  });

  final RoiRule rule;
  final List<RoiProductKind> kinds;
  final Currency currency;

  /// What the habit costs over a year.
  final Money habitYear;

  /// Saving in year 1 and in year 2 (not cumulative). Year 1 is above zero.
  final Money year1Saving;
  final Money year2Saving;

  /// Copy arguments: `{monthly}`, `{alt}`, `{idle}`, `{balance}` and the
  /// example rate in basis points (`{exampleRate}`), where the rule uses
  /// them.
  final Money? monthly;
  final Money? altMonthly;
  final Money? idle;
  final Money? balance;
  final int? exampleRateBp;

  /// Year 1 plus year 2 (the "2 years" projection of FR-ROI-01).
  Money get twoYearSaving => year1Saving + year2Saving;

  String get titleKey => rule.titleKey;
  String get bodyKey => rule.bodyKey;
}

/// Evaluates the rules.
abstract final class RoiEngine {
  /// The qualifying suggestions for [signals], best year-1 saving first
  /// (ties by rule order). Empty when [assumptions] is null or invalid, or
  /// is for another currency.
  static List<RoiSuggestion> evaluate(
    RoiSignals signals,
    RoiAssumptions? assumptions,
  ) {
    if (assumptions == null ||
        !assumptions.isValid ||
        assumptions.currency != signals.currency) {
      return const [];
    }
    final a = assumptions;
    final s = signals;
    final out = <RoiSuggestion?>[
      _coffee(s, a),
      _cooking(s, a),
      _water(s, a),
      _idleCash(s, a),
      _rides(s, a),
      _card(s, a),
      _subscriptions(s, a),
      _staples(s, a),
    ].whereType<RoiSuggestion>().where((r) => r.year1Saving.minor > 0).toList();
    out.sort((x, y) {
      final c = y.year1Saving.minor.compareTo(x.year1Saving.minor);
      return c != 0 ? c : x.rule.index.compareTo(y.rule.index);
    });
    return out;
  }

  /// Per-currency results: one list per currency, never merged.
  static Map<String, List<RoiSuggestion>> evaluateAll(
    Iterable<RoiSignals> signals,
    RoiAssumptionsTable table,
  ) => {
    for (final s in signals)
      s.currency.code: evaluate(s, table.forCurrency(s.currency)),
  };

  // ---------------------------------------------------------------- rules

  static bool _over(Money? spend, Money threshold) =>
      spend != null && spend > threshold;

  static Money _avg12(Money total) =>
      total.mulDiv(1, 12, MoneyRounding.halfEven);

  /// Habit [monthly] vs an alternative that costs [oneOff] in year 1 plus
  /// [running] per month in both years.
  static RoiSuggestion _habit(
    RoiRule rule,
    List<RoiProductKind> kinds,
    Money monthly,
    Money oneOffYear1,
    Money runningYear1,
    Money runningYear2, {
    Money? alt,
  }) {
    final habitYear = monthly.times(12);
    final altYear1 = oneOffYear1 + runningYear1;
    return RoiSuggestion(
      rule: rule,
      kinds: kinds,
      currency: monthly.currency,
      habitYear: habitYear,
      year1Saving: habitYear - altYear1,
      year2Saving: habitYear - runningYear2,
      monthly: monthly,
      altMonthly: alt ?? _avg12(altYear1),
    );
  }

  static RoiSuggestion? _coffee(RoiSignals s, RoiAssumptions a) {
    final m = s.coffeeMonthly;
    if (!_over(m, a.coffeeThreshold)) return null;
    final running = a.coffeeRunningMonthly.times(12);
    final monthlyInstallment = a.coffeeMachinePrice.mulDiv(
      1,
      a.coffeeInstallmentMonths,
      MoneyRounding.halfEven,
    );
    return _habit(
      RoiRule.coffeeMachine,
      const [RoiProductKind.homeAppliance, RoiProductKind.installmentPlan],
      m!,
      a.coffeeMachinePrice,
      running,
      running,
      alt: monthlyInstallment + a.coffeeRunningMonthly,
    );
  }

  static RoiSuggestion? _cooking(RoiSignals s, RoiAssumptions a) {
    final m = s.deliveryMonthly;
    if (!_over(m, a.deliveryThreshold)) return null;
    final groceries = a.deliveryGroceriesMonthly.times(12);
    return _habit(
      RoiRule.cookingAppliance,
      const [RoiProductKind.homeAppliance, RoiProductKind.installmentPlan],
      m!,
      a.deliveryApplianceTotal,
      groceries,
      groceries,
    );
  }

  static RoiSuggestion? _water(RoiSignals s, RoiAssumptions a) {
    final m = s.waterMonthly;
    if (!_over(m, a.waterThreshold)) return null;
    return _habit(
      RoiRule.waterFilter,
      const [RoiProductKind.waterFilter, RoiProductKind.installmentPlan],
      m!,
      a.waterFilterTotal,
      a.waterCartridgesAnnual,
      a.waterCartridgesAnnual,
    );
  }

  static RoiSuggestion? _idleCash(RoiSignals s, RoiAssumptions a) {
    final idle = s.idleSurplus;
    final days = s.idleDays;
    if (!_over(idle, a.idleCashThreshold) || days == null) return null;
    if (days <= a.idleMinDays) return null;
    final y1 = idle!.mulDiv(a.idleRateBp, 10000, MoneyRounding.halfEven);
    final y2 = (idle + y1).mulDiv(a.idleRateBp, 10000, MoneyRounding.halfEven);
    return RoiSuggestion(
      rule: RoiRule.idleCash,
      kinds: const [
        RoiProductKind.moneyMarketFund,
        RoiProductKind.savingsCertificate,
      ],
      currency: idle.currency,
      habitYear: Money.zero(idle.currency),
      year1Saving: y1,
      year2Saving: y2,
      idle: idle,
      exampleRateBp: a.idleRateBp,
    );
  }

  static RoiSuggestion? _rides(RoiSignals s, RoiAssumptions a) {
    final m = s.commuteMonthly;
    if (!_over(m, a.commuteThreshold)) return null;
    final vehicle = a.commuteVehicleMonthly.times(12);
    final transit = a.commuteTransitMonthly.times(12);
    return _habit(
      RoiRule.regularRides,
      const [RoiProductKind.installmentPlan, RoiProductKind.publicTransport],
      m!,
      Money.zero(m.currency),
      vehicle + transit,
      // The vehicle is paid off after year 1 (a 12-month plan).
      transit,
    );
  }

  static RoiSuggestion? _card(RoiSignals s, RoiAssumptions a) {
    final balance = s.cardBalance;
    final cash = s.cashOnHand;
    if (balance == null || cash == null || balance.minor <= 0) return null;
    if (cash <= a.cardCashThreshold || cash < balance) return null;
    final yearly = balance.mulDiv(
      a.cardMonthlyRateBp * 12,
      10000,
      MoneyRounding.halfEven,
    );
    return RoiSuggestion(
      rule: RoiRule.cardInterest,
      kinds: const [RoiProductKind.fullCardPayment],
      currency: balance.currency,
      habitYear: yearly,
      year1Saving: yearly,
      year2Saving: yearly,
      balance: balance,
      exampleRateBp: a.cardMonthlyRateBp,
    );
  }

  static RoiSuggestion? _subscriptions(RoiSignals s, RoiAssumptions a) {
    final m = s.subscriptionsMonthly;
    final n = s.subscriptionCount;
    if (!_over(m, a.subscriptionsThreshold)) return null;
    if (n == null || n < a.subscriptionsMinCount) return null;
    final plan = a.subscriptionsPlanMonthly.times(12);
    return _habit(
      RoiRule.subscriptions,
      const [RoiProductKind.yearlyPlan],
      m!,
      Money.zero(m.currency),
      plan,
      plan,
      alt: a.subscriptionsPlanMonthly,
    );
  }

  static RoiSuggestion? _staples(RoiSignals s, RoiAssumptions a) {
    final m = s.staplesMonthly;
    final runs = s.staplesRuns;
    if (!_over(m, a.staplesThreshold)) return null;
    if (runs == null || runs < a.staplesMinRuns) return null;
    final alt = m!.mulDiv(
      a.staplesBulkNumerator,
      a.staplesBulkDenominator,
      MoneyRounding.halfEven,
    );
    final altYear = alt.times(12);
    return _habit(
      RoiRule.bulkStaples,
      const [RoiProductKind.bulkShopping],
      m,
      Money.zero(m.currency),
      altYear,
      altYear,
      alt: alt,
    );
  }
}
