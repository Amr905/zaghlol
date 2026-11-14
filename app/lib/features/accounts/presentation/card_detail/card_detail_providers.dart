// T-084: read models behind S-41 (card detail) and S-42 (compare). Widgets
// read these; none touches the DB. Everything is per currency: nothing is
// summed across currencies (D-28).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../budget/application/budget_providers.dart';
import '../../../insights/data/chart_providers.dart';
import '../../../insights/domain/chart_models.dart';
import '../../../recurring/data/recurring_repository.dart';
import '../../../transactions/data/transactions_providers.dart';
import '../../../transactions/domain/transaction.dart';
import '../../data/accounts_providers.dart';
import '../../domain/account.dart';

/// How many recent rows S-41 shows.
const int cardDetailRecentCount = 5;

/// Trend buckets (cycles) on S-41.
const int cardDetailTrendBuckets = 6;

/// The account and its balances; null when it no longer exists.
final cardDetailAccountProvider =
    FutureProvider.family<AccountWithBalances?, String>((ref, id) async {
      final repo = await ref.watch(accountsRepositoryProvider.future);
      final all = await repo.listWithBalances(includeHidden: true);
      for (final a in all) {
        if (a.account.id == id) return a;
      }
      return null;
    }, name: 'cardDetailAccountProvider');

/// Everything S-41 shows below the header, for one card and one currency in
/// the current cycle.
final class CardDetailData {
  const CardDetailData({
    required this.donut,
    required this.merchants,
    required this.trend,
    required this.recent,
    required this.income,
    required this.nextDue,
  });

  final ChartResult<CategoryDonut> donut;
  final ChartResult<List<MerchantSpend>> merchants;
  final ChartResult<List<CashFlowPoint>> trend;
  final List<TransactionRecord> recent;

  /// Income and refunds in the current cycle; null when there is no trend.
  final Money? income;

  /// The next statement due date of a credit card (T-096 item), if any.
  final CivilDate? nextDue;
}

/// Key: account id and currency code.
typedef CardDetailKey = ({String accountId, String currency});

final cardDetailDataProvider =
    FutureProvider.family<CardDetailData, CardDetailKey>((ref, key) async {
      final schedule = await ref.watch(paydayScheduleProvider.future);
      final cycle = schedule.cycleOn(ref.watch(todayProvider));
      final charts = await ref.watch(chartRepositoryProvider.future);
      final txns = await ref.watch(transactionRepositoryProvider.future);
      final recurring = await ref.watch(recurringRepositoryProvider.future);
      final currency = Currency.of(key.currency);
      final filter = ChartFilter(
        currency: currency,
        accountIds: {key.accountId},
      );
      final period = ChartPeriod.cycle(cycle);
      final cycles = <Cycle>[cycle];
      for (var i = 1; i < cardDetailTrendBuckets; i++) {
        cycles.insert(0, schedule.before(cycles.first));
      }
      final donut = await charts.categoryDonut(period, filter);
      final merchants = await charts.topMerchants(period, filter, limit: 5);
      final trend = await charts.cashFlow([
        for (final c in cycles) ChartPeriod.cycle(c),
      ], filter);
      final recent = await txns.query(
        filter: TransactionFilter(
          accountIds: {key.accountId},
          currencies: {currency},
        ),
        page: const PageRequest(limit: cardDetailRecentCount),
      );
      CivilDate? due;
      for (final r in await recurring.list(status: RecurringStatus.active)) {
        if (r.kind == RecurringKind.cardDue &&
            r.accountId == key.accountId &&
            r.nextDueDate != null) {
          final d = CivilDate.tryParse(r.nextDueDate!);
          if (d != null && (due == null || d < due)) due = d;
        }
      }
      return CardDetailData(
        donut: donut,
        merchants: merchants,
        trend: trend,
        recent: recent,
        income: trend is ChartReady<List<CashFlowPoint>>
            ? trend.data.last.income
            : null,
        nextDue: due,
      );
    }, name: 'cardDetailDataProvider');

