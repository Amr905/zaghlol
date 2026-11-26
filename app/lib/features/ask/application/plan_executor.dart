// T-342: the plan executor of the online helper (ask-llm.md section 3,
// ADR-027). Takes a plan that already passed PlanValidator and computes it
// on the phone over the repositories. It only reads: there is no network, no
// write and no logging here. Placeholders resolve through the in-memory mask
// map; a mention goes through the existing Ask matcher and, if it matches
// nothing, the answer is `LlmNotFoundAnswer` with chips, never a guess.
// Results are per currency, primary first; no two currencies are ever added
// and all rounding is integer, half-even once per figure.

import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../accounts/domain/account.dart';
import '../../insights/data/chart_repository.dart';
import '../../insights/domain/chart_models.dart';
import '../../insights/domain/chart_rules.dart';
import '../domain/ask_period.dart';
import '../domain/llm_answer_models.dart';
import 'ask_engine.dart'
    show AccountsSource, BudgetsSource, EntitiesSource, ScheduleSource;

/// The gold and FX prices the investment illustrations need.
typedef InvestPricesSource = Future<InvestPrices> Function();

/// Most chips offered after a name was not found.
const int llmMaxChips = 6;

/// Full periods a what-if / suggestion looks back over.
const int _basis = 3;

/// The category id of a closed-catalogue slug (system categories).
String llmCategoryIdOf(String slug) => 'sys:$slug';

class PlanExecutor {
  PlanExecutor({
    required this.charts,
    required this.accounts,
    required this.cycleBudgets,
    required this.schedule,
    required this.entities,
    required this.today,
    required this.prices,
    required this.now,
    Currency? primary,
    InvestThresholds? investThresholds,
    this.suggestThresholds = const SuggestThresholds(),
  }) : primary = primary ?? Currency.of('EGP'),
       investThresholds = investThresholds ?? InvestThresholds.defaults();

  final ChartRepository charts;
  final AccountsSource accounts;
  final BudgetsSource cycleBudgets;
  final ScheduleSource schedule;
  final EntitiesSource entities;
  final CivilDate Function() today;
  final InvestPricesSource prices;
  final DateTime Function() now;
  final Currency primary;
  final InvestThresholds investThresholds;
  final SuggestThresholds suggestThresholds;

  /// Computes [plan]. Never throws: a failed read is
  /// `LlmFallbackAnswer(failed)`.
  Future<LlmAnswer> execute(Plan plan, MaskMap map) async {
    try {
      final ctx = await _Ctx.load(this);
      return await _run(plan, map, ctx);
    } on Object {
      return const LlmFallbackAnswer(LlmFallbackReason.failed);
    }
  }

  Future<LlmAnswer> _run(Plan plan, MaskMap map, _Ctx x) async {
    switch (plan) {
      case PlanFallback(:final reason):
        return LlmFallbackAnswer(switch (reason) {
          FallbackReason.unsupported => LlmFallbackReason.unsupported,
          FallbackReason.ambiguous => LlmFallbackReason.ambiguous,
          FallbackReason.zakah => LlmFallbackReason.zakah,
          FallbackReason.noData => LlmFallbackReason.noData,
        });
      case PlanRefuse(:final reason, :final selfHarm):
        return LlmRefuseAnswer(reason, selfHarm: selfHarm);
      case PlanSpend(:final period, :final filter):
        return _spend(x, map, period, filter);
      case PlanCompare(:final periodA, :final periodB, :final filter):
        return _compare(x, map, periodA, periodB, filter);
      case PlanBreakdown(:final period, :final by, :final limit):
        return _breakdown(x, period, by, limit);
      case PlanTopN(:final period, :final of, :final n):
        return _topN(x, period, of, n);
      case PlanAverage(:final per, :final period, :final filter):
        return _average(x, map, per, period, filter);
      case PlanIncome(:final period, :final filter):
        return _income(x, map, period, filter);
      case PlanSaved(:final period):
        return _saved(x, period);
      case PlanBillsDue(:final windowDays):
        return _bills(x, windowDays);
      case PlanBudgetLeft(:final slug):
        return _budgetLeft(x, slug);
      case PlanSafeSpend():
        return _safeSpend(x);
      case PlanBalance(:final ref):
        return _balance(x, map, ref);
      case PlanWhatIfCut():
        return _whatIfCut(x, map, plan);
      case PlanWhatIfSave(:final amount, :final months):
        return _whatIfSave(amount, months);
      case PlanSuggest(:final currency):
        return _suggest(x, currency);
      case PlanInvest():
        return _invest(x, map, plan);
    }
  }

