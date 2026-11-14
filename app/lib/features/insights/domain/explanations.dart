// T-106: the "Explain this chart" engine (FR-CHT-03, copy deck §2.0.1 and
// §2.4, OQ-07). Pure Dart, no Flutter, no l10n: it picks the salient fact and
// the tip by rule and returns ExplanationLine values (an l10n key plus typed
// arguments taken from the T-105 chart results). The presentation layer
// (T-108) renders each line with the generated AppLocalizations method of the
// same name, per locale, so the numbers shown are exactly the query results.
//
// Tiers: basic (Free and Gold) = fact + tip. Deep (Gold only) = fact + deep
// comparison + deep tip (+ projection / drivers on charts 1, 2, 3, 5, 7).
// A basic tier call never reads a "previous" input, so Free can't leak deep
// content. A sentence whose values can't be computed is dropped whole.
//
// Voice rules honoured here: no "not financial advice" line (Q-20), no halal
// wording (Q-24), a tip never targets an essential category (Q-25), alerts
// stay calm (no emoji, in the copy). Nothing here logs.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'chart_models.dart';
import 'chart_rules.dart';

/// Which part of the explanation a line is (bubble class E or S, §2.4).
enum ExplanationPart { fact, tip, deepFact, deepTip, projection, drivers }

/// The l10n keys the engine emits; [l10nKey] is the generated getter/method
/// name (ARB key) and [part] says where the line sits.
enum ExplanationKey {
  cashFlowBasic('insightsExplainCashFlowBasic', ExplanationPart.fact),
  cashFlowTip('insightsExplainCashFlowTip', ExplanationPart.tip),
  cashFlowDeep('insightsExplainCashFlowDeep', ExplanationPart.deepFact),
  cashFlowDeepTip('insightsExplainCashFlowDeepTip', ExplanationPart.deepTip),
  categoriesBasic('insightsExplainCategoriesBasic', ExplanationPart.fact),
  categoriesTip('insightsExplainCategoriesTip', ExplanationPart.tip),
  categoriesDeep('insightsExplainCategoriesDeep', ExplanationPart.deepFact),
  categoriesDeepTip(
    'insightsExplainCategoriesDeepTip',
    ExplanationPart.deepTip,
  ),
  burnRateBasic('insightsExplainBurnRateBasic', ExplanationPart.fact),
  burnRateTip('insightsExplainBurnRateTip', ExplanationPart.tip),
  burnRateDeep('insightsExplainBurnRateDeep', ExplanationPart.deepFact),
  burnRateDeepTip('insightsExplainBurnRateDeepTip', ExplanationPart.deepTip),
  rule503020Basic('insightsExplainRule503020Basic', ExplanationPart.fact),
  rule503020Tip('insightsExplainRule503020Tip', ExplanationPart.tip),
  rule503020Deep('insightsExplainRule503020Deep', ExplanationPart.deepFact),
  rule503020DeepTip(
    'insightsExplainRule503020DeepTip',
    ExplanationPart.deepTip,
  ),
  weekPatternBasic('insightsExplainWeekPatternBasic', ExplanationPart.fact),
  weekPatternTip('insightsExplainWeekPatternTip', ExplanationPart.tip),
  weekPatternDeep('insightsExplainWeekPatternDeep', ExplanationPart.deepFact),
  weekPatternDeepTip(
    'insightsExplainWeekPatternDeepTip',
    ExplanationPart.deepTip,
  ),
  merchantsBasic('insightsExplainMerchantsBasic', ExplanationPart.fact),
  merchantsTip('insightsExplainMerchantsTip', ExplanationPart.tip),
  merchantsDeep('insightsExplainMerchantsDeep', ExplanationPart.deepFact),
  merchantsDeepTip('insightsExplainMerchantsDeepTip', ExplanationPart.deepTip),
  vsAverageBasic('insightsExplainVsAverageBasic', ExplanationPart.fact),
  vsAverageTip('insightsExplainVsAverageTip', ExplanationPart.tip),
  vsAverageDeep('insightsExplainVsAverageDeep', ExplanationPart.deepFact),
  vsAverageDeepTip('insightsExplainVsAverageDeepTip', ExplanationPart.deepTip),
  installmentsBasic('insightsExplainInstallmentsBasic', ExplanationPart.fact),
  installmentsTip('insightsExplainInstallmentsTip', ExplanationPart.tip),
  installmentsDeep('insightsExplainInstallmentsDeep', ExplanationPart.deepFact),
  installmentsDeepTip(
    'insightsExplainInstallmentsDeepTip',
    ExplanationPart.deepTip,
  ),
  subscriptionsBasic('insightsExplainSubscriptionsBasic', ExplanationPart.fact),
  subscriptionsTip('insightsExplainSubscriptionsTip', ExplanationPart.tip),
  subscriptionsDeep(
    'insightsExplainSubscriptionsDeep',
    ExplanationPart.deepFact,
  ),
  subscriptionsDeepTip(
    'insightsExplainSubscriptionsDeepTip',
    ExplanationPart.deepTip,
  ),
  cardsBasic('insightsExplainCardsBasic', ExplanationPart.fact),
  cardsTip('insightsExplainCardsTip', ExplanationPart.tip),
  cardsDeep('insightsExplainCardsDeep', ExplanationPart.deepFact),
  cardsDeepTip('insightsExplainCardsDeepTip', ExplanationPart.deepTip),
  netWorthBasic('insightsExplainNetWorthBasic', ExplanationPart.fact),
  netWorthTip('insightsExplainNetWorthTip', ExplanationPart.tip),
  netWorthDeep('insightsExplainNetWorthDeep', ExplanationPart.deepFact),
  netWorthDeepTip('insightsExplainNetWorthDeepTip', ExplanationPart.deepTip),
  inflationBasic('insightsExplainInflationBasic', ExplanationPart.fact),
  inflationTip('insightsExplainInflationTip', ExplanationPart.tip),
  inflationDeep('insightsExplainInflationDeep', ExplanationPart.deepFact),
  inflationDeepTip('insightsExplainInflationDeepTip', ExplanationPart.deepTip),
  deepProjection('insightsDeepProjection', ExplanationPart.projection),
  deepDrivers('insightsDeepDrivers', ExplanationPart.drivers);

