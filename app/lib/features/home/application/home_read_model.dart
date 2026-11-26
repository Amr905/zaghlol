// T-052: everything Home shows, in one reactive provider (FR-HOME-01/03/05).
// Money stays per currency: nothing here adds two currencies (CLAUDE.md §2).
// Nothing here logs.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/settings/settings_providers.dart';
import '../../accounts/data/accounts_providers.dart';
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
  const HomeCurrencyFigures({
    required this.overview,
    required this.net,
    this.safeToSpend,
  });

  /// Spend figures for the selected cards.
  final CurrencyOverview overview;

  Currency get currency => overview.currency;
  Money get income => overview.totals.income;

  /// T-272 (D-86): the month's money in: income plus money received by
  /// exchanging another currency. The income KPI shows this.
  Money get moneyIn => overview.totals.moneyIn;

  /// The exchanged-in part of [moneyIn] (never income, never spending).
  Money get exchangedIn => overview.totals.exchangedIn;

  /// Money of this currency given away in exchanges (never spending).
  Money get exchangedOut => overview.totals.exchangedOut;
  Money get spend => overview.totals.spend;
  Money get pending => overview.totals.pendingSpend;

  /// Always from all cards: the card filter never changes it.
  final Money? safeToSpend;
  Money? get budget => overview.budget;

  /// What is left: money in minus spend minus exchanged out, same
  /// currency (T-272; was income minus spend).
  final Money net;
}

/// T-278 (D-86): one small currency card under the Home hero. A non-primary
/// currency appears when it had activity this month (spending, income or an
/// exchange) or holds a non-zero balance on an account. Never converted.
final class HomeCurrencyCard {
  const HomeCurrencyCard({required this.figures, this.lastActivity});

  /// This month in that currency (zeros when only a balance qualifies).
  final HomeCurrencyFigures figures;

  /// The latest civil date of a transaction of this currency in the month;
  /// null when the card exists only because of a balance.
  final CivilDate? lastActivity;

  Currency get currency => figures.currency;

  /// What is left, exact in the currency's own exponent.
  Money get left => figures.net;

  Money get moneyIn => figures.moneyIn;

  /// Spending plus what was exchanged away (so in - out = left).
  Money get out => figures.spend + figures.exchangedOut;
}

/// The cards, most recent activity first (balance-only last, then by code).
List<HomeCurrencyCard> orderCurrencyCards(Iterable<HomeCurrencyCard> cards) {
  final list = cards.toList();
  list.sort((a, b) {
    final x = a.lastActivity;
    final y = b.lastActivity;
    if (x != null && y != null) {
      final c = y.compareTo(x);
      if (c != 0) return c;
    } else if (x != null) {
      return -1;
    } else if (y != null) {
      return 1;
    }
    return a.currency.code.compareTo(b.currency.code);
  });
  return list;
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
    this.currencyCards = const [],
    this.primary,
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
  bool get showCurrencyUi => currencyCards.isNotEmpty;

  /// T-278: the small cards of the other currencies, in display order. The
  /// primary currency never has one (it is the hero).
  final List<HomeCurrencyCard> currencyCards;

  /// The primary currency (the hero); null means "the first of
  /// [currencies]" (tests and legacy callers).
  final Currency? primary;

  /// The hero is always the primary currency's page (T-278). When only
  /// other currencies have data it shows zeros; null when there is no data.
  HomeCurrencyFigures? get hero {
    if (currencies.isEmpty && currencyCards.isEmpty) return null;
    final p =
        primary ?? (currencies.isEmpty ? null : currencies.first.currency);
    if (p == null) return null;
    for (final f in currencies) {
      if (f.currency == p) return f;
    }
    return zeroFigures(p);
  }
}

/// Figures with every amount zero (a currency with nothing this month).
HomeCurrencyFigures zeroFigures(Currency c) => HomeCurrencyFigures(
  overview: CurrencyOverview(
    currency: c,
    totals: CycleTotals(
      currency: c,
      income: Money.zero(c),
      spend: Money.zero(c),
      pendingSpend: Money.zero(c),
      byCategoryMinor: const {},
    ),
    budget: null,
    safeToSpend: null,
    underIdealLine: null,
  ),
  net: Money.zero(c),
);

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
  final budgets = await repo.cycleBudgets();
  final all = buildCycleOverview(
    cycle: cycle,
    today: today,
    totals: await repo.totals(cycle),
    budgets: budgets,
    incomeTarget: target,
  );
  final overview = filter.isEmpty
      ? all
      : buildCycleOverview(
          cycle: cycle,
          today: today,
          totals: await repo.totals(cycle, accounts: filter),
          budgets: budgets,
          incomeTarget: target,
        );
  // T-278: cards for the other currencies (activity this month or a balance).
  final (rows, _) = await repo.loadRows(cycle, accounts: filter);
  final lastActivity = <Currency, CivilDate>{};
  for (final r in rows) {
    if (r.status == CycleStatus.declined || r.status == CycleStatus.reversed) {
      continue;
    }
    final cur = lastActivity[r.amount.currency];
    if (cur == null || r.date > cur) lastActivity[r.amount.currency] = r.date;
  }
  final accountsRepo = await ref.watch(accountsRepositoryProvider.future);
  final held = <Currency>{};
  for (final a in await accountsRepo.listWithBalances(includeHidden: true)) {
    if (filter.isNotEmpty && !filter.contains(a.account.id)) continue;
    for (final b in a.balances) {
      final m = b.balance;
      if (m != null && m.minor != 0) held.add(m.currency);
    }
  }
  final cards = <HomeCurrencyCard>[];
  for (final c in {
    ...overview.byCurrency.keys,
    ...lastActivity.keys,
    ...held,
  }) {
    if (c == primary) continue;
    final f = overview.byCurrency[c];
    final t = f?.totals;
    final active =
        lastActivity.containsKey(c) ||
        (t != null &&
            (t.income.minor != 0 ||
                t.spend.minor != 0 ||
                t.exchangedIn.minor != 0 ||
                t.exchangedOut.minor != 0));
    if (!active && !held.contains(c)) continue;
    cards.add(
      HomeCurrencyCard(
        figures: f == null
            ? zeroFigures(c)
            : HomeCurrencyFigures(
                overview: f,
                safeToSpend: all.byCurrency[c]?.safeToSpend,
                net: f.totals.left,
              ),
        lastActivity: lastActivity[c],
      ),
    );
  }
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
          safeToSpend: all.byCurrency[c]?.safeToSpend,
          net: overview.byCurrency[c]!.totals.left,
        ),
    ],
    recent: [
      for (final r in feed)
        HomeFeedItem(record: r, excludedFromTotals: r.isInternal),
    ],
    reviewCount: reviewCount,
    scanInProgress: scanning,
    cardFilter: filter,
    currencyCards: orderCurrencyCards(cards),
    primary: primary,
  );
}, name: 'homeModelProvider');