  // ----------------------------------------------------------- helpers

  AskPeriod _askPeriod(PlanPeriod p) => AskPeriod(
    AskPeriodKind.values.byName(p.kind.name),
    offset: p.offset,
    count: p.lastDays ?? 0,
    month: p.month ?? 0,
    year: p.year,
  );

  ChartPeriod _resolve(_Ctx x, PlanPeriod p) =>
      resolveAskPeriod(_askPeriod(p), x.today, x.schedule, firstDay: x.first);

  /// Primary first, then by code.
  List<Currency> _ordered(Iterable<Currency> cs) {
    final list = cs.toSet().toList()
      ..sort((a, b) {
        if (a == primary) return -1;
        if (b == primary) return 1;
        return a.code.compareTo(b.code);
      });
    return list;
  }

  Future<List<Currency>> _currencies(
    ChartPeriod span,
    String? asked, {
    Set<String> accountIds = const {},
  }) async {
    if (asked != null) {
      final c = Currency.tryOf(asked);
      return c == null ? const [] : [c];
    }
    return _ordered(
      await charts.currenciesWithActivity(span, accountIds: accountIds),
    );
  }

  Future<Money> _spendOf(
    ChartPeriod p,
    LlmTarget t,
    Currency c, {
    bool noAccounts = false,
  }) async {
    final f = ChartFilter(
      currency: c,
      accountIds: noAccounts ? const {} : t.accountIds,
    );
    if (t.kind == LlmTargetKind.merchant && t.merchantIds.isNotEmpty) {
      return (await charts.merchantSpend(p, f, t.merchantIds))?.amount ??
          Money.zero(c);
    }
    return (await charts.scopedSpend(p, f, categoryId: t.categoryId)).amount;
  }

  // ------------------------------------------------- filter resolution

  /// Either a target or the answer that ends the plan (not found, missing
  /// placeholder).
  Future<({LlmTarget? target, LlmAnswer? stop})> _target(
    _Ctx x,
    MaskMap map,
    PlanFilter f,
  ) async {
    if (f.slug != null) {
      return (
        target: LlmTarget.category(
          llmCategoryIdOf(f.slug!),
          slug: f.slug,
          label: x.categoryName(llmCategoryIdOf(f.slug!)),
        ),
        stop: null,
      );
    }
    if (f.ref != null) {
      final t = map[f.ref!];
      if (t == null) {
        return (
          target: null,
          stop: const LlmFallbackAnswer(LlmFallbackReason.missingPlaceholder),
        );
      }
      return _fromMask(x, t);
    }
    if (f.mention != null) {
      final parsed = parseAskQuestion(
        'صرفت كام على ${f.mention}',
        entities: x.ents,
      );
      if (parsed is AskUnderstood) {
        final s = parsed.slots;
        if (s.categoryId != null) {
          return (
            target: LlmTarget.category(
              s.categoryId!,
              label: x.categoryName(s.categoryId!),
            ),
            stop: null,
          );
        }
        if (s.merchantIds.isNotEmpty) {
          return (
            target: LlmTarget.merchants(
              s.merchantIds,
              label: x.merchantName(s.merchantIds.first),
            ),
            stop: null,
          );
        }
        if (s.accountIds.isNotEmpty) {
          return (target: LlmTarget.accounts(s.accountIds), stop: null);
        }
      }
      return (target: null, stop: x.notFound());
    }
    return (target: LlmTarget.everything, stop: null);
  }

  ({LlmTarget? target, LlmAnswer? stop}) _fromMask(_Ctx x, MaskTarget t) {
    switch (t.kind) {
      case MaskKind.merchant:
        final id = t.merchantId;
        if (id == null) return (target: null, stop: x.notFound());
        return (
          target: LlmTarget.merchants({id}, label: x.merchantName(id)),
          stop: null,
        );
      case MaskKind.account:
      case MaskKind.card:
      case MaskKind.bank:
        if (t.accountIds.isEmpty) return (target: null, stop: x.notFound());
        return (target: LlmTarget.accounts(t.accountIds.toSet()), stop: null);
    }
  }

