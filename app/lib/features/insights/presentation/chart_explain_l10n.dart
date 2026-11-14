// T-108: renders T-106 ExplanationLines with the generated AppLocalizations
// (ExplanationLine.key.l10nKey names the method). Typed arguments are
// formatted per locale here: money, percent, counts, names, weekdays, hours.
// The engine never builds user-facing text; this file never computes figures.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../domain/explanations.dart';

/// Locale-aware formatting of explanation arguments.
class ExplainFormat {
  ExplainFormat.of(BuildContext context, WidgetRef ref, this.categoryName)
    : l = AppLocalizations.of(context),
      lang = Localizations.localeOf(context).languageCode,
      digits = ref.watch(
        digitsModeProvider(Localizations.localeOf(context).languageCode),
      );

  final AppLocalizations l;
  final String lang;
  final DigitsMode digits;

  /// Category id (null = uncategorized) to its localised name.
  final String Function(String? id) categoryName;

  String arg(ExplanationArg a) => switch (a) {
    MoneyArg(:final money) => MoneyFormat.format(
      money,
      languageCode: lang,
      digits: digits,
    ),
    UnitAmountArg(:final unit, :final minor) => digits.render('$minor $unit'),
    PercentArg(:final bp) => digits.render('${(bp + 50) ~/ 100}%'),
    CountArg(:final count) => digits.render('$count'),
    NameArg(:final name) => name,
    CategoryArg(:final categoryId) => categoryName(categoryId),
    AssetTypeArg(:final type) => switch (type) {
      'gold' => l.commonAssetTypeGold,
      'certificate' => l.commonAssetTypeCertificate,
      'foreign_cash' => l.commonAssetTypeForeignCash,
      'stocks' => l.commonAssetTypeStocks,
      'property' => l.commonAssetTypeProperty,
      'car' => l.commonAssetTypeCar,
      _ => type,
    },
    // 2024-01-01 is a Monday.
    WeekdayArg(:final isoWeekday) => DateFormat.EEEE(
      lang,
    ).format(DateTime(2024, 1, isoWeekday)),
    HourArg(:final hour) => ZDateFormat.time(
      DateTime(2024, 1, 1, hour),
      lang,
      digits,
    ),
    MonthArg(:final year, :final month) => ZDateFormat.monthYear(
      DateTime(year, month),
      lang,
      digits,
    ),
    SelectArg(:final value) => value,
  };
}