  const ExplanationKey(this.l10nKey, this.part);
  final String l10nKey;
  final ExplanationPart part;

  /// Deep-only lines: never in a basic explanation.
  bool get isDeepOnly =>
      part == ExplanationPart.deepFact ||
      part == ExplanationPart.deepTip ||
      part == ExplanationPart.projection ||
      part == ExplanationPart.drivers;
}

/// A typed template argument. The renderer formats it for the locale
/// (digits, currency, dates); the engine never builds user-facing text.
sealed class ExplanationArg {
  const ExplanationArg();
}

final class MoneyArg extends ExplanationArg {
  const MoneyArg(this.money);
  final Money money;
}

/// An amount in a non-currency unit (a gold unit) or a currency code; net
/// worth is one unit at a time.
final class UnitAmountArg extends ExplanationArg {
  const UnitAmountArg(this.unit, this.minor);
  final String unit;
  final int minor;
}

/// Basis points: 10000 is 100%.
final class PercentArg extends ExplanationArg {
  const PercentArg(this.bp);
  final int bp;
}

final class CountArg extends ExplanationArg {
  const CountArg(this.count);
  final int count;
}

/// A user-data name (merchant, card, commitment): shown as is.
final class NameArg extends ExplanationArg {
  const NameArg(this.name);
  final String name;
}

/// A category by id; null is uncategorized. The renderer localises the name.
final class CategoryArg extends ExplanationArg {
  const CategoryArg(this.categoryId);
  final String? categoryId;
}

/// A `common_assetType_*` code.
final class AssetTypeArg extends ExplanationArg {
  const AssetTypeArg(this.type);
  final String type;
}

/// ISO weekday 1 (Monday) .. 7 (Sunday).
final class WeekdayArg extends ExplanationArg {
  const WeekdayArg(this.isoWeekday);
  final int isoWeekday;
}

/// Local hour 0..23 (the renderer shows "around 9 pm").
final class HourArg extends ExplanationArg {
  const HourArg(this.hour);
  final int hour;
}

final class MonthArg extends ExplanationArg {
  const MonthArg(this.year, this.month);
  final int year;
  final int month;
}

/// A `select` branch (`state`, `trend`).
final class SelectArg extends ExplanationArg {
  const SelectArg(this.value);
  final String value;
}

/// One rendered-later sentence: [key] plus placeholder name -> value.
final class ExplanationLine {
  ExplanationLine(this.key, Map<String, ExplanationArg> args)
    : args = Map.unmodifiable(args);

  final ExplanationKey key;
  final Map<String, ExplanationArg> args;

  Money? money(String name) => switch (args[name]) {
    MoneyArg(:final money) => money,
    _ => null,
  };

  String? select(String name) => switch (args[name]) {
    SelectArg(:final value) => value,
    _ => null,
  };

  @override
  String toString() => 'ExplanationLine(${key.name})';
}

final class Explanation {
  Explanation(this.chart, this.tier, List<ExplanationLine> lines)
    : lines = List.unmodifiable(lines);

  final ChartId chart;
  final ExplanationTier tier;
  final List<ExplanationLine> lines;

  /// Nothing could be computed honestly; the screen shows needs-data.
  bool get isEmpty => lines.isEmpty;

  ExplanationLine? firstOf(ExplanationPart part) {
    for (final l in lines) {
      if (l.key.part == part) return l;
    }
    return null;
  }

  /// Free users see the deep upsell once under the basic tip (§2.0.1 rule 4).
  bool get offersDeepUpsell =>
      tier == ExplanationTier.basic && firstOf(ExplanationPart.tip) != null;
}

enum ExplanationTier { basic, deep }

/// Basic for Free, deep for Gold (T-119 decides who is Gold; this only maps
/// the boolean).
ExplanationTier tierFor({required bool isGold}) =>
    isGold ? ExplanationTier.deep : ExplanationTier.basic;

/// The `need` select of `insightsChartDetailNeedsData` for a chart that has
/// no data yet (EC-23).
String needsDataFor(ChartId chart, NotEnoughReason reason) {
  switch (chart) {
    case ChartId.netWorth:
      return 'accounts';
    case ChartId.installmentTimeline:
      return 'installments';
    case ChartId.subscriptionsAnnual:
      return 'subscriptions';
    case ChartId.monthVsAverage:
      return 'months';
    default:
      break;
  }
  return switch (reason) {
    NotEnoughReason.tooFewCycles => 'months',
    NotEnoughReason.tooFewSnapshots => 'accounts',
    NotEnoughReason.noData || NotEnoughReason.tooFewTransactions => 'cycle',
    _ => 'other',
  };
}

/// Category codes that tips never target (PO Q-25). The caller may pass its
/// own set (catalog ids); this is the seed default.
const Set<String> defaultEssentialCategoryIds = {
  'rent',
  'bills',
  'utilities',
  'groceries',
  'health',
  'education',
  'fees',
  'debt',
  'installments',
  'transport_work',
};

/// What the engine needs besides the chart's own result.
final class ExplainContext {
  ExplainContext({
    Set<String> essentialCategoryIds = defaultEssentialCategoryIds,
    Set<String> protectedMerchantNorms = const {},
    this.burn,
    this.merchants = const [],
    this.previousMerchants = const [],
    this.totalSpend,
  }) : essentialCategoryIds = Set.unmodifiable(essentialCategoryIds),
       protectedMerchantNorms = Set.unmodifiable(protectedMerchantNorms);

  /// Never the subject of a "cut / cap / trim" tip (Q-25).
  final Set<String> essentialCategoryIds;