  // ------------------------------------------------------------- spend

  Future<LlmAnswer> _spend(
    _Ctx x,
    MaskMap map,
    PlanPeriod pp,
    PlanFilter f,
  ) async {
    final r = await _target(x, map, f);
    if (r.stop != null) return r.stop!;
    final t = r.target!;
    final p = _resolve(x, pp);
    final figures = <Money>[];
    for (final c in await _currencies(
      p,
      f.currency,
      accountIds: t.accountIds,
    )) {
      final m = await _spendOf(p, t, c);
      if (m.isPositive) figures.add(m);
    }
    if (figures.isEmpty) {
      return const LlmFallbackAnswer(LlmFallbackReason.noData);
    }
    return LlmDataAnswer(period: p, target: t, figures: figures);
  }

  Future<LlmAnswer> _compare(
    _Ctx x,
    MaskMap map,
    PlanPeriod a,
    PlanPeriod b,
    PlanFilter f,
  ) async {
    final r = await _target(x, map, f);
    if (r.stop != null) return r.stop!;
    final t = r.target!;
    final pa = _resolve(x, a);
    final pb = _resolve(x, b);
    final span = ChartPeriod(
      pa.from < pb.from ? pa.from : pb.from,
      pa.to > pb.to ? pa.to : pb.to,
    );
    final figures = <LlmCompareFigure>[];
    for (final c in await _currencies(
      span,
      f.currency,
      accountIds: t.accountIds,
    )) {
      final cur = await _spendOf(pa, t, c);
      final prev = await _spendOf(pb, t, c);
      if (cur.isZero && prev.isZero) continue;
      figures.add(
        LlmCompareFigure(
          current: cur,
          previous: prev,
          deltaBp: deltaBp(cur.minor, prev.minor),
        ),
      );
    }
    if (figures.isEmpty) {
      return const LlmFallbackAnswer(LlmFallbackReason.noData);
    }
    return LlmCompareAnswer(
      periodA: pa,
      periodB: pb,
      target: t,
      figures: figures,
    );
  }

  // --------------------------------------------- breakdown and ranking

  Future<LlmAnswer> _breakdown(
    _Ctx x,
    PlanPeriod pp,
    BreakdownBy by,
    int limit,
  ) async {
    final p = _resolve(x, pp);
    final lists = <LlmRankedList>[];
    for (final c in await _currencies(p, null)) {
      final f = ChartFilter(currency: c);
      final list = switch (by) {
        BreakdownBy.category => await _categoryList(x, p, f, limit),
        BreakdownBy.merchant => await _merchantList(
          p,
          f,
          limit,
          withOther: true,
        ),
        BreakdownBy.account => await _accountList(p, f, limit),
      };
      if (list != null) lists.add(list);
    }
    if (lists.isEmpty) return const LlmFallbackAnswer(LlmFallbackReason.noData);
    return LlmBreakdownAnswer(period: p, by: by, lists: lists);
  }

  Future<LlmAnswer> _topN(_Ctx x, PlanPeriod pp, TopOf of, int n) async {
    final p = _resolve(x, pp);
    final lists = <LlmRankedList>[];
    for (final c in await _currencies(p, null)) {
      final f = ChartFilter(currency: c);
      final list = switch (of) {
        TopOf.category => await _categoryList(x, p, f, n, withOther: false),
        TopOf.merchant => await _merchantList(p, f, n, withOther: false),
        TopOf.expense => await _expenseList(p, f, n),
      };
      if (list != null) lists.add(list);
    }
    if (lists.isEmpty) return const LlmFallbackAnswer(LlmFallbackReason.noData);
    return LlmTopNAnswer(period: p, of: of, lists: lists);
  }

  Future<LlmRankedList?> _categoryList(
    _Ctx x,
    ChartPeriod p,
    ChartFilter f,
    int limit, {
    bool withOther = true,
  }) async {
    final totals = await charts.categoryTotals(p, f);
    if (totals.isEmpty) return null;
    final rows = totals.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final total = rows.fold<int>(0, (a, e) => a + e.value);
    final shown = rows.take(limit).toList();
    final rest = total - shown.fold<int>(0, (a, e) => a + e.value);
    return LlmRankedList(
      rows: [
        for (final e in shown)
          LlmRankedRow(
            id: e.key.isEmpty ? null : e.key,
            name: e.key.isEmpty ? null : x.categoryName(e.key),
            amount: Money(f.currency, e.value),
            shareBp: mulDivRound(e.value, 10000, total),
          ),
      ],
      other: withOther && rest > 0 ? Money(f.currency, rest) : null,
    );
  }

