// T-110: Ask Zaghlol, fully offline (D-06, FR-CHAT-01/03/04/05). Parses a
// question with the pure grammar in `zaghlol_parsing`, turns the slots into
// a query plan and answers through the T-105 chart repository (plus the
// accounts and cycle budgets for balance and budget questions). One figure
// per currency; a question that is not understood gets a fallback with
// example chips and never a number. Nothing here logs: no question, name or
// amount leaves this class except inside the returned answer.

import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../accounts/domain/account.dart';
import '../../insights/data/chart_repository.dart';
import '../../insights/domain/chart_models.dart';
import '../../insights/domain/chart_rules.dart';
import '../domain/ask_models.dart';
import '../domain/ask_period.dart';
import '../domain/roast_picker.dart';

/// Reads what the answers need besides the chart queries.
typedef AccountsSource = Future<List<AccountWithBalances>> Function();
typedef BudgetsSource = Future<Map<Currency, Money>> Function();
typedef ScheduleSource = Future<PaydaySchedule> Function();
typedef EntitiesSource = Future<AskEntities> Function();

/// Dues within this many days are "upcoming".
const int askDuesWindowDays = 30;

/// Default length of the top-merchants list.
const int askDefaultTop = 5;

class AskEngine {
  AskEngine({
    required this.charts,
    required this.accounts,
    required this.cycleBudgets,
    required this.schedule,
    required this.entities,
    required this.today,
  });

  final ChartRepository charts;
  final AccountsSource accounts;
  final BudgetsSource cycleBudgets;
  final ScheduleSource schedule;
  final EntitiesSource entities;
  final CivilDate Function() today;

  /// Answers [question]. Never throws: a database failure is
  /// [AskUnavailableAnswer]; an unknown question is [AskFallbackAnswer].
  Future<AskAnswer> ask(
    String question, {
    int roastSeed = 0,
    Set<RoastKind> recentRoasts = const {},
  }) async {
    try {
      final ents = await entities();
      final parsed = parseAskQuestion(question, entities: ents);
      return switch (parsed) {
        AskUnrecognized(:final reason) => AskFallbackAnswer(
          reason,
          askFallbackChips,
        ),
        AskUnderstood(:final intent, :final slots) => await _answer(
          intent,
          slots,
          ents,
          roastSeed,
          recentRoasts,
        ),
      };
    } on Exception {
      return const AskUnavailableAnswer();
    }
  }

  /// Answers a tapped chip without parsing text (FR-CHAT-05).
  Future<AskAnswer> askChip(
    AskChip chip, {
    int roastSeed = 0,
    Set<RoastKind> recentRoasts = const {},
  }) async {
    const month = AskPeriod(AskPeriodKind.month);
    const last = AskPeriod(AskPeriodKind.month, offset: -1);
    final (intent, slots) = switch (chip) {
      AskChip.spendThisMonth => (
        AskIntent.spend,
        const AskSlots(period: month),
      ),
      AskChip.spendLastMonth => (AskIntent.spend, const AskSlots(period: last)),
      AskChip.topMerchants => (
        AskIntent.topMerchants,
        const AskSlots(period: month),
      ),
      AskChip.biggestExpense => (
        AskIntent.biggestExpense,
        const AskSlots(period: month),
      ),
      AskChip.budgetLeft => (
        AskIntent.budgetRemaining,
        const AskSlots(period: AskPeriod(AskPeriodKind.cycle)),
      ),
      AskChip.balance => (AskIntent.accountBalance, const AskSlots()),
      AskChip.upcomingDues => (AskIntent.upcomingDues, const AskSlots()),
      AskChip.savings => (AskIntent.savings, const AskSlots(period: month)),
      AskChip.compareMonths => (
        AskIntent.comparePeriods,
        const AskSlots(period: month, compareWith: last),
      ),
      AskChip.roast => (AskIntent.roast, const AskSlots(period: month)),
    };
    try {
      return await _answer(
        intent,
        slots,
        AskEntities.none,
        roastSeed,
        recentRoasts,
      );
    } on Exception {
      return const AskUnavailableAnswer();
    }
  }

