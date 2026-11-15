// T-169/T-170: Smart ROI wiring (FR-ROI-01/04/05). Behind the `smart_roi`
// flag, OFF at launch: with the flag off nothing is queried and the list is
// empty. The screen (T-170) is in `../presentation/`.
//
// Signals, per currency, never summed across currencies. Spending figures are
// a monthly average over the three calendar months before the current one,
// from the T-105 category totals (catalog category codes, `sys:<code>` ids):
// - bulk staples: `groceries` (spend and number of rows);
// - delivery (rule 2): the `dining` category. GUESS: the catalog has one
//   category for cafes, restaurants and delivery, so this overstates pure
//   delivery;
// - ride-hailing (rule 5): no catalog category exists (`transport` also holds
//   fuel, tolls and public transport and would overstate it), so it stays
//   null (rule silent, Lead decision 2026-11-15) until merchant groups exist;
// - cafes (rule 1) and bottled water (rule 3): no catalog category exists,
//   and `dining` already feeds rule 2, so both stay null (rules silent)
//   until merchant groups exist;
// - subscriptions: the recurring subscription items (count, monthly cost).
// Balances come from the accounts repository (stored balances, per currency):
// - cash on hand: cash, current-account and debit balances;
// - idle surplus: cash on hand above one month of spending (the same
//   three-month average of all categories). GUESS: no budget is read;
// - idle days: days since the newest of those balances last moved (the
//   balance row's `as_of`). GUESS: a proxy for "sat there unused";
// - card balance (amount owed): credit limit minus available, for credit
//   accounts in their own currency, when both are known.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/flags/feature_flags.dart';
import '../../../core/flags/flags_providers.dart';
import '../../insights/data/chart_providers.dart';
import '../../accounts/data/accounts_providers.dart';
import '../../accounts/domain/account.dart';
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

/// The category code of a category id: `sys:groceries` -> `groceries`.
String roiCategoryCode(String? id) {
  if (id == null) return '';
  return id.startsWith('sys:') ? id.substring(4) : id;
}

const _cashKinds = {AccountKind.cash, AccountKind.account, AccountKind.debit};

/// The signals of [currency] from the chart queries and [accounts]. Null
/// figures mean "not enough data".
Future<RoiSignals> roiSignalsFrom(
  ChartRepository charts,
  Currency currency,
  DateTime now, {
  List<AccountWithBalances> accounts = const [],
}) async {
  // The three complete calendar months before [now]'s month.
  final first = DateTime(now.year, now.month - roiWindowMonths, 1);
  final last = DateTime(now.year, now.month, 0);
  final period = ChartPeriod(
    CivilDate(first.year, first.month, first.day),
    CivilDate(last.year, last.month, last.day),
  );
  final filter = ChartFilter(currency: currency);

  Money monthly(Money m) =>
      m.mulDiv(1, roiWindowMonths, MoneyRounding.halfEven);

  Money? staplesMonthly;
  int? staplesRuns;
  Money? deliveryMonthly;
  Money? commuteMonthly;
  Money? allSpendMonthly;
  final donut = await charts.categoryDonut(period, filter);
  if (donut is ChartReady<CategoryDonut>) {
    allSpendMonthly = monthly(donut.data.total);
    for (final slice in donut.data.slices) {
      switch (roiCategoryCode(slice.categoryId)) {
        case 'groceries':
          staplesMonthly = monthly(slice.amount);
          staplesRuns = (slice.count / roiWindowMonths).round();
        case 'dining':
          deliveryMonthly = monthly(slice.amount);
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

  // Cash on hand, and how long since it last moved.
  Money? cash;
  DateTime? newestMove;
  Money? owed;
  for (final a in accounts) {
    final kind = a.account.kind;
    for (final b in a.balances) {
      if (b.currency != currency) continue;
      if (_cashKinds.contains(kind) && b.balance != null) {
        cash = (cash ?? Money.zero(currency)) + b.balance!;
        if (newestMove == null || b.asOf.isAfter(newestMove)) {
          newestMove = b.asOf;
        }
      }
      if (kind == AccountKind.credit) {
        final limit = a.account.creditLimit;
        final available = b.available;
        if (limit != null &&
            available != null &&
            limit.currency == currency &&
            available.currency == currency) {
          final due = limit - available;
          if (due.minor > 0) owed = (owed ?? Money.zero(currency)) + due;
        }
      }
    }
  }
  Money? idleSurplus;
  int? idleDays;
  if (cash != null && allSpendMonthly != null && cash > allSpendMonthly) {
    idleSurplus = cash - allSpendMonthly;
    idleDays = newestMove == null ? null : now.difference(newestMove).inDays;
  }

  return RoiSignals(
    currency: currency,
    deliveryMonthly: deliveryMonthly,
    commuteMonthly: commuteMonthly,
    idleSurplus: idleSurplus,
    idleDays: idleDays,
    cardBalance: owed,
    cashOnHand: cash,
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
      final accounts = await (await ref.watch(
        accountsRepositoryProvider.future,
      )).listWithBalances(includeHidden: true);
      final signals = await roiSignalsFrom(
        charts,
        currency,
        ref.watch(clockProvider)(),
        accounts: accounts,
      );
      return RoiEngine.evaluate(signals, assumptions);
    }, name: 'roiSuggestionsProvider');