  Future<LlmRankedList?> _merchantList(
    ChartPeriod p,
    ChartFilter f,
    int limit, {
    required bool withOther,
  }) async {
    final r = await charts.topMerchants(p, f, limit: limit);
    if (r is! ChartReady<List<MerchantSpend>>) return null;
    final total = (await charts.scopedSpend(p, f)).amount.minor;
    final other = withOther
        ? await charts.otherMerchants(p, f, shown: limit)
        : null;
    return LlmRankedList(
      rows: [
        for (final m in r.data)
          LlmRankedRow(
            id: m.merchantNorm,
            name: m.name,
            amount: m.amount,
            shareBp: total > 0
                ? mulDivRound(m.amount.minor, 10000, total)
                : null,
          ),
      ],
      other: other?.amount,
    );
  }

  Future<LlmRankedList?> _accountList(
    ChartPeriod p,
    ChartFilter f,
    int limit,
  ) async {
    final r = await charts.cardsSplit(p, f);
    if (r is! ChartReady<List<CardSpend>>) return null;
    final rows = r.data.where((c) => c.spend.isPositive).toList();
    if (rows.isEmpty) return null;
    final shown = rows.take(limit).toList();
    final rest = rows
        .skip(limit)
        .fold<Money>(Money.zero(f.currency), (a, c) => a + c.spend);
    return LlmRankedList(
      rows: [
        for (final c in shown)
          LlmRankedRow(
            id: c.accountId,
            name: c.label,
            amount: c.spend,
            shareBp: c.shareBp,
          ),
      ],
      other: rest.isPositive ? rest : null,
    );
  }

  Future<LlmRankedList?> _expenseList(
    ChartPeriod p,
    ChartFilter f,
    int n,
  ) async {
    final rows = await charts.topExpenses(p, f, limit: n);
    if (rows.isEmpty) return null;
    return LlmRankedList(
      rows: [
        for (final e in rows)
          LlmRankedRow(
            id: e.id,
            name: e.merchant,
            amount: e.amount,
            date: e.date,
          ),
      ],
    );
  }

  // ----------------------------------------------------------- average

  Future<LlmAnswer> _average(
    _Ctx x,
    MaskMap map,
    AveragePer per,
    PlanPeriod pp,
    PlanFilter f,
  ) async {
    final r = await _target(x, map, f);
    if (r.stop != null) return r.stop!;
    final t = r.target!;
    final p = _resolve(x, pp);
    final u = _fullUnits(x, per, p);
    if (u == null) return const LlmFallbackAnswer(LlmFallbackReason.noData);
    final figures = <LlmAverageFigure>[];
    for (final c in await _currencies(
      u.range,
      f.currency,
      accountIds: t.accountIds,
    )) {
      final total = await _spendOf(u.range, t, c);
      if (!total.isPositive) continue;
      figures.add(
        LlmAverageFigure(
          total: total,
          units: u.units,
          average: total.mulDiv(1, u.units, MoneyRounding.halfEven),
        ),
      );
    }
    if (figures.isEmpty) {
      return const LlmFallbackAnswer(LlmFallbackReason.noData);
    }
    return LlmAverageAnswer(
      per: per,
      period: p,
      range: u.range,
      target: t,
      figures: figures,
      partialExcluded: u.partial,
    );
  }