  /// Merchants (landlord, school) that tips never name.
  final Set<String> protectedMerchantNorms;

  /// Deep extras: the burn curve (projection) and the merchants of this and
  /// the previous period (drivers). Read in the deep tier only.
  final BurnCurve? burn;
  final List<MerchantSpend> merchants;
  final List<MerchantSpend> previousMerchants;

  /// Net spend of the period, for the "top three" share.
  final Money? totalSpend;

  bool isEssential(String? id) =>
      id != null && essentialCategoryIds.contains(id);
}

// ------------------------------------------------------------------ inputs

/// One chart's explanation input. `previous*` fields are the previous cycle
/// (Gold only); the basic tier never reads them.
sealed class ExplainInput {
  const ExplainInput();
  ChartId get chart;
}

final class CashFlowExplainInput extends ExplainInput {
  const CashFlowExplainInput({
    required this.current,
    this.previous,
    this.categories = const [],
  });
  final CashFlowPoint current;
  final CashFlowPoint? previous;

  /// This period's category slices (for the "trim" tip).
  final List<CategorySlice> categories;
  @override
  ChartId get chart => ChartId.cashFlow;
}

final class CategoriesExplainInput extends ExplainInput {
  const CategoriesExplainInput({required this.current, this.previous});
  final CategoryDonut current;
  final CategoryDonut? previous;
  @override
  ChartId get chart => ChartId.categoryDonut;
}

final class BurnRateExplainInput extends ExplainInput {
  const BurnRateExplainInput({required this.current, this.previous});
  final BurnCurve current;
  final BurnCurve? previous;
  @override
  ChartId get chart => ChartId.burnCurve;
}

final class Rule503020ExplainInput extends ExplainInput {
  const Rule503020ExplainInput({required this.current, this.previous});
  final FiftyThirtyTwenty current;
  final FiftyThirtyTwenty? previous;
  @override
  ChartId get chart => ChartId.fiftyThirtyTwenty;
}

final class WeekPatternExplainInput extends ExplainInput {
  const WeekPatternExplainInput({
    required this.current,
    required this.period,
    this.previous,
    this.previousPeriod,
  });
  final DayHourPattern current;
  final ChartPeriod period;
  final DayHourPattern? previous;
  final ChartPeriod? previousPeriod;
  @override
  ChartId get chart => ChartId.dayHourPattern;
}

final class MerchantsExplainInput extends ExplainInput {
  const MerchantsExplainInput({
    required this.current,
    this.previous = const [],
  });
  final List<MerchantSpend> current;
  final List<MerchantSpend> previous;
  @override
  ChartId get chart => ChartId.topMerchants;
}

final class VsAverageExplainInput extends ExplainInput {
  const VsAverageExplainInput({required this.current});
  final MonthVsAverage current;
  @override
  ChartId get chart => ChartId.monthVsAverage;
}

/// A commitment's last due date (the chart rows alone don't say when it ends).
final class InstallmentEnd {
  const InstallmentEnd({
    required this.itemId,
    required this.name,
    required this.endsOn,
    required this.monthly,
  });
  final String itemId;
  final String name;
  final CivilDate endsOn;
  final Money monthly;
}

final class InstallmentsExplainInput extends ExplainInput {
  const InstallmentsExplainInput({
    required this.months,
    required this.ends,
    required this.today,
  });

  /// The timeline, first entry = the current month.
  final List<InstallmentMonth> months;
  final List<InstallmentEnd> ends;
  final CivilDate today;
  @override
  ChartId get chart => ChartId.installmentTimeline;
}

final class SubscriptionsExplainInput extends ExplainInput {
  const SubscriptionsExplainInput({required this.current, this.threeMonthsAgo});
  final SubscriptionsAnnual current;
  final SubscriptionsAnnual? threeMonthsAgo;
  @override
  ChartId get chart => ChartId.subscriptionsAnnual;
}

final class CardsExplainInput extends ExplainInput {
  const CardsExplainInput({
    required this.current,
    this.previous = const [],
    this.utilisationBpByAccount = const {},
  });
  final List<CardSpend> current;
  final List<CardSpend> previous;

  /// Credit-limit use per credit account, in basis points.
  final Map<String, int> utilisationBpByAccount;
  @override
  ChartId get chart => ChartId.cardsSplit;
}

final class NetWorthExplainInput extends ExplainInput {
  const NetWorthExplainInput({
    required this.points,
    this.assetsByTypeLatest = const {},
    this.assetsByTypeFirst = const {},
  });

  /// One unit, oldest first.
  final List<NetWorthPoint> points;

  /// Asset value per `common_assetType_*` code (minor units of the unit).
  final Map<String, int> assetsByTypeLatest;
  final Map<String, int> assetsByTypeFirst;
  @override
  ChartId get chart => ChartId.netWorth;
}

final class InflationBasketPoint {
  const InflationBasketPoint(this.year, this.month, this.average);
  final int year;
  final int month;
  final Money average;
}

final class InflationExplainInput extends ExplainInput {
  const InflationExplainInput({
    required this.basket,
    this.biggestRiseCategoryId,
    this.deliveryNow,
    this.deliveryBefore,
    this.basketVisitsPerMonth,
  });

  /// Average supermarket basket per month, oldest first.
  final List<InflationBasketPoint> basket;
  final String? biggestRiseCategoryId;
  final Money? deliveryNow;
  final Money? deliveryBefore;
  final int? basketVisitsPerMonth;
  @override
  ChartId get chart => ChartId.personalInflation;
}

// ------------------------------------------------------------------ engine

/// "About the same" band: within 1% of the base.
const int _sameBandBp = 100;

/// Tips size a saving at a tenth of the figure (a small, believable step).
const int _stepNum = 1;
const int _stepDen = 10;

const int _cyclesPerYear = 12;
const int _weeksPerYear = 52;

