// T-169: Smart ROI wiring (FR-ROI-01/04/05). Behind the `smart_roi` flag,
// OFF at launch: with the flag off nothing is queried and the list is empty.
// No UI here (T-170 is the screen, and applies the Gold gate and dismissals).
//
// Signals come from the T-105 chart queries, per currency, as a monthly
// average over the three calendar months before the current one:
// - bulk staples: the `groceries` category (spend and number of rows);
// - subscriptions: the recurring subscription items (count, monthly cost).
// The other rules need figures T-105 does not have (cafe, delivery, water and
// ride-hailing merchant groups, idle cash, card balance); their signals stay
// null and the rules stay silent until those sources exist (follow-up).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/flags/feature_flags.dart';
import '../../../core/flags/flags_providers.dart';
import '../../insights/data/chart_providers.dart';
import '../../insights/data/chart_repository.dart';
import '../../insights/domain/chart_models.dart';
import '../../transactions/data/transactions_providers.dart' show clockProvider;

/// Months averaged for the monthly figures.
const int roiWindowMonths = 3;

/// The example figures. Overridden when the catalog supplies a newer table.
final roiAssumptionsProvider = Provider<RoiAssumptionsTable>(
  (ref) => RoiAssumptionsTable.builtIn(),
  name: 'roiAssumptionsProvider',
);

/// The monthly signals of [currency] from the chart queries. Null figures
/// mean "not enough data".
Future<RoiSignals> roiSignalsFrom(
  ChartRepository charts,
  Currency currency,
  DateTime now,
) async {
  // The three complete calendar months before [now]'s month.
  final first = DateTime(now.year, now.month - roiWindowMonths, 1);
  final last = DateTime(now.year, now.month, 0);
  final period = ChartPeriod(
    CivilDate(first.year, first.month, first.day),
    CivilDate(last.year, last.month, last.day),
  );
  final filter = ChartFilter(currency: currency);

  Money? staplesMonthly;
  int? staplesRuns;
  final donut = await charts.categoryDonut(period, filter);
  if (donut is ChartReady<CategoryDonut>) {
    for (final slice in donut.data.slices) {
      if (slice.categoryId == 'groceries') {
        staplesMonthly = slice.amount.mulDiv(
          1,
          roiWindowMonths,
          MoneyRounding.halfEven,
        );
        staplesRuns = (slice.count / roiWindowMonths).round();
      }
    }
  }

  Money? subscriptionsMonthly;
  int? subscriptionCount;
  final subs = await charts.subscriptionsAnnual(filter);
  if (subs is ChartReady<SubscriptionsAnnual>) {
    subscriptionCount = subs.data.items.length;
    subscriptionsMonthly = subs.data.annualTotal.mulDiv(
      1,
      12,
      MoneyRounding.halfEven,
    );
  }

  return RoiSignals(
    currency: currency,
    staplesMonthly: staplesMonthly,
    staplesRuns: staplesRuns,
    subscriptionsMonthly: subscriptionsMonthly,
    subscriptionCount: subscriptionCount,
  );
}

/// The qualifying suggestions for one currency. Empty while the flag is off
/// (nothing is queried) and for a currency without example figures.
final roiSuggestionsProvider =
    FutureProvider.family<List<RoiSuggestion>, Currency>((ref, currency) async {
      if (!ref.watch(featureFlagProvider(FeatureFlag.smartRoi))) {
        return const [];
      }
      final assumptions = ref
          .watch(roiAssumptionsProvider)
          .forCurrency(currency);
      if (assumptions == null) return const [];
      final charts = await ref.watch(chartRepositoryProvider.future);
      final signals = await roiSignalsFrom(
        charts,
        currency,
        ref.watch(clockProvider)(),
      );
      return RoiEngine.evaluate(signals, assumptions);
    }, name: 'roiSuggestionsProvider');