  /// The part of [p] made of full units: nothing after yesterday (the
  /// current day is unfinished), nothing before the first transaction, and
  /// for weeks (Saturday start) and months (payday cycles) only whole ones.
  ({ChartPeriod range, int units, bool partial})? _fullUnits(
    _Ctx x,
    AveragePer per,
    ChartPeriod p,
  ) {
    var end = p.to;
    var start = p.from;
    if (end >= x.today) end = x.today.plusDays(-1);
    final first = x.first;
    if (first == null) return null;
    if (first > start) start = first;
    if (end < start) return null;
    switch (per) {
      case AveragePer.day:
        final r = ChartPeriod(start, end);
        return (range: r, units: r.lengthDays, partial: r != p);
      case AveragePer.week:
        final s = start.plusDays((6 - isoWeekday(start.epochDay) + 7) % 7);
        final k = s > end ? 0 : (end.difference(s) + 1) ~/ 7;
        if (k < 1) return null;
        final r = ChartPeriod(s, s.plusDays(7 * k - 1));
        return (range: r, units: k, partial: r != p);
      case AveragePer.month:
        var c = x.schedule.cycleOn(start);
        if (c.start < start) c = x.schedule.after(c);
        if (c.end > end) return null;
        final firstStart = c.start;
        var last = c;
        var k = 0;
        while (c.end <= end) {
          k++;
          last = c;
          c = x.schedule.after(c);
        }
        final r = ChartPeriod(firstStart, last.end);
        return (range: r, units: k, partial: r != p);
    }
  }

  // ------------------------------------------------- income and saved

  Future<LlmAnswer> _income(
    _Ctx x,
    MaskMap map,
    PlanPeriod pp,
    PlanFilter f,
  ) async {
    final r = await _target(x, map, f);
    if (r.stop != null) return r.stop!;
    final ids = r.target!.accountIds;
    final p = _resolve(x, pp);
    final figures = <Money>[];
    for (final c in await _currencies(p, f.currency, accountIds: ids)) {
      final pt = await _point(p, ChartFilter(currency: c, accountIds: ids));
      if (pt != null && pt.income.isPositive) figures.add(pt.income);
    }
    if (figures.isEmpty) {
      return const LlmFallbackAnswer(LlmFallbackReason.noData);
    }
    return LlmIncomeAnswer(period: p, figures: figures);
  }

  Future<CashFlowPoint?> _point(ChartPeriod p, ChartFilter f) async {
    final r = await charts.cashFlow([p], f);
    return r is ChartReady<List<CashFlowPoint>> ? r.data.single : null;
  }

  Future<LlmAnswer> _saved(_Ctx x, PlanPeriod pp) async {
    final p = _resolve(x, pp);
    final figures = <LlmSavedFigure>[];
    for (final c in await _currencies(p, null)) {
      final pt = await _point(p, ChartFilter(currency: c));
      if (pt == null || (pt.income.isZero && pt.spend.isZero)) continue;
      figures.add(LlmSavedFigure(income: pt.income, spend: pt.spend));
    }
    if (figures.isEmpty) {
      return const LlmFallbackAnswer(LlmFallbackReason.noData);
    }
    return LlmSavedAnswer(period: p, figures: figures);
  }

  // ------------------------------------------- bills, budget, balance

  Future<LlmAnswer> _bills(_Ctx x, int windowDays) async {
    final end = x.today.plusDays(windowDays);
    final year = ChartPeriod(x.today.plusDays(-365), x.today);
    final cs = _ordered({
      ...await charts.currenciesWithActivity(year),
      primary,
    });
    final figures = <LlmBillsFigure>[];
    for (final c in cs) {
      final r = await charts.installmentTimeline(
        x.today,
        ChartFilter(currency: c),
        months: 3,
      );
      if (r is! ChartReady<List<InstallmentMonth>>) continue;
      final dues =
          <InstallmentDue>[
            for (final m in r.data)
              for (final d in m.dues)
                if (d.overdue || d.date <= end) d,
          ]..sort((a, b) {
            final k = a.date.epochDay.compareTo(b.date.epochDay);
            return k != 0 ? k : a.itemId.compareTo(b.itemId);
          });
      if (dues.isEmpty) continue;
      figures.add(
        LlmBillsFigure(
          total: dues.fold<Money>(Money.zero(c), (a, d) => a + d.amount),
          dues: dues,
        ),
      );
    }
    return LlmBillsAnswer(windowEnd: end, figures: figures);
  }

