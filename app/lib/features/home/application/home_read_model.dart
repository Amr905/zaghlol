// T-052: everything Home shows, in one reactive provider (FR-HOME-01/03/05).
// Money stays per currency: nothing here adds two currencies (CLAUDE.md §2).
// Nothing here logs.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/settings/settings_providers.dart';
import '../../budget/application/budget_providers.dart';
import '../../budget/application/cycle_app_wiring.dart';
import '../../budget/application/cycle_overview.dart';
import '../../capture/application/capture_providers.dart';
import '../../capture/domain/scan_plan.dart';
import '../../ingestion/data/review_repository.dart'
    show reviewOpenCountProvider;
import '../../transactions/data/transactions_providers.dart';
import '../../transactions/domain/transaction.dart';
import 'card_filter.dart';

/// The recent feed length.
const int homeFeedLimit = 10;

/// One currency's hero and KPIs.
final class HomeCurrencyFigures {
  const HomeCurrencyFigures({required this.overview, required this.net});

  final CurrencyOverview overview;

  Currency get currency => overview.currency;
  Money get income => overview.totals.income;
  Money get spend => overview.totals.spend;
  Money get pending => overview.totals.pendingSpend;
  Money? get safeToSpend => overview.safeToSpend;
  Money? get budget => overview.budget;

  /// Income minus spend, same currency.
  final Money net;
}

/// A feed row. [excludedFromTotals] is true for internal transfers, which
/// are shown labelled and never counted (BR-XFR).
final class HomeFeedItem {
  const HomeFeedItem({required this.record, required this.excludedFromTotals});

  final TransactionRecord record;
  final bool excludedFromTotals;
}

final class HomeModel {
  const HomeModel({
    required this.cycle,
    required this.today,
    required this.daysRemaining,
    required this.currencies,
    required this.recent,
    required this.reviewCount,
    required this.scanInProgress,
    required this.cardFilter,
  });

  final Cycle cycle;
  final CivilDate today;
  final int daysRemaining;

  /// The primary currency first (when it has data), then the rest by code.
  final List<HomeCurrencyFigures> currencies;
  final List<HomeFeedItem> recent;
  final int reviewCount;
  final bool scanInProgress;

  /// Empty is all cards.
  final Set<String> cardFilter;

  /// EC-55: with one currency (or none) no currency UI is shown.
  bool get showCurrencyUi => currencies.length > 1;

  HomeCurrencyFigures? get hero => currencies.isEmpty ? null : currencies.first;
}

/// Primary currency first, then the others by code.
List<Currency> orderCurrencies(Iterable<Currency> all, Currency primary) {
  final rest = all.where((c) => c != primary).toList()
    ..sort((a, b) => a.code.compareTo(b.code));
  return [if (all.any((c) => c == primary)) primary, ...rest];
}

/// True while a first-run or re-scan is running.
final homeScanInProgressProvider = StreamProvider<bool>((ref) async* {
  final service = await ref.watch(inboxScanServiceProvider.future);
  if (service == null) {
    yield false;
    return;
  }
  yield false;
  yield* service.progress.map((p) => p.phase == ScanPhase.running);
}, name: 'homeScanInProgressProvider');

final homeModelProvider = FutureProvider<HomeModel>((ref) async {
  final schedule = await ref.watch(paydayScheduleProvider.future);
  final repo = await ref.watch(cycleRepositoryProvider.future);
  final txns = await ref.watch(transactionRepositoryProvider.future);
  final today = ref.watch(todayProvider);
  ref.watch(cycleDataVersionProvider);
  final filter = ref.watch(cardFilterProvider);
  final target = await ref.watch(incomeTargetProvider.future);
  final primary = await ref.watch(primaryCurrencyProvider.future);
  final reviewCount = await ref.watch(reviewOpenCountProvider.future);
  final scanning = ref.watch(homeScanInProgressProvider).value ?? false;

  final cycle = schedule.cycleOn(today);
  final overview = buildCycleOverview(
    cycle: cycle,
    today: today,
    totals: await repo.totals(cycle, accounts: filter),
    budgets: await repo.cycleBudgets(),
    incomeTarget: target,
  );
  final feed = await txns.query(
    filter: TransactionFilter(accountIds: filter),
    page: const PageRequest(limit: homeFeedLimit),
  );
  return HomeModel(
    cycle: cycle,
    today: today,
    daysRemaining: overview.daysRemaining,
    currencies: [
      for (final c in orderCurrencies(overview.byCurrency.keys, primary))
        HomeCurrencyFigures(
          overview: overview.byCurrency[c]!,
          net:
              overview.byCurrency[c]!.totals.income -
              overview.byCurrency[c]!.totals.spend,
        ),
    ],
    recent: [
      for (final r in feed)
        HomeFeedItem(record: r, excludedFromTotals: r.isInternal),
    ],
    reviewCount: reviewCount,
    scanInProgress: scanning,
    cardFilter: filter,
  );
}, name: 'homeModelProvider');