/// Explains [input] in [tier]. Returns an empty explanation when the basic
/// fact itself can't be computed (the deep lines then aren't shown either).
Explanation explainChart(
  ExplainInput input,
  ExplanationTier tier, {
  ExplainContext? context,
}) {
  final ctx = context ?? ExplainContext();
  final deep = tier == ExplanationTier.deep;
  final b = _Builder(deep);
  switch (input) {
    case CashFlowExplainInput():
      _cashFlow(b, input, ctx);
    case CategoriesExplainInput():
      _categories(b, input, ctx);
    case BurnRateExplainInput():
      _burnRate(b, input);
    case Rule503020ExplainInput():
      _rule503020(b, input);
    case WeekPatternExplainInput():
      _weekPattern(b, input);
    case MerchantsExplainInput():
      _merchants(b, input, ctx);
    case VsAverageExplainInput():
      _vsAverage(b, input, ctx);
    case InstallmentsExplainInput():
      _installments(b, input);
    case SubscriptionsExplainInput():
      _subscriptions(b, input);
    case CardsExplainInput():
      _cards(b, input);
    case NetWorthExplainInput():
      _netWorth(b, input);
    case InflationExplainInput():
      _inflation(b, input);
  }
  if (b.fact == null) {
    return Explanation(input.chart, tier, const []);
  }
  if (deep) {
    _extras(b, input, ctx);
  }
  return Explanation(input.chart, tier, b.build());
}

/// Collects the parts, then lays them out per tier: basic = fact + tip, deep
/// = fact + deep + deep tip + extras (deep tip replaces the basic tip).
final class _Builder {
  _Builder(this.deep);
  final bool deep;
  ExplanationLine? fact;
  ExplanationLine? tip;
  ExplanationLine? deepFact;
  ExplanationLine? deepTip;
  final List<ExplanationLine> extras = [];

  List<ExplanationLine> build() {
    final f = fact!;
    if (!deep) return [f, ?tip];
    return [f, ?deepFact, ?deepTip, ...extras];
  }
}

ExplanationLine _line(ExplanationKey k, Map<String, ExplanationArg> a) =>
    ExplanationLine(k, a);

SelectArg _trend(int current, int base) {
  final diff = current - base;
  if (diff == 0) return const SelectArg('other');
  if (base > 0 && diff.abs() * 10000 < _sameBandBp * base) {
    return const SelectArg('other');
  }
  return SelectArg(diff > 0 ? 'up' : 'down');
}

Money _step(Money m) => m.mulDiv(_stepNum, _stepDen, MoneyRounding.floor);

Money _yearly(Money perCycle, [int times = _cyclesPerYear]) =>
    perCycle.times(times);

List<CategorySlice> _byAmount(List<CategorySlice> slices) =>
    [...slices]..sort((a, c) => c.amount.minor.compareTo(a.amount.minor));

List<CategorySlice> _named(List<CategorySlice> slices) =>
    _byAmount(slices.where((s) => s.categoryId != null).toList());

CategorySlice? _largestTippable(List<CategorySlice> slices, ExplainContext c) {
  for (final s in _named(slices)) {
    if (s.amount.isPositive && !c.isEssential(s.categoryId)) return s;
  }
  return null;
}

// 1 cash flow
void _cashFlow(_Builder b, CashFlowExplainInput i, ExplainContext ctx) {
  final p = i.current;
  if (p.income.isZero && p.spend.isZero) return;
  final net = p.net;
  final short = net.isNegative;
  if (short) {
    b.fact = _line(ExplanationKey.cashFlowBasic, {
      'state': const SelectArg('short'),
      'income': MoneyArg(p.income),
      'spent': MoneyArg(p.spend),
      'gap': MoneyArg(-net),
    });
    final cat = _largestTippable(i.categories, ctx);
    if (cat != null) {
      final target = -net < cat.amount ? -net : cat.amount;
      // Only honest when trimming that category really closes the gap.
      if (cat.amount >= -net) {
        b.tip = _line(ExplanationKey.cashFlowTip, {
          'state': const SelectArg('short'),
          'category': CategoryArg(cat.categoryId),
          'target': MoneyArg(target),
        });
      }
    }
  } else {
    if (p.income.isZero) return;
    b.fact = _line(ExplanationKey.cashFlowBasic, {
      'state': const SelectArg('other'),
      'income': MoneyArg(p.income),
      'spent': MoneyArg(p.spend),
      'saved': MoneyArg(net),
      'percent': PercentArg(mulDivRound(net.minor, 10000, p.income.minor)),
    });
    final target = net.mulDiv(1, 2, MoneyRounding.floor);
    if (target.isPositive) {
      b.tip = _line(ExplanationKey.cashFlowTip, {
        'state': const SelectArg('other'),
        'target': MoneyArg(target),
      });
    }
  }
  if (!b.deep) return;
  final prev = i.previous;
  if (prev != null) {
    final delta = (net - prev.net).abs();
    b.deepFact = _line(ExplanationKey.cashFlowDeep, {
      'trend': _trend(net.minor, prev.net.minor),
      'delta': MoneyArg(delta),
    });
  }
  if (net.isPositive) {
    b.deepTip = _line(ExplanationKey.cashFlowDeepTip, {
      'target': MoneyArg(net),
      'yearly': MoneyArg(_yearly(net)),
    });
  }
}