  Future<LlmAnswer> _budgetLeft(_Ctx x, String? slug) async {
    final cycle = ChartPeriod.cycle(x.schedule.cycleOn(x.today));
    final catId = slug == null ? null : llmCategoryIdOf(slug);
    final budgets = catId == null
        ? await cycleBudgets()
        : await charts.categoryBudgets(catId);
    final figures = <LlmBudgetFigure>[];
    for (final c in _ordered(budgets.keys)) {
      final budget = budgets[c]!;
      final spent = (await charts.scopedSpend(
        cycle,
        ChartFilter(currency: c),
        categoryId: catId,
      )).amount;
      figures.add(
        LlmBudgetFigure(
          budget: budget,
          spent: spent,
          remaining: budget - spent,
        ),
      );
    }
    return LlmBudgetLeftAnswer(
      cycle: cycle,
      target: catId == null
          ? LlmTarget.everything
          : LlmTarget.category(catId, slug: slug, label: x.categoryName(catId)),
      figures: figures,
    );
  }

  Future<LlmAnswer> _safeSpend(_Ctx x) async {
    final cycle = x.schedule.cycleOn(x.today);
    final budgets = await cycleBudgets();
    final figures = <Money>[];
    for (final c in _ordered(budgets.keys)) {
      final spent = (await charts.scopedSpend(
        ChartPeriod.cycle(cycle),
        ChartFilter(currency: c),
      )).amount;
      final s = safeToSpend(
        budget: budgets[c],
        spend: spent,
        cycle: cycle,
        today: x.today,
      );
      if (s != null) figures.add(s);
    }
    // EC-24: no budget, no figure.
    return LlmSafeSpendAnswer(
      daysRemaining: cycle.daysRemaining(x.today),
      figures: figures,
    );
  }

  Future<LlmAnswer> _balance(_Ctx x, MaskMap map, String? ref) async {
    Set<String> named = const {};
    if (ref != null) {
      final t = map[ref];
      if (t == null) {
        return const LlmFallbackAnswer(LlmFallbackReason.missingPlaceholder);
      }
      if (t.kind == MaskKind.merchant || t.accountIds.isEmpty) {
        return x.notFound();
      }
      named = t.accountIds.toSet();
    }
    final rows = [
      for (final a in await accounts())
        if (named.isEmpty
            ? a.account.kind.isAsset
            : named.contains(a.account.id))
          a,
    ];
    // Named accounts one by one; with no name only asset accounts are summed
    // (a debit and a credit balance are never added).
    final perAccount = named.isNotEmpty;
    final sums = <String, Money>{};
    final asOf = <String, DateTime>{};
    final owner = <String, Account>{};
    for (final a in rows) {
      for (final b in a.balances) {
        final m = b.balance;
        if (m == null) continue;
        final k = perAccount
            ? '${a.account.id}|${m.currency.code}'
            : m.currency.code;
        sums[k] = sums[k] == null ? m : sums[k]! + m;
        owner[k] = a.account;
        final prev = asOf[k];
        if (prev == null || b.asOf.isAfter(prev)) asOf[k] = b.asOf;
      }
    }
    if (sums.isEmpty) return const LlmFallbackAnswer(LlmFallbackReason.noData);
    final keys = sums.keys.toList()
      ..sort((a, b) {
        final ca = sums[a]!.currency, cb = sums[b]!.currency;
        if (ca != cb) return _ordered([ca, cb]).first == ca ? -1 : 1;
        return a.compareTo(b);
      });
    return LlmBalanceAnswer(
      figures: [
        for (final k in keys)
          LlmBalanceFigure(
            balance: sums[k]!,
            asOf: asOf[k]!,
            accountLabel: perAccount ? owner[k]!.label : null,
            liability: perAccount && !owner[k]!.kind.isAsset,
          ),
      ],
    );
  }

  // ------------------------------------------------------------ what-if

  /// The last [_basis] full cycles before the current one, oldest first. A
  /// cycle that starts before the first transaction is partial (EC-23).
  List<ChartPeriod> _fullCycles(_Ctx x) {
    final first = x.first;
    if (first == null) return const [];
    final out = <ChartPeriod>[];
    var c = x.schedule.cycleOn(x.today);
    for (var i = 0; i < _basis; i++) {
      c = x.schedule.before(c);
      if (c.start < first) break;
      out.add(ChartPeriod.cycle(c));
    }
    return out.reversed.toList();
  }

  Money? _planMoney(PlanAmount? a, {String? currency}) {
    if (a == null) return null;
    return _money(a.amount, a.currency ?? currency);
  }