  // ------------------------------------------------------------ routing

  Future<AskAnswer> _answer(
    AskIntent intent,
    AskSlots s,
    AskEntities ents,
    int seed,
    Set<RoastKind> recent,
  ) async {
    final sched = await schedule();
    final now = today();
    final first = await charts.firstDataDay();
    ChartPeriod res(AskPeriod p) =>
        resolveAskPeriod(p, now, sched, firstDay: first);
    final period = res(s.period ?? const AskPeriod(AskPeriodKind.month));
    return switch (intent) {
      AskIntent.spend => _spend(s, period, ents),
      AskIntent.comparePeriods => _compare(
        s,
        period,
        res(s.compareWith ?? const AskPeriod(AskPeriodKind.month, offset: -1)),
        ents,
      ),
      AskIntent.topMerchants => _top(s, period),
      AskIntent.accountBalance => _balance(s, ents),
      AskIntent.budgetRemaining => _budget(s, period),
      AskIntent.upcomingDues => _dues(s, now),
      AskIntent.biggestExpense => _biggest(s, period, ents),
      AskIntent.savings => _savings(s, period),
      AskIntent.roast => _roast(s, period, seed, recent),
    };
  }

  // ------------------------------------------------------------ helpers

  ChartFilter _filter(Currency c, AskSlots s) =>
      ChartFilter(currency: c, accountIds: s.accountIds);

  Currency? _slotCurrency(AskSlots s) =>
      s.currencyCode == null ? null : Currency.tryOf(s.currencyCode!);

  /// Currencies with activity in [p] (or the one the user asked for), by
  /// code.
  Future<List<Currency>> _currencies(ChartPeriod p, AskSlots s) async {
    final asked = _slotCurrency(s);
    if (asked != null) return [asked];
    return charts.currenciesWithActivity(p, accountIds: s.accountIds);
  }

  AskTarget _target(AskSlots s) {
    if (s.merchantIds.isNotEmpty) return AskTarget.merchant;
    if (s.categoryId != null) return AskTarget.category;
    if (s.accountIds.isNotEmpty) return AskTarget.card;
    return AskTarget.everything;
  }

  String? _label(AskSlots s, AskEntities ents) {
    final list = s.merchantIds.isNotEmpty ? ents.merchants : ents.accounts;
    final ids = s.merchantIds.isNotEmpty ? s.merchantIds : s.accountIds;
    if (ids.isEmpty) return null;
    final names = <String>{
      for (final e in list)
        if (ids.contains(e.id) && e.names.isNotEmpty) e.names.first,
    }.toList()..sort();
    return names.isEmpty ? null : names.join(' / ');
  }

  /// Net spend of the slots' target in [c] over [p]; null when none.
  Future<Money?> _spendIn(ChartPeriod p, AskSlots s, Currency c) async {
    final f = _filter(c, s);
    if (s.merchantIds.isNotEmpty) {
      return (await charts.merchantSpend(p, f, s.merchantIds))?.amount;
    }
    final r = await charts.categoryDonut(p, f);
    if (r is! ChartReady<CategoryDonut>) return null;
    if (s.categoryId == null) return r.data.total;
    for (final slice in r.data.slices) {
      if (slice.categoryId == s.categoryId) return slice.amount;
    }
    return null;
  }

  // -------------------------------------------------------------- spend

  Future<AskAnswer> _spend(AskSlots s, ChartPeriod p, AskEntities ents) async {
    final figures = <Money>[];
    for (final c in await _currencies(p, s)) {
      final m = await _spendIn(p, s, c);
      if (m != null && m.isPositive) figures.add(m);
    }
    if (figures.isEmpty) {
      return const AskNoDataAnswer(
        AskIntent.spend,
        AskNoDataReason.noTransactions,
      );
    }
    return AskSpendAnswer(
      period: p,
      periodDefaulted: s.periodDefaulted,
      target: _target(s),
      categoryId: s.categoryId,
      targetLabel: _label(s, ents),
      figures: figures,
    );
  }