// 2 categories
void _categories(_Builder b, CategoriesExplainInput i, ExplainContext ctx) {
  final named = _named(i.current.slices);
  if (named.length < 2 || !named[0].amount.isPositive) return;
  b.fact = _line(ExplanationKey.categoriesBasic, {
    'category': CategoryArg(named[0].categoryId),
    'percent': PercentArg(named[0].shareBp),
    'amount': MoneyArg(named[0].amount),
    'category2': CategoryArg(named[1].categoryId),
    'percent2': PercentArg(named[1].shareBp),
  });
  final tippable = _largestTippable(i.current.slices, ctx);
  final target = tippable == null ? null : _step(tippable.amount);
  if (tippable != null && target!.isPositive) {
    b.tip = _line(ExplanationKey.categoriesTip, {
      'category': CategoryArg(tippable.categoryId),
      'target': MoneyArg(target),
    });
  }
  if (!b.deep) return;
  final prev = i.previous;
  if (prev != null) {
    final before = prev.slices
        .where((s) => s.categoryId == named[0].categoryId)
        .firstOrNull;
    if (before != null) {
      b.deepFact = _line(ExplanationKey.categoriesDeep, {
        'trend': _trend(named[0].amount.minor, before.amount.minor),
        'category': CategoryArg(named[0].categoryId),
        'delta': MoneyArg((named[0].amount - before.amount).abs()),
      });
    }
  }
  if (tippable != null && target!.isPositive) {
    b.deepTip = _line(ExplanationKey.categoriesDeepTip, {
      'category': CategoryArg(tippable.categoryId),
      'target': MoneyArg(target),
      'yearly': MoneyArg(_yearly(target)),
    });
  }
}

// 3 burn rate
Money? _perDay(BurnCurve c) {
  final budget = c.budget;
  if (budget == null || c.cumulative.isEmpty) return null;
  final left = budget - c.cumulative.last;
  final days = c.cycle.length - c.elapsedDays + 1;
  if (days < 1) return null;
  if (!left.isPositive) return Money.zero(budget.currency);
  return left.mulDiv(1, days, MoneyRounding.floor);
}

void _burnRate(_Builder b, BurnRateExplainInput i) {
  final c = i.current;
  final budget = c.budget;
  if (budget == null || c.cumulative.isEmpty || c.elapsedDays < 1) return;
  final spent = c.cumulative.last;
  final ideal = c.idealAt(c.elapsedDays)!;
  final over = spent > ideal;
  final perDay = _perDay(c)!;
  b.fact = _line(ExplanationKey.burnRateBasic, {
    'state': SelectArg(over ? 'over' : 'other'),
    'cycleDay': CountArg(c.elapsedDays),
    'spent': MoneyArg(spent),
    'budget': MoneyArg(budget),
    'perDay': MoneyArg(perDay),
  });
  if (perDay.isPositive) {
    b.tip = _line(ExplanationKey.burnRateTip, {
      'state': SelectArg(over ? 'over' : 'other'),
      'perDay': MoneyArg(perDay),
    });
  }
  if (!b.deep) return;
  final prev = i.previous;
  if (prev != null &&
      prev.cumulative.length >= c.elapsedDays &&
      prev.cumulative.first.currency == spent.currency) {
    final then = prev.cumulative[c.elapsedDays - 1];
    b.deepFact = _line(ExplanationKey.burnRateDeep, {
      'trend': _trend(spent.minor, then.minor),
      'delta': MoneyArg((spent - then).abs()),
    });
  }
  final projected = c.projectedTotal;
  final days = c.cycle.length - c.elapsedDays + 1;
  if (projected != null && projected > budget && days >= 1) {
    final target = (projected - budget).mulDiv(1, days, MoneyRounding.ceil);
    b.deepTip = _line(ExplanationKey.burnRateDeepTip, {
      'target': MoneyArg(target),
    });
  }
}

// 4 fifty / thirty / twenty
void _rule503020(_Builder b, Rule503020ExplainInput i) {
  final c = i.current;
  if (!c.income.isPositive) return;
  final needs = c.shareBp(c.needs);
  final wants = c.shareBp(c.wants);
  final savings = c.shareBp(c.savings);
  final state = wants > FiftyThirtyTwenty.targetWantsBp
      ? 'wantsHigh'
      : savings < FiftyThirtyTwenty.targetSavingsBp
      ? 'savingsLow'
      : 'other';
  b.fact = _line(ExplanationKey.rule503020Basic, {
    'state': SelectArg(state),
    'needsPct': PercentArg(needs),
    'wantsPct': PercentArg(wants),
    'savingsPct': PercentArg(savings),
  });
  final Money target = switch (state) {
    'wantsHigh' =>
      c.wants -
          c.income.mulDiv(
            FiftyThirtyTwenty.targetWantsBp,
            10000,
            MoneyRounding.floor,
          ),
    'savingsLow' =>
      c.income.mulDiv(
            FiftyThirtyTwenty.targetSavingsBp,
            10000,
            MoneyRounding.floor,
          ) -
          c.savings,
    _ => c.income.mulDiv(500, 10000, MoneyRounding.floor),
  };
  if (target.isPositive) {
    b.tip = _line(ExplanationKey.rule503020Tip, {
      'state': SelectArg(state),
      'target': MoneyArg(target),
    });
  }
  if (!b.deep) return;
  final prev = i.previous;
  if (prev != null && prev.income.isPositive) {
    b.deepFact = _line(ExplanationKey.rule503020Deep, {
      'trend': _trend(savings, prev.shareBp(prev.savings)),
      'savingsPct': PercentArg(savings),
    });
  }
  final nextStep = (savings ~/ 500) * 500 + 500;
  if (nextStep <= 10000) {
    final reach = c.income.mulDiv(nextStep, 10000, MoneyRounding.floor);
    b.deepTip = _line(ExplanationKey.rule503020DeepTip, {
      'percent': PercentArg(nextStep),
      'yearly': MoneyArg(_yearly(reach)),
    });
  }
}

// 5 week pattern
int _occurrences(ChartPeriod p, int isoDay) {
  var n = 0;
  for (var d = p.from; d <= p.to; d = d.plusDays(1)) {
    if (isoWeekday(d.epochDay) == isoDay) n++;
  }
  return n;
}

List<int> _topDays(DayHourPattern p) {
  final days = p.byWeekday.keys.toList()
    ..sort((a, c) {
      final r = p.byWeekday[c]!.spend.minor.compareTo(
        p.byWeekday[a]!.spend.minor,
      );
      return r != 0 ? r : a.compareTo(c);
    });
  return days;
}