  Money? _money(String amount, String? currency) {
    final c = currency == null ? primary : Currency.tryOf(currency);
    if (c == null) return null;
    final minor = planAmountToMinor(amount, c.exponent);
    return minor == null ? null : Money(c, minor);
  }

  Future<({LlmWhatIfAnswer? answer, LlmAnswer? stop})> _cut(
    _Ctx x,
    MaskMap map,
    PlanWhatIfCut plan,
  ) async {
    final r = await _target(x, map, plan.target);
    if (r.stop != null) return (answer: null, stop: r.stop);
    final t = r.target!;
    final WhatIfMode mode;
    Currency? onlyCurrency;
    if (plan.mode.kind == WhatIfKind.percent) {
      final pct = plan.mode.percent;
      if (pct == null) {
        return (
          answer: null,
          stop: const LlmFallbackAnswer(LlmFallbackReason.failed),
        );
      }
      mode = WhatIfPercent(pct);
    } else {
      final m = plan.mode.amount == null
          ? null
          : _money(plan.mode.amount!, plan.mode.currency);
      if (m == null || m.minor <= 0) {
        return (
          answer: null,
          stop: const LlmFallbackAnswer(LlmFallbackReason.unsupported),
        );
      }
      mode = WhatIfAmount(m);
      onlyCurrency = m.currency;
    }
    final periods = _fullCycles(x);
    final spend = <Currency, List<Money>>{};
    if (periods.isNotEmpty) {
      final span = ChartPeriod(periods.first.from, periods.last.to);
      final cs = onlyCurrency != null
          ? [onlyCurrency]
          : await _currencies(
              span,
              plan.target.currency,
              accountIds: t.accountIds,
            );
      for (final c in cs) {
        final list = [for (final p in periods) await _spendOf(p, t, c)];
        if (list.any((m) => !m.isZero)) spend[c] = list;
      }
    }
    if (spend.isEmpty) {
      spend[onlyCurrency ?? primary] = const [];
    }
    final out = whatIfCutByCurrency(
      spendByCurrency: spend,
      mode: mode,
      months: plan.months,
    );
    return (
      answer: LlmWhatIfAnswer(
        target: t,
        months: plan.months,
        outcomes: [
          for (final c in _ordered(out.keys))
            LlmWhatIfOutcome(
              c,
              out[c] is WhatIfCutResult ? out[c]! as WhatIfCutResult : null,
            ),
        ],
      ),
      stop: null,
    );
  }

  Future<LlmAnswer> _whatIfCut(_Ctx x, MaskMap map, PlanWhatIfCut plan) async {
    final r = await _cut(x, map, plan);
    return r.stop ?? r.answer!;
  }

  LlmAnswer _whatIfSave(PlanAmount amount, int months) {
    final m = _planMoney(amount);
    if (m == null || m.minor <= 0) {
      return const LlmFallbackAnswer(LlmFallbackReason.unsupported);
    }
    return LlmWhatIfSaveAnswer(
      amount: m,
      months: months,
      total: whatIfSave(amount: m, months: months),
    );
  }

  // ------------------------------------------------------------ suggest

  Future<LlmAnswer> _suggest(_Ctx x, String? currency) async {
    final c = currency == null ? primary : Currency.tryOf(currency);
    if (c == null) return const LlmFallbackAnswer(LlmFallbackReason.noData);
    final f = ChartFilter(currency: c);
    final periods = _fullCycles(x);
    final cats = <CategorySpend>[];
    if (periods.length == _basis) {
      final totals = [
        for (final p in periods) await charts.categoryTotals(p, f),
      ];
      final ids = {for (final t in totals) ...t.keys}..remove('');
      for (final id in ids.toList()..sort()) {
        cats.add(
          CategorySpend(
            id: id,
            name: x.categoryName(id) ?? id,
            periods: [for (final t in totals) Money(c, t[id] ?? 0)],
          ),
        );
      }
    }
    final subs = await charts.subscriptionsAnnual(f);
    final costs = subs is ChartReady<SubscriptionsAnnual>
        ? [
            for (final s in subs.data.items)
              SuggestSubscriptionCost(
                name: s.name,
                monthly: s.annual.mulDiv(1, 12, MoneyRounding.halfEven),
              ),
          ]
        : <SuggestSubscriptionCost>[];
    Money? withdrawn;
    Money? unattributed;
    if (periods.isNotEmpty) {
      final pool = await charts.cashPool(periods.last, f);
      withdrawn = pool.withdrawn;
      unattributed = pool.unattributed;
    }
    final result = suggestSavings(
      inputs: [
        SuggestInputs(
          currency: c,
          categories: cats,
          subscriptions: costs,
          cashWithdrawn: withdrawn,
          cashUnattributed: unattributed,
        ),
      ],
      thresholds: suggestThresholds,
    );
    return LlmSuggestAnswer(perCurrency: result);
  }