/// The sentence for [line] in the current locale. A placeholder the line
/// doesn't carry (a select branch that doesn't use it) is passed empty.
String renderExplanationLine(ExplainFormat f, ExplanationLine line) {
  final l = f.l;
  String a(String name) {
    final v = line.args[name];
    return v == null ? '' : f.arg(v);
  }

  return switch (line.key.l10nKey) {
    'insightsExplainCashFlowBasic' => l.insightsExplainCashFlowBasic(
      a('state'),
      a('income'),
      a('spent'),
      a('gap'),
      a('saved'),
      a('percent'),
    ),
    'insightsExplainCashFlowTip' => l.insightsExplainCashFlowTip(
      a('state'),
      a('category'),
      a('target'),
    ),
    'insightsExplainCashFlowDeep' => l.insightsExplainCashFlowDeep(
      a('trend'),
      a('delta'),
    ),
    'insightsExplainCashFlowDeepTip' => l.insightsExplainCashFlowDeepTip(
      a('target'),
      a('yearly'),
    ),
    'insightsExplainCategoriesBasic' => l.insightsExplainCategoriesBasic(
      a('category'),
      a('percent'),
      a('amount'),
      a('category2'),
      a('percent2'),
    ),
    'insightsExplainCategoriesTip' => l.insightsExplainCategoriesTip(
      a('category'),
      a('target'),
    ),
    'insightsExplainCategoriesDeep' => l.insightsExplainCategoriesDeep(
      a('trend'),
      a('category'),
      a('delta'),
    ),
    'insightsExplainCategoriesDeepTip' => l.insightsExplainCategoriesDeepTip(
      a('category'),
      a('target'),
      a('yearly'),
    ),
    'insightsExplainBurnRateBasic' => l.insightsExplainBurnRateBasic(
      a('state'),
      a('cycleDay'),
      a('spent'),
      a('budget'),
      a('perDay'),
    ),
    'insightsExplainBurnRateTip' => l.insightsExplainBurnRateTip(
      a('state'),
      a('perDay'),
    ),
    'insightsExplainBurnRateDeep' => l.insightsExplainBurnRateDeep(
      a('trend'),
      a('delta'),
    ),
    'insightsExplainBurnRateDeepTip' => l.insightsExplainBurnRateDeepTip(
      a('target'),
    ),
    'insightsExplainRule503020Basic' => l.insightsExplainRule503020Basic(
      a('state'),
      a('needsPct'),
      a('wantsPct'),
      a('savingsPct'),
    ),
    'insightsExplainRule503020Tip' => l.insightsExplainRule503020Tip(
      a('state'),
      a('target'),
    ),
    'insightsExplainRule503020Deep' => l.insightsExplainRule503020Deep(
      a('trend'),
      a('savingsPct'),
    ),
    'insightsExplainRule503020DeepTip' => l.insightsExplainRule503020DeepTip(
      a('percent'),
      a('yearly'),
    ),
    'insightsExplainWeekPatternBasic' => l.insightsExplainWeekPatternBasic(
      a('peakDay'),
      a('peakDay2'),
      a('percent'),
      a('time'),
    ),
    'insightsExplainWeekPatternTip' => l.insightsExplainWeekPatternTip(
      a('target'),
      a('peakDay'),
    ),
    'insightsExplainWeekPatternDeep' => l.insightsExplainWeekPatternDeep(
      a('trend'),
      a('peakDay'),
      a('amount'),
    ),
    'insightsExplainWeekPatternDeepTip' => l.insightsExplainWeekPatternDeepTip(
      a('peakDay'),
      a('target'),
      a('yearly'),
    ),
    'insightsExplainMerchantsBasic' => l.insightsExplainMerchantsBasic(
      a('merchant'),
      a('amount'),
      a('visits'),
      a('merchant2'),
      a('amount2'),
    ),
    'insightsExplainMerchantsTip' => l.insightsExplainMerchantsTip(
      a('merchant'),
    ),
    'insightsExplainMerchantsDeep' => l.insightsExplainMerchantsDeep(
      a('percent'),
      a('trend'),
      a('merchant'),
      a('delta'),
    ),
    'insightsExplainMerchantsDeepTip' => l.insightsExplainMerchantsDeepTip(
      a('merchant'),
      a('target'),
      a('yearly'),
    ),
    'insightsExplainVsAverageBasic' => l.insightsExplainVsAverageBasic(
      a('state'),
      a('category'),
      a('percent'),
      a('category2'),
      a('percent2'),
    ),
    'insightsExplainVsAverageTip' => l.insightsExplainVsAverageTip(
      a('state'),
      a('category'),
      a('target'),
      a('category2'),
    ),
    'insightsExplainVsAverageDeep' => l.insightsExplainVsAverageDeep(
      a('trend'),
      a('delta'),
    ),
    'insightsExplainVsAverageDeepTip' => l.insightsExplainVsAverageDeepTip(
      a('category'),
      a('target'),
    ),
    'insightsExplainInstallmentsBasic' => l.insightsExplainInstallmentsBasic(
      a('sum'),
      a('item'),
      a('month'),
    ),
    'insightsExplainInstallmentsTip' => l.insightsExplainInstallmentsTip(
      a('item'),
    ),
    'insightsExplainInstallmentsDeep' => l.insightsExplainInstallmentsDeep(
      a('amount'),
      a('average'),
    ),
    'insightsExplainInstallmentsDeepTip' =>
      l.insightsExplainInstallmentsDeepTip(a('item'), a('monthly')),
    'insightsExplainSubscriptionsBasic' => l.insightsExplainSubscriptionsBasic(
      a('monthly'),
      a('yearly'),
    ),
    'insightsExplainSubscriptionsTip' => l.insightsExplainSubscriptionsTip(
      a('item'),
      a('target'),
    ),
    'insightsExplainSubscriptionsDeep' => l.insightsExplainSubscriptionsDeep(
      a('trend'),
      a('delta'),
    ),
    'insightsExplainSubscriptionsDeepTip' =>
      l.insightsExplainSubscriptionsDeepTip(a('target')),
    'insightsExplainCardsBasic' => l.insightsExplainCardsBasic(
      a('state'),
      a('percent'),
      a('card'),
      a('card2'),
      a('percent2'),
      a('utilisation'),
    ),
    'insightsExplainCardsTip' => l.insightsExplainCardsTip(a('state')),
    'insightsExplainCardsDeep' => l.insightsExplainCardsDeep(
      a('trend'),
      a('card'),
    ),
    'insightsExplainCardsDeepTip' => l.insightsExplainCardsDeepTip(
      a('amount'),
      a('card'),
      a('target'),
    ),
    'insightsExplainNetWorthBasic' => l.insightsExplainNetWorthBasic(
      a('trend'),
      a('startAmount'),
      a('month'),
      a('endAmount'),
      a('month2'),
    ),
    'insightsExplainNetWorthTip' => l.insightsExplainNetWorthTip(
      a('assetType'),
      a('percent'),
    ),
    'insightsExplainNetWorthDeep' => l.insightsExplainNetWorthDeep(
      a('trend'),
      a('percent'),
      a('assetType2'),
    ),
    'insightsExplainNetWorthDeepTip' => l.insightsExplainNetWorthDeepTip(
      a('projected'),
    ),
    'insightsExplainInflationBasic' => l.insightsExplainInflationBasic(
      a('trend'),
      a('startAmount'),
      a('month'),
      a('endAmount'),
      a('percent'),
    ),
    'insightsExplainInflationTip' => l.insightsExplainInflationTip(
      a('category'),
    ),
    'insightsExplainInflationDeep' => l.insightsExplainInflationDeep(
      a('average'),
      a('previous'),
    ),
    'insightsExplainInflationDeepTip' => l.insightsExplainInflationDeepTip(
      a('target'),
      a('yearly'),
    ),
    'insightsDeepProjection' => l.insightsDeepProjection(
      a('state'),
      a('projected'),
    ),
    'insightsDeepDrivers' => l.insightsDeepDrivers(
      a('merchant'),
      a('merchant2'),
      a('merchant3'),
    ),
    final k => throw StateError('no l10n method for $k'),
  };
}