// ------------------------------------------------------------------ S-42

/// The picked currency on S-42; null means the first one with spending.
final compareCurrencyProvider =
    NotifierProvider.autoDispose<_CompareCurrency, String?>(
      _CompareCurrency.new,
      name: 'compareCurrencyProvider',
    );

class _CompareCurrency extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String code) => state = code;
}

/// Cards the user picked; null means "the top cards by spend".
final compareChosenProvider =
    NotifierProvider.autoDispose<_CompareChosen, Set<String>?>(
      _CompareChosen.new,
      name: 'compareChosenProvider',
    );

class _CompareChosen extends Notifier<Set<String>?> {
  @override
  Set<String>? build() => null;
  void set(Set<String> ids) => state = Set.unmodifiable(ids);
}

/// Up to this many cards at once (UX-A-03).
const int compareMaxCards = 6;

/// One column of the table.
final class CompareCard {
  const CompareCard({
    required this.accountId,
    required this.label,
    required this.spend,
    required this.byCategory,
  });

  final String accountId;
  final String label;

  /// Net spend of the period in the table's currency.
  final Money spend;

  /// Net spend by category id (null key: uncategorized).
  final Map<String?, Money> byCategory;
}

final class CompareData {
  const CompareData({
    required this.currencies,
    required this.currency,
    required this.available,
    required this.cards,
    required this.categoryIds,
    required this.period,
  });

  /// Currencies with spending in the period.
  final List<Currency> currencies;
  final Currency currency;

  /// Every card with spending (feeds "Choose cards").
  final List<CompareCard> available;

  /// The chosen columns.
  final List<CompareCard> cards;

  /// Rows: categories with spending on any shown card, biggest first.
  final List<String?> categoryIds;
  final ChartPeriod period;

  /// Fewer than two cards with spending (S-42 empty state).
  bool get isEmpty => available.length < 2;
}

final compareDataProvider = FutureProvider.autoDispose<CompareData>((
  ref,
) async {
  final schedule = await ref.watch(paydayScheduleProvider.future);
  final period = ChartPeriod.cycle(schedule.cycleOn(ref.watch(todayProvider)));
  final charts = await ref.watch(chartRepositoryProvider.future);
  final currencies = await charts.currenciesWithActivity(period);
  final picked = ref.watch(compareCurrencyProvider);
  final currency = currencies.isEmpty
      ? Currency.of('EGP')
      : currencies.firstWhere(
          (c) => c.code == picked,
          orElse: () => currencies.first,
        );
  final chosen = ref.watch(compareChosenProvider);
  final split = await charts.cardsSplit(
    period,
    ChartFilter(currency: currency),
  );
  final available = <CompareCard>[];
  if (split is ChartReady<List<CardSpend>>) {
    for (final c in split.data) {
      final donut = await charts.categoryDonut(
        period,
        ChartFilter(currency: currency, accountIds: {c.accountId}),
      );
      available.add(
        CompareCard(
          accountId: c.accountId,
          label: c.label,
          spend: c.spend,
          byCategory: donut is ChartReady<CategoryDonut>
              ? {for (final s in donut.data.slices) s.categoryId: s.amount}
              : const {},
        ),
      );
    }
  }
  final shown = chosen == null
      ? available.take(compareMaxCards).toList()
      : [
          for (final a in available)
            if (chosen.contains(a.accountId)) a,
        ].take(compareMaxCards).toList();
  final totals = <String?, int>{};
  for (final c in shown) {
    c.byCategory.forEach((k, v) => totals[k] = (totals[k] ?? 0) + v.minor);
  }
  final ids = totals.keys.toList()
    ..sort((a, b) {
      final d = totals[b]!.compareTo(totals[a]!);
      return d != 0 ? d : (a ?? '').compareTo(b ?? '');
    });
  return CompareData(
    currencies: currencies,
    currency: currency,
    available: available,
    cards: shown,
    categoryIds: ids,
    period: period,
  );
}, name: 'compareDataProvider');