  // ------------------------------------------------------------- invest

  Future<LlmAnswer> _invest(_Ctx x, MaskMap map, PlanInvest plan) async {
    // `index`: no licensed price feed (OQ-ASK-02), never shown.
    final instruments = <InvestInstrument>{
      for (final i in plan.instruments)
        ?switch (i) {
          Instrument.gold => InvestInstrument.gold,
          Instrument.usd => InvestInstrument.usd,
          Instrument.certificate => InvestInstrument.certificate,
          Instrument.indexFund => null,
        },
    };

    if (instruments.isEmpty) {
      return const LlmFallbackAnswer(LlmFallbackReason.unsupported);
    }
    final bases = <Money>[];
    final src = plan.source;
    switch (src.kind) {
      case InvestSourceKind.amount:
        final m = _planMoney(src.amount);
        if (m == null) return const LlmFallbackAnswer(LlmFallbackReason.failed);
        bases.add(m);
      case InvestSourceKind.whatIf:
        if (src.whatIf == null) {
          return const LlmFallbackAnswer(LlmFallbackReason.failed);
        }
        final r = await _cut(x, map, src.whatIf!);
        if (r.stop != null) return r.stop!;
        for (final o in r.answer!.outcomes) {
          final res = o.result;
          if (res != null) bases.add(res.monthlySaving);
        }
      case InvestSourceKind.savedLastPeriod:
        final last = _fullCycles(x);
        if (last.isEmpty) break;
        final p = last.last;
        for (final c in await _currencies(p, null)) {
          final pt = await _point(p, ChartFilter(currency: c));
          if (pt != null) bases.add(pt.income - pt.spend);
        }
    }
    if (bases.isEmpty) return const LlmFallbackAnswer(LlmFallbackReason.noData);
    final pr = await prices();
    final at = now();
    final figures = [
      for (final s in bases)
        LlmInvestFigure(
          saved: s,
          illustration: illustrate(
            saved: s,
            prices: pr,
            instruments: instruments,
            horizonMonths: plan.horizonMonths,
            now: at,
            thresholds: investThresholds,
          ),
        ),
    ];
    return LlmInvestAnswer(
      horizonMonths: plan.horizonMonths,
      figures: figures,
      instruments: instruments,
    );
  }
}

/// Values read once per `execute`.
final class _Ctx {
  _Ctx._(this.today, this.schedule, this.first, this.ents);

  final CivilDate today;
  final PaydaySchedule schedule;
  final CivilDate? first;
  final AskEntities ents;

  static Future<_Ctx> load(PlanExecutor e) async => _Ctx._(
    e.today(),
    await e.schedule(),
    await e.charts.firstDataDay(),
    await e.entities(),
  );

  String? categoryName(String id) => _name(ents.categories, id);
  String? merchantName(String id) => _name(ents.merchants, id);

  static String? _name(List<AskEntity> list, String id) {
    for (final e in list) {
      if (e.id == id && e.names.isNotEmpty) return e.names.first;
    }
    return null;
  }

  /// Chips of the user's own names: a few categories, the most used
  /// merchants (the list is ordered that way) and the accounts.
  LlmNotFoundAnswer notFound() => LlmNotFoundAnswer([
    for (final e in ents.categories.take(llmMaxChips ~/ 2))
      if (e.names.isNotEmpty)
        LlmChip(LlmChipKind.category, e.id, e.names.first),
    for (final e in ents.merchants.take(llmMaxChips ~/ 3))
      if (e.names.isNotEmpty)
        LlmChip(LlmChipKind.merchant, e.id, e.names.first),
    for (final e in ents.accounts.take(llmMaxChips ~/ 3))
      if (e.names.isNotEmpty) LlmChip(LlmChipKind.account, e.id, e.names.first),
  ]);
}