Money? _avgOn(DayHourPattern p, ChartPeriod period, int day) {
  final n = _occurrences(period, day);
  final cell = p.byWeekday[day];
  if (n == 0 || cell == null) return null;
  return cell.spend.mulDiv(1, n, MoneyRounding.halfAwayFromZero);
}

void _weekPattern(_Builder b, WeekPatternExplainInput i) {
  final p = i.current;
  if (p.byWeekday.length < 2 || p.byHour.isEmpty) return;
  final days = _topDays(p);
  final total = p.byWeekday.values.fold<int>(0, (s, c) => s + c.spend.minor);
  final first = days[0];
  final second = days[1];
  if (total <= 0 || !p.byWeekday[second]!.spend.isPositive) return;
  var hour = p.byHour.keys.first;
  for (final h in p.byHour.keys) {
    final s = p.byHour[h]!.spend.minor;
    final best = p.byHour[hour]!.spend.minor;
    if (s > best || (s == best && h < hour)) hour = h;
  }
  final share =
      p.byWeekday[first]!.spend.minor + p.byWeekday[second]!.spend.minor;
  b.fact = _line(ExplanationKey.weekPatternBasic, {
    'peakDay': WeekdayArg(first),
    'peakDay2': WeekdayArg(second),
    'percent': PercentArg(mulDivRound(share, 10000, total)),
    'time': HourArg(hour),
  });
  final avg = _avgOn(p, i.period, first);
  if (avg == null || !avg.isPositive) return;
  final step = _step(avg);
  final limit = avg - step;
  if (limit.isPositive) {
    b.tip = _line(ExplanationKey.weekPatternTip, {
      'target': MoneyArg(limit),
      'peakDay': WeekdayArg(first),
    });
  }
  if (!b.deep) return;
  final prev = i.previous;
  final prevPeriod = i.previousPeriod;
  if (prev != null && prevPeriod != null) {
    final before = _avgOn(prev, prevPeriod, first);
    if (before != null) {
      b.deepFact = _line(ExplanationKey.weekPatternDeep, {
        'trend': _trend(avg.minor, before.minor),
        'peakDay': WeekdayArg(first),
        'amount': MoneyArg(avg),
      });
    }
  }
  if (step.isPositive) {
    b.deepTip = _line(ExplanationKey.weekPatternDeepTip, {
      'target': MoneyArg(step),
      'peakDay': WeekdayArg(first),
      'yearly': MoneyArg(_yearly(step, _weeksPerYear)),
    });
  }
}

// 6 merchants
void _merchants(_Builder b, MerchantsExplainInput i, ExplainContext ctx) {
  final list = [...i.current]
    ..sort((a, c) => c.amount.minor.compareTo(a.amount.minor));
  if (list.length < 2 || !list[0].amount.isPositive) return;
  final top = list[0];
  b.fact = _line(ExplanationKey.merchantsBasic, {
    'merchant': NameArg(top.name),
    'amount': MoneyArg(top.amount),
    'visits': CountArg(top.count),
    'merchant2': NameArg(list[1].name),
    'amount2': MoneyArg(list[1].amount),
  });
  final tippable = list
      .where((m) => !ctx.protectedMerchantNorms.contains(m.merchantNorm))
      .firstOrNull;
  if (tippable != null) {
    b.tip = _line(ExplanationKey.merchantsTip, {
      'merchant': NameArg(tippable.name),
    });
  }
  if (!b.deep) return;
  final total = ctx.totalSpend;
  final prevMatch = i.previous
      .where((m) => m.merchantNorm == top.merchantNorm)
      .firstOrNull;
  if (total != null &&
      total.isPositive &&
      list.length >= 3 &&
      prevMatch != null) {
    final top3 = list[0].amount + list[1].amount + list[2].amount;
    b.deepFact = _line(ExplanationKey.merchantsDeep, {
      'percent': PercentArg(mulDivRound(top3.minor, 10000, total.minor)),
      'trend': _trend(top.amount.minor, prevMatch.amount.minor),
      'merchant': NameArg(top.name),
      'delta': MoneyArg((top.amount - prevMatch.amount).abs()),
    });
  }
  if (tippable != null) {
    final target = tippable.amount.mulDiv(1, 4, MoneyRounding.floor);
    if (target.isPositive) {
      b.deepTip = _line(ExplanationKey.merchantsDeepTip, {
        'merchant': NameArg(tippable.name),
        'target': MoneyArg(target),
        'yearly': MoneyArg(_yearly(target)),
      });
    }
  }
}

// 7 vs average
const int _noticeBp = 1000;

