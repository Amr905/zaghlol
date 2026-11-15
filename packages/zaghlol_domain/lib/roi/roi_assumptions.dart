// T-169: the example figures behind the Smart ROI rules (spec §12, FR-ROI-05).
// Pure Dart.
//
// Every figure is an EXAMPLE, labelled as such in the copy (never a quote or
// an offer). Amounts are `Money` in one currency; the table is keyed by
// currency, so a currency without an entry gets no suggestions (nothing is
// ever converted, CLAUDE.md §2.4). The backend may update the table through
// [RoiAssumptions.isValid] is ignored.

import '../money/currency.dart';
import '../money/money.dart';

/// Example figures for one currency.
final class RoiAssumptions {
  const RoiAssumptions({
    required this.currency,
    required this.coffeeThreshold,
    required this.coffeeMachinePrice,
    required this.coffeeInstallmentMonths,
    required this.coffeeRunningMonthly,
    required this.deliveryThreshold,
    required this.deliveryApplianceTotal,
    required this.deliveryGroceriesMonthly,
    required this.waterThreshold,
    required this.waterFilterTotal,
    required this.waterCartridgesAnnual,
    required this.idleCashThreshold,
    required this.idleMinDays,
    required this.idleRateBp,
    required this.commuteThreshold,
    required this.commuteVehicleMonthly,
    required this.commuteTransitMonthly,
    required this.cardCashThreshold,
    required this.cardMonthlyRateBp,
    required this.subscriptionsThreshold,
    required this.subscriptionsMinCount,
    required this.subscriptionsPlanMonthly,
    required this.staplesThreshold,
    required this.staplesMinRuns,
    required this.staplesBulkNumerator,
    required this.staplesBulkDenominator,
  });

  /// Spec §12 figures in EGP (piastres).
  factory RoiAssumptions.egp() {
    final egp = Currency.of('EGP');
    Money m(int pounds) => Money(egp, pounds * 100);
    return RoiAssumptions(
      currency: egp,
      coffeeThreshold: m(2000),
      coffeeMachinePrice: m(9600),
      coffeeInstallmentMonths: 12,
      coffeeRunningMonthly: m(450),
      deliveryThreshold: m(3500),
      deliveryApplianceTotal: m(5400),
      deliveryGroceriesMonthly: m(1500),
      waterThreshold: m(600),
      waterFilterTotal: m(4200),
      waterCartridgesAnnual: m(800),
      idleCashThreshold: m(30000),
      idleMinDays: 20,
      idleRateBp: 2200,
      commuteThreshold: m(4500),
      commuteVehicleMonthly: m(1650),
      commuteTransitMonthly: m(800),
      cardCashThreshold: m(15000),
      cardMonthlyRateBp: 350,
      subscriptionsThreshold: m(950),
      subscriptionsMinCount: 4,
      subscriptionsPlanMonthly: m(500),
      staplesThreshold: m(3000),
      staplesMinRuns: 6,
      staplesBulkNumerator: 5,
      staplesBulkDenominator: 6,
    );
  }

  final Currency currency;

  // 1 coffee machine
  final Money coffeeThreshold;
  final Money coffeeMachinePrice;
  final int coffeeInstallmentMonths;
  final Money coffeeRunningMonthly;

  // 2 cooking appliance instead of delivery
  final Money deliveryThreshold;
  final Money deliveryApplianceTotal;
  final Money deliveryGroceriesMonthly;

  // 3 water filter
  final Money waterThreshold;
  final Money waterFilterTotal;
  final Money waterCartridgesAnnual;

  // 4 idle cash
  final Money idleCashThreshold;
  final int idleMinDays;

  /// Example yearly yield in basis points (2200 = 22 %). Never a quote.
  final int idleRateBp;

  // 5 regular rides
  final Money commuteThreshold;
  final Money commuteVehicleMonthly;
  final Money commuteTransitMonthly;

  // 6 credit card balance
  final Money cardCashThreshold;

  /// Example monthly interest in basis points (350 = 3.5 %).
  final int cardMonthlyRateBp;

  // 7 subscriptions
  final Money subscriptionsThreshold;
  final int subscriptionsMinCount;
  final Money subscriptionsPlanMonthly;