  Future<AskAnswer> _compare(
    AskSlots s,
    ChartPeriod a,
    ChartPeriod b,
    AskEntities ents,
  ) async {
    final span = ChartPeriod(
      a.from < b.from ? a.from : b.from,
      a.to > b.to ? a.to : b.to,
    );
    final figures = <AskCompareFigure>[];
    for (final c in await _currencies(span, s)) {
      final cur = await _spendIn(a, s, c) ?? Money(c, 0);
      final prev = await _spendIn(b, s, c) ?? Money(c, 0);
      if (cur.isZero && prev.isZero) continue;
      figures.add(
        AskCompareFigure(
          current: cur,
          previous: prev,
          deltaBp: deltaBp(cur.minor, prev.minor),
        ),
      );
    }
    if (figures.isEmpty) {
      return const AskNoDataAnswer(
        AskIntent.comparePeriods,
        AskNoDataReason.noTransactions,
      );
    }
    return AskCompareAnswer(
      current: a,
      previous: b,
      target: _target(s),
      categoryId: s.categoryId,
      targetLabel: _label(s, ents),
      figures: figures,
    );
  }

  // ------------------------------------------------------ top merchants

  Future<AskAnswer> _top(AskSlots s, ChartPeriod p) async {
    final lists = <List<MerchantSpend>>[];
    for (final c in await _currencies(p, s)) {
      final r = await charts.topMerchants(
        p,
        _filter(c, s),
        limit: s.limit ?? askDefaultTop,
      );
      if (r is ChartReady<List<MerchantSpend>>) lists.add(r.data);
    }
    if (lists.isEmpty) {
      return const AskNoDataAnswer(
        AskIntent.topMerchants,
        AskNoDataReason.noTransactions,
      );
    }
    return AskTopMerchantsAnswer(
      period: p,
      periodDefaulted: s.periodDefaulted,
      byCurrency: lists,
    );
  }

  // ------------------------------------------------------------ balance

  Future<AskAnswer> _balance(AskSlots s, AskEntities ents) async {
    final asked = _slotCurrency(s);
    final named = s.accountIds;
    final rows = [
      for (final a in await accounts())
        if (named.isEmpty
            ? a.account.kind.isAsset
            : named.contains(a.account.id))
          a,
    ];
    final sums = <Currency, Money>{};
    final asOf = <Currency, DateTime>{};
    for (final a in rows) {
      for (final b in a.balances) {
        final m = b.balance;
        if (m == null) continue;
        if (asked != null && m.currency != asked) continue;
        sums[m.currency] = sums[m.currency] == null ? m : sums[m.currency]! + m;
        final prev = asOf[m.currency];
        if (prev == null || b.asOf.isAfter(prev)) asOf[m.currency] = b.asOf;
      }
    }
    if (sums.isEmpty) {
      return const AskNoDataAnswer(
        AskIntent.accountBalance,
        AskNoDataReason.noAccounts,
      );
    }
    final codes = sums.keys.toList()..sort((x, y) => x.code.compareTo(y.code));
    return AskBalanceAnswer(
      figures: [for (final c in codes) AskBalanceFigure(sums[c]!, asOf[c]!)],
      liability: rows.isNotEmpty && rows.every((a) => !a.account.kind.isAsset),
      accountLabel: rows.length == 1 && named.isNotEmpty
          ? rows.single.account.label
          : null,
    );
  }

  // ------------------------------------------------------------- budget