void _vsAverage(_Builder b, VsAverageExplainInput i, ExplainContext ctx) {
  final m = i.current;
  if (m.cyclesCounted < ChartThresholds.averageMinCycles) return;
  CategoryComparison? rise;
  CategoryComparison? drop;
  for (final c in m.byCategory) {
    final d = c.deltaBp;
    if (c.categoryId == null || d == null) continue;
    if (d >= _noticeBp && (rise == null || d > rise.deltaBp!)) rise = c;
    if (d <= -_noticeBp && (drop == null || d < drop.deltaBp!)) drop = c;
  }
  final state = rise != null && drop != null
      ? 'both'
      : rise != null
      ? 'rise'
      : drop != null
      ? 'drop'
      : 'other';
  b.fact = _line(ExplanationKey.vsAverageBasic, {
    'state': SelectArg(state),
    if (rise != null) ...{
      'category': CategoryArg(rise.categoryId),
      'percent': PercentArg(rise.deltaBp!),
    },
    if (drop != null) ...{
      'category2': CategoryArg(drop.categoryId),
      'percent2': PercentArg(-drop.deltaBp!),
    },
  });
  // The tip never asks to pull an essential category down (Q-25).
  CategoryComparison? tipRise;
  for (final c in m.byCategory) {
    final d = c.deltaBp;
    if (c.categoryId == null || d == null || d < _noticeBp) continue;
    if (ctx.isEssential(c.categoryId)) continue;
    if (tipRise == null || d > tipRise.deltaBp!) tipRise = c;
  }
  if (tipRise != null) {
    final both = drop != null;
    b.tip = _line(ExplanationKey.vsAverageTip, {
      'state': SelectArg(both ? 'both' : 'rise'),
      'category': CategoryArg(tipRise.categoryId),
      'target': MoneyArg(tipRise.current - tipRise.average),
      if (both) 'category2': CategoryArg(drop.categoryId),
    });
  } else if (drop != null) {
    b.tip = _line(ExplanationKey.vsAverageTip, {
      'state': const SelectArg('drop'),
      'category2': CategoryArg(drop.categoryId),
    });
  } else if (state == 'other') {
    b.tip = _line(ExplanationKey.vsAverageTip, {
      'state': const SelectArg('other'),
    });
  }
  if (!b.deep) return;
  b.deepFact = _line(ExplanationKey.vsAverageDeep, {
    'trend': _trend(m.current.minor, m.average.minor),
    'delta': MoneyArg((m.current - m.average).abs()),
  });
  if (tipRise != null) {
    b.deepTip = _line(ExplanationKey.vsAverageDeepTip, {
      'category': CategoryArg(tipRise.categoryId),
      'target': MoneyArg(tipRise.average),
    });
  }
}

// 8 installments
void _installments(_Builder b, InstallmentsExplainInput i) {
  if (i.months.isEmpty) return;
  final now = i.months.first;
  final upcoming = i.ends.where((e) => e.endsOn >= i.today).toList()
    ..sort((a, c) => a.endsOn.compareTo2(c.endsOn));
  if (upcoming.isEmpty || !now.total.isPositive) return;
  final next = upcoming.first;
  b.fact = _line(ExplanationKey.installmentsBasic, {
    'sum': MoneyArg(now.total),
    'item': NameArg(next.name),
    'month': MonthArg(next.endsOn.year, next.endsOn.month),
  });
  b.tip = _line(ExplanationKey.installmentsTip, {'item': NameArg(next.name)});
  if (!b.deep) return;
  var total = Money.zero(now.total.currency);
  for (final m in i.months) {
    total = total + m.total;
  }
  b.deepFact = _line(ExplanationKey.installmentsDeep, {
    'amount': MoneyArg(total),
    'average': MoneyArg(
      total.mulDiv(1, i.months.length, MoneyRounding.halfAwayFromZero),
    ),
  });
  b.deepTip = _line(ExplanationKey.installmentsDeepTip, {
    'item': NameArg(next.name),
    'monthly': MoneyArg(next.monthly),
  });
}

extension on CivilDate {
  int compareTo2(CivilDate o) => epochDay.compareTo(o.epochDay);
}

// 9 subscriptions
Money _monthly(Money annual) =>
    annual.mulDiv(1, 12, MoneyRounding.halfAwayFromZero);

void _subscriptions(_Builder b, SubscriptionsExplainInput i) {
  final s = i.current;
  if (s.items.isEmpty || !s.annualTotal.isPositive) return;
  final byCost = [...s.items]
    ..sort((a, c) => c.annual.minor.compareTo(a.annual.minor));
  b.fact = _line(ExplanationKey.subscriptionsBasic, {
    'monthly': MoneyArg(_monthly(s.annualTotal)),
    'yearly': MoneyArg(s.annualTotal),
  });
  b.tip = _line(ExplanationKey.subscriptionsTip, {
    'item': NameArg(byCost.first.name),
    'target': MoneyArg(byCost.first.annual),
  });
  if (!b.deep) return;
  final prev = i.threeMonthsAgo;
  if (prev != null) {
    final now = _monthly(s.annualTotal);
    final then = _monthly(prev.annualTotal);
    b.deepFact = _line(ExplanationKey.subscriptionsDeep, {
      'trend': _trend(now.minor, then.minor),
      'delta': MoneyArg((now - then).abs()),
    });
  }
  if (byCost.length >= 2) {
    b.deepTip = _line(ExplanationKey.subscriptionsDeepTip, {
      'target': MoneyArg(byCost[0].annual + byCost[1].annual),
    });
  }
}

// 10 cards
void _cards(_Builder b, CardsExplainInput i) {
  final list = [...i.current]
    ..sort((a, c) => c.spend.minor.compareTo(a.spend.minor));
  if (list.length < 2 || !list[0].spend.isPositive) return;
  final top = list[0];
  final util = i.utilisationBpByAccount[top.accountId];
  final credit = top.kind == 'credit' && util != null;
  b.fact = _line(ExplanationKey.cardsBasic, {
    'state': SelectArg(credit ? 'credit' : 'other'),
    'percent': PercentArg(top.shareBp),
    'card': NameArg(top.label),
    'card2': NameArg(list[1].label),
    'percent2': PercentArg(list[1].shareBp),
    if (credit) 'utilisation': PercentArg(util),
  });
  b.tip = _line(ExplanationKey.cardsTip, {
    'state': SelectArg(credit ? 'credit' : 'other'),
  });
  if (!b.deep) return;
  final before = i.previous
      .where((c) => c.accountId == top.accountId)
      .firstOrNull;
  if (before != null) {
    b.deepFact = _line(ExplanationKey.cardsDeep, {
      'trend': _trend(top.shareBp, before.shareBp),
      'card': NameArg(top.label),
    });
  }
  final limit = top.spend - _step(top.spend);
  if (limit.isPositive) {
    b.deepTip = _line(ExplanationKey.cardsDeepTip, {
      'amount': MoneyArg(top.spend),
      'card': NameArg(top.label),
      'target': MoneyArg(limit),
    });
  }
}