  // 8 staples in bulk
  final Money staplesThreshold;
  final int staplesMinRuns;
  final int staplesBulkNumerator;
  final int staplesBulkDenominator;

  Iterable<Money> get _moneys => [
    coffeeThreshold,
    coffeeMachinePrice,
    coffeeRunningMonthly,
    deliveryThreshold,
    deliveryApplianceTotal,
    deliveryGroceriesMonthly,
    waterThreshold,
    waterFilterTotal,
    waterCartridgesAnnual,
    idleCashThreshold,
    commuteThreshold,
    commuteVehicleMonthly,
    commuteTransitMonthly,
    cardCashThreshold,
    subscriptionsThreshold,
    subscriptionsPlanMonthly,
    staplesThreshold,
  ];

  /// True when every amount is in [currency], every count is positive and
  /// every rate is in range. The engine ignores a table that fails this.
  bool get isValid =>
      _moneys.every((m) => m.currency == currency && m.minor >= 0) &&
      coffeeInstallmentMonths > 0 &&
      coffeeInstallmentMonths <= 12 &&
      idleMinDays >= 0 &&
      idleRateBp >= 0 &&
      idleRateBp <= 100000 &&
      cardMonthlyRateBp >= 0 &&
      cardMonthlyRateBp <= 10000 &&
      subscriptionsMinCount > 0 &&
      staplesMinRuns > 0 &&
      staplesBulkNumerator > 0 &&
      staplesBulkDenominator > 0 &&
      staplesBulkNumerator <= staplesBulkDenominator;

  /// A copy with some thresholds replaced (tests, catalog overrides).
  RoiAssumptions copyWith({
    Money? subscriptionsThreshold,
    Money? coffeeThreshold,
    int? idleRateBp,
  }) => RoiAssumptions(
    currency: currency,
    coffeeThreshold: coffeeThreshold ?? this.coffeeThreshold,
    coffeeMachinePrice: coffeeMachinePrice,
    coffeeInstallmentMonths: coffeeInstallmentMonths,
    coffeeRunningMonthly: coffeeRunningMonthly,
    deliveryThreshold: deliveryThreshold,
    deliveryApplianceTotal: deliveryApplianceTotal,
    deliveryGroceriesMonthly: deliveryGroceriesMonthly,
    waterThreshold: waterThreshold,
    waterFilterTotal: waterFilterTotal,
    waterCartridgesAnnual: waterCartridgesAnnual,
    idleCashThreshold: idleCashThreshold,
    idleMinDays: idleMinDays,
    idleRateBp: idleRateBp ?? this.idleRateBp,
    commuteThreshold: commuteThreshold,
    commuteVehicleMonthly: commuteVehicleMonthly,
    commuteTransitMonthly: commuteTransitMonthly,
    cardCashThreshold: cardCashThreshold,
    cardMonthlyRateBp: cardMonthlyRateBp,
    subscriptionsThreshold:
        subscriptionsThreshold ?? this.subscriptionsThreshold,
    subscriptionsMinCount: subscriptionsMinCount,
    subscriptionsPlanMonthly: subscriptionsPlanMonthly,
    staplesThreshold: staplesThreshold,
    staplesMinRuns: staplesMinRuns,
    staplesBulkNumerator: staplesBulkNumerator,
    staplesBulkDenominator: staplesBulkDenominator,
  );
}

/// The example figures by currency. Built-in: EGP only.
final class RoiAssumptionsTable {
  RoiAssumptionsTable(Iterable<RoiAssumptions> entries)
    : _byCode = {
        for (final e in entries)
          if (e.isValid) e.currency.code: e,
      };

  /// The launch table (spec §12, EGP).
  factory RoiAssumptionsTable.builtIn() =>
      RoiAssumptionsTable([RoiAssumptions.egp()]);

  final Map<String, RoiAssumptions> _byCode;

  /// The figures for [currency], or null: no entry means no suggestions.
  RoiAssumptions? forCurrency(Currency currency) => _byCode[currency.code];

  Iterable<String> get currencyCodes => _byCode.keys;
}