  Future<AskAnswer> _budget(AskSlots s, ChartPeriod cycle) async {
    final asked = _slotCurrency(s);
    final budgets = await cycleBudgets();
    final codes = [
      for (final c in budgets.keys)
        if (asked == null || c == asked) c,
    ]..sort((x, y) => x.code.compareTo(y.code));
    if (codes.isEmpty) {
      return const AskNoDataAnswer(
        AskIntent.budgetRemaining,
        AskNoDataReason.noBudget,
      );
    }
    final figures = <AskBudgetFigure>[];
    for (final c in codes) {
      final r = await charts.categoryDonut(cycle, ChartFilter(currency: c));
      final spent = r is ChartReady<CategoryDonut> ? r.data.total : Money(c, 0);
      final budget = budgets[c]!;
      figures.add(
        AskBudgetFigure(
          budget: budget,
          spent: spent,
          remaining: budget - spent,
        ),
      );
    }
    return AskBudgetAnswer(cycle: cycle, figures: figures);
  }

  // --------------------------------------------------------------- dues

  Future<AskAnswer> _dues(AskSlots s, CivilDate now) async {
    final end = now.plusDays(askDuesWindowDays);
    final year = ChartPeriod(now.plusDays(-365), now);
    final asked = _slotCurrency(s);
    final currencies =
        asked != null
              ? [asked]
              : {
                  ...await charts.currenciesWithActivity(year),
                  Currency.of('EGP'),
                }.toList()
          ..sort((x, y) => x.code.compareTo(y.code));
    final figures = <AskDuesFigure>[];
    for (final c in currencies) {
      final r = await charts.installmentTimeline(now, _filter(c, s), months: 3);
      if (r is! ChartReady<List<InstallmentMonth>>) continue;
      final dues =
          <InstallmentDue>[
            for (final m in r.data)
              for (final d in m.dues)
                if (d.overdue || d.date <= end) d,
          ]..sort((x, y) {
            final c = x.date.epochDay.compareTo(y.date.epochDay);
            return c != 0 ? c : x.itemId.compareTo(y.itemId);
          });
      if (dues.isEmpty) continue;
      figures.add(
        AskDuesFigure(
          total: dues.fold<Money>(Money(c, 0), (a, d) => a + d.amount),
          dues: dues,
        ),
      );
    }
    if (figures.isEmpty) {
      return const AskNoDataAnswer(
        AskIntent.upcomingDues,
        AskNoDataReason.noDues,
      );
    }
    return AskDuesAnswer(windowEnd: end, figures: figures);
  }

  // ------------------------------------------------------------ biggest

  Future<AskAnswer> _biggest(
    AskSlots s,
    ChartPeriod p,
    AskEntities ents,
  ) async {
    final out = <BiggestExpense>[];
    for (final c in await _currencies(p, s)) {
      final b = await charts.biggestExpense(
        p,
        _filter(c, s),
        categoryId: s.categoryId,
        merchantNorms: s.merchantIds,
      );
      if (b != null) out.add(b);
    }
    if (out.isEmpty) {
      return const AskNoDataAnswer(
        AskIntent.biggestExpense,
        AskNoDataReason.noTransactions,
      );
    }
    return AskBiggestAnswer(
      period: p,
      periodDefaulted: s.periodDefaulted,
      figures: out,
    );
  }

  // ------------------------------------------------------------ savings

  Future<AskAnswer> _savings(AskSlots s, ChartPeriod p) async {
    final figures = <AskSavingsFigure>[];
    var sawSpendOnly = false;
    for (final c in await _currencies(p, s)) {
      final r = await charts.cashFlow([p], _filter(c, s));
      if (r is! ChartReady<List<CashFlowPoint>>) continue;
      final pt = r.data.single;
      if (pt.income.isZero) {
        sawSpendOnly = true;
        continue;
      }
      figures.add(
        AskSavingsFigure(
          income: pt.income,
          spend: pt.spend,
          isPartial: pt.isPartial,
        ),
      );
    }
    if (figures.isEmpty) {
      return AskNoDataAnswer(
        AskIntent.savings,
        sawSpendOnly
            ? AskNoDataReason.noIncome
            : AskNoDataReason.noTransactions,
      );
    }
    return AskSavingsAnswer(
      period: p,
      periodDefaulted: s.periodDefaulted,
      figures: figures,
    );
  }