// 11 net worth
void _netWorth(_Builder b, NetWorthExplainInput i) {
  if (i.points.length < ChartThresholds.netWorthMinSnapshots) return;
  final first = i.points.first;
  final last = i.points.last;
  if (first.unit != last.unit) return;
  final trend = _trend(last.netMinor, first.netMinor);
  final steady = trend.value == 'other';
  b.fact = _line(ExplanationKey.netWorthBasic, {
    'trend': trend,
    'endAmount': UnitAmountArg(last.unit, last.netMinor),
    if (!steady) ...{
      'startAmount': UnitAmountArg(first.unit, first.netMinor),
      'month': MonthArg(first.takenOn.year, first.takenOn.month),
      'month2': MonthArg(last.takenOn.year, last.takenOn.month),
    },
  });
  final latest = i.assetsByTypeLatest;
  final assetsTotal = latest.values.fold<int>(0, (s, v) => s + v);
  if (assetsTotal > 0) {
    var bestType = latest.keys.first;
    for (final t in latest.keys) {
      if (latest[t]! > latest[bestType]!) bestType = t;
    }
    b.tip = _line(ExplanationKey.netWorthTip, {
      'assetType': AssetTypeArg(bestType),
      'percent': PercentArg(mulDivRound(latest[bestType]!, 10000, assetsTotal)),
    });
  }
  if (!b.deep) return;
  final base = first.netMinor;
  if (base > 0) {
    final pct = mulDivRound((last.netMinor - base).abs(), 10000, base);
    String? driver;
    var bestDelta = 0;
    final start = i.assetsByTypeFirst;
    for (final t in latest.keys) {
      final d = latest[t]! - (start[t] ?? 0);
      final aligned = trend.value == 'down' ? -d : d;
      if (aligned > bestDelta) {
        bestDelta = aligned;
        driver = t;
      }
    }
    if (steady) {
      b.deepFact = _line(ExplanationKey.netWorthDeep, {'trend': trend});
    } else if (driver != null) {
      b.deepFact = _line(ExplanationKey.netWorthDeep, {
        'trend': trend,
        'percent': PercentArg(pct),
        'assetType2': AssetTypeArg(driver),
      });
    }
  }
  final months =
      (last.takenOn.year - first.takenOn.year) * 12 +
      last.takenOn.month -
      first.takenOn.month;
  if (months >= 1 && trend.value == 'up') {
    final perMonth = (last.netMinor - first.netMinor) ~/ months;
    b.deepTip = _line(ExplanationKey.netWorthDeepTip, {
      'projected': UnitAmountArg(last.unit, last.netMinor + perMonth * 12),
    });
  }
}

// 12 inflation
void _inflation(_Builder b, InflationExplainInput i) {
  if (i.basket.length < 2) return;
  final first = i.basket.first;
  final last = i.basket.last;
  if (first.average.currency != last.average.currency ||
      !first.average.isPositive) {
    return;
  }
  final trend = _trend(last.average.minor, first.average.minor);
  final steady = trend.value == 'other';
  b.fact = _line(ExplanationKey.inflationBasic, {
    'trend': trend,
    'endAmount': MoneyArg(last.average),
    if (!steady) ...{
      'startAmount': MoneyArg(first.average),
      'month': MonthArg(first.year, first.month),
      'percent': PercentArg(
        mulDivRound(
          (last.average.minor - first.average.minor).abs(),
          10000,
          first.average.minor,
        ),
      ),
    },
  });
  if (i.biggestRiseCategoryId != null) {
    b.tip = _line(ExplanationKey.inflationTip, {
      'category': CategoryArg(i.biggestRiseCategoryId),
    });
  }
  if (!b.deep) return;
  final now = i.deliveryNow;
  final before = i.deliveryBefore;
  if (now != null && before != null && now > before) {
    b.deepFact = _line(ExplanationKey.inflationDeep, {
      'average': MoneyArg(now),
      'previous': MoneyArg(before),
    });
  }
  final visits = i.basketVisitsPerMonth;
  final target = _step(last.average);
  if (visits != null && visits > 0 && target.isPositive) {
    b.deepTip = _line(ExplanationKey.inflationDeepTip, {
      'target': MoneyArg(target),
      'yearly': MoneyArg(_yearly(target, visits * 12)),
    });
  }
}

// deep extras: projection (charts 1, 2, 3, 5, 7) and drivers
void _extras(_Builder b, ExplainInput input, ExplainContext ctx) {
  const projectionCharts = {
    ChartId.cashFlow,
    ChartId.categoryDonut,
    ChartId.burnCurve,
    ChartId.dayHourPattern,
    ChartId.monthVsAverage,
  };
  if (!projectionCharts.contains(input.chart)) return;
  final burn = input is BurnRateExplainInput ? input.current : ctx.burn;
  final budget = burn?.budget;
  final projected = burn?.projectedTotal;
  if (budget != null && projected != null) {
    b.extras.add(
      _line(ExplanationKey.deepProjection, {
        'state': SelectArg(projected > budget ? 'over' : 'other'),
        'projected': MoneyArg(projected),
      }),
    );
  }
  final drivers = _drivers(ctx);
  if (drivers != null) b.extras.add(drivers);
}

ExplanationLine? _drivers(ExplainContext ctx) {
  final before = {for (final m in ctx.previousMerchants) m.merchantNorm: m};
  final moved = <(MerchantSpend, int)>[];
  for (final m in ctx.merchants) {
    final delta = m.amount.minor - (before[m.merchantNorm]?.amount.minor ?? 0);
    if (delta != 0) moved.add((m, delta));
  }
  if (moved.length < 3) return null;
  moved.sort((a, c) {
    final r = c.$2.abs().compareTo(a.$2.abs());
    return r != 0 ? r : a.$1.merchantNorm.compareTo(c.$1.merchantNorm);
  });
  return _line(ExplanationKey.deepDrivers, {
    'merchant': NameArg(moved[0].$1.name),
    'merchant2': NameArg(moved[1].$1.name),
    'merchant3': NameArg(moved[2].$1.name),
  });
}
