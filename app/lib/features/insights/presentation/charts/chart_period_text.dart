// T-188: the words for the chart period: the resolved range ("25 Oct – 24
// Nov"), the preset names, and the "now" / "previous" phrases the
// explanations and footnotes use. Dates are Gregorian; digits follow the
// user's digits setting.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/date_format.dart';
import '../../../../core/l10n/digits_mode.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../budget/application/budget_providers.dart';
import '../../domain/chart_models.dart';
import '../../domain/chart_period_selection.dart';

class ChartPeriodText {
  const ChartPeriodText({
    required this.l,
    required this.lang,
    required this.digits,
    required this.today,
  });

  factory ChartPeriodText.of(BuildContext context, WidgetRef ref) {
    final lang = Localizations.localeOf(context).languageCode;
    return ChartPeriodText(
      l: AppLocalizations.of(context),
      lang: lang,
      digits: ref.watch(digitsModeProvider(lang)),
      today: ref.watch(todayProvider),
    );
  }

  final AppLocalizations l;
  final String lang;
  final DigitsMode digits;
  final CivilDate today;

  String _date(CivilDate d, {required bool withYear}) {
    final when = DateTime(d.year, d.month, d.day);
    return withYear
        ? ZDateFormat.date(when, lang, digits)
        : ZDateFormat.dayMonth(when, lang, digits);
  }

  /// `25 Oct – 24 Nov`; the year shows when the range crosses years or is
  /// not in the current year.
  String range(ChartPeriod p) {
    final withYear = p.from.year != p.to.year || p.to.year != today.year;
    return l.commonDateRange(
      _date(p.from, withYear: withYear),
      _date(p.to, withYear: withYear),
    );
  }

  /// The name of a preset in the picker and on the chip's spoken label.
  String presetName(ChartPreset preset) => switch (preset) {
    ChartPreset.thisCycle => l.commonPeriodThisCycle,
    ChartPreset.lastCycle => l.commonPeriodLastCycle,
    ChartPreset.thisMonth => l.commonPeriodThisMonth,
    ChartPreset.lastMonth => l.commonPeriodLastMonth,
    ChartPreset.last3Months => l.commonPeriodLastMonths(3, digits.render('3')),
    ChartPreset.last6Months => l.commonPeriodLastMonths(6, digits.render('6')),
    ChartPreset.last12Months => l.commonPeriodLastMonths(
      12,
      digits.render('12'),
    ),
    ChartPreset.thisYear => l.commonPeriodThisYear,
    ChartPreset.custom => l.commonPeriodCustom,
  };

  String _rangePhrase(ChartPeriod p) {
    final withYear = p.from.year != p.to.year || p.to.year != today.year;
    return l.insightsChartsPeriodNowRange(
      _date(p.from, withYear: withYear),
      _date(p.to, withYear: withYear),
    );
  }

  /// The period as a phrase inside a sentence: "this cycle", "the last 6
  /// months", "the period 1 Jan – 31 Mar".
  String now(ResolvedChartPeriod r) {
    final s = r.selection;
    final back = s.periodsBack;
    switch (s.kind) {
      case ChartPeriodKind.cycle:
        if (back == 0) return l.insightsChartsPeriodNowThisCycle;
        if (back == 1) return l.insightsChartsPeriodNowLastCycle;
      case ChartPeriodKind.month:
        if (back == 0) return l.insightsChartsPeriodNowThisMonth;
        if (back == 1) return l.insightsChartsPeriodNowLastMonth;
      case ChartPeriodKind.rolling:
        if (s.offset == 0) {
          final n = s.rollingMonths;
          return l.insightsChartsPeriodNowMonths(n, digits.render('$n'));
        }
      case ChartPeriodKind.year:
        if (s.offset == 0) return l.insightsChartsPeriodNowThisYear;
        if (s.offset == 1) return l.insightsChartsPeriodNowLastYear;
      case ChartPeriodKind.custom:
        break;
    }
    return _rangePhrase(r.period);
  }

  /// The period before it, as a phrase: "last cycle" next to the current
  /// one, "the cycle before" otherwise.
  String prev(ResolvedChartPeriod r) {
    final s = r.selection;
    final first = s.periodsBack == 0;
    switch (s.kind) {
      case ChartPeriodKind.cycle:
        return first
            ? l.insightsChartsPeriodPrevCycleNow
            : l.insightsChartsPeriodPrevCycle;
      case ChartPeriodKind.month:
        return first
            ? l.insightsChartsPeriodPrevMonthNow
            : l.insightsChartsPeriodPrevMonth;
      case ChartPeriodKind.rolling:
        final n = s.rollingMonths;
        return l.insightsChartsPeriodPrevMonths(n, digits.render('$n'));
      case ChartPeriodKind.year:
        return s.offset == 0
            ? l.insightsChartsPeriodPrevYearNow
            : l.insightsChartsPeriodPrevYear;
      case ChartPeriodKind.custom:
        return l.insightsChartsPeriodPrevRange;
    }
  }

  /// The card caption: how many days, weeks or months the chart shows.
  String bucketCount(ChartBucketKind kind, int count) {
    final text = digits.render('$count');
    return switch (kind) {
      ChartBucketKind.day => l.insightsChartsDaysCount(count, text),
      ChartBucketKind.week => l.insightsChartsWeeksCount(count, text),
      ChartBucketKind.month => l.insightsChartsMonthsCount(count, text),
    };
  }
}