  // -------------------------------------------------------------- roast

  /// A roast uses ONE currency (the one with the most spend, or the one
  /// asked for): a joke about a figure never mixes currencies.
  Future<AskAnswer> _roast(
    AskSlots s,
    ChartPeriod p,
    int seed,
    Set<RoastKind> recent,
  ) async {
    Currency? best;
    CategoryDonut? bestDonut;
    for (final c in await _currencies(p, s)) {
      final r = await charts.categoryDonut(p, ChartFilter(currency: c));
      if (r is! ChartReady<CategoryDonut>) continue;
      if (bestDonut == null || r.data.total.minor > bestDonut.total.minor) {
        best = c;
        bestDonut = r.data;
      }
    }
    if (best == null || bestDonut == null) {
      return const AskNoDataAnswer(
        AskIntent.roast,
        AskNoDataReason.noTransactions,
      );
    }
    final f = ChartFilter(currency: best);
    final facts = <RoastFact>[];

    final top = bestDonut.slices.first;
    if (top.categoryId != null && top.shareBp >= roastTopCategoryShareBp) {
      facts.add(
        RoastFact(
          RoastKind.topCategory,
          amount: top.amount,
          shareBp: top.shareBp,
          categoryId: top.categoryId,
        ),
      );
    }
    final merchants = await charts.topMerchants(p, f, limit: 1);
    if (merchants is ChartReady<List<MerchantSpend>>) {
      final m = merchants.data.first;
      if (m.count >= roastMerchantMinVisits) {
        facts.add(
          RoastFact(
            RoastKind.merchantRegular,
            amount: m.amount,
            count: m.count,
            name: m.name,
          ),
        );
      }
    }
    final pattern = await charts.dayHourPattern(p, f);
    if (pattern is ChartReady<DayHourPattern>) {
      final all = pattern.data.byHour.values.fold<int>(
        0,
        (a, c) => a + c.count,
      );
      final late = [
        for (var h = 0; h < roastLateNightEndHour; h++) pattern.data.byHour[h]!,
      ].fold<int>(0, (a, c) => a + c.count);
      if (all > 0 && late * 10000 ~/ all >= roastLateNightShareBp) {
        facts.add(RoastFact(RoastKind.lateNight, count: late));
      }
      final days = pattern.data.byWeekday;
      final total = days.values.fold<int>(0, (a, c) => a + c.spend.minor);
      // Friday and Saturday are the Egyptian weekend.
      final weekend = days[5]!.spend.minor + days[6]!.spend.minor;
      if (total > 0 && weekend * 10000 ~/ total >= roastWeekendShareBp) {
        facts.add(
          RoastFact(
            RoastKind.weekendHeavy,
            amount: Money(best, weekend),
            shareBp: weekend * 10000 ~/ total,
          ),
        );
      }
    }
    final big = await charts.biggestExpense(p, f);
    if (big != null) {
      facts.add(
        RoastFact(
          RoastKind.biggestExpense,
          amount: big.amount,
          name: big.merchant,
        ),
      );
    }
    final subs = await charts.subscriptionsAnnual(f);
    if (subs is ChartReady<SubscriptionsAnnual> &&
        subs.data.items.length >= roastSubscriptionsMin) {
      facts.add(
        RoastFact(
          RoastKind.subscriptions,
          amount: subs.data.annualTotal,
          count: subs.data.items.length,
        ),
      );
    }
    facts.add(RoastFact(RoastKind.calm, amount: bestDonut.total));
    return AskRoastAnswer(
      period: p,
      fact: pickRoastFact(facts, seed, recent: recent),
    );
  }
}

/// Roast thresholds (basis points unless noted).
const int roastTopCategoryShareBp = 3000;
const int roastMerchantMinVisits = 4;
const int roastLateNightEndHour = 5;
const int roastLateNightShareBp = 1000;
const int roastWeekendShareBp = 4500;
const int roastSubscriptionsMin = 3;
