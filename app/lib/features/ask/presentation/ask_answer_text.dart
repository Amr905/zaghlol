// T-111: turns an engine answer (data, never text) into the lines of a Zaghlol
// bubble, from ARB keys only. One line per currency; figures are never summed
// or converted (CLAUDE.md §2.4). Spending is plain ink, never red.

import 'package:intl/intl.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/money_format.dart';
import '../../insights/domain/chart_models.dart';
import '../domain/ask_models.dart';

/// One bar of a mini chart. [label] is the caption; [permille] is the bar
/// height (0..1000) relative to the biggest bar of its chart.
final class AskBar {
  const AskBar(this.label, this.permille);
  final String label;
  final int permille;
}

/// A small chart under a bubble, for one currency.
final class AskMiniChart {
  const AskMiniChart(this.currencyCode, this.bars);
  final String currencyCode;
  final List<AskBar> bars;
}

/// What a Zaghlol bubble shows.
final class AskBubbleContent {
  const AskBubbleContent(this.lines, {this.charts = const []});
  final List<String> lines;
  final List<AskMiniChart> charts;
}

class AskAnswerTextBuilder {
  AskAnswerTextBuilder({
    required this.l,
    required this.languageCode,
    required this.digits,
    required this.today,
    required this.categoryNames,
  });

  final AppLocalizations l;
  final String languageCode;
  final DigitsMode digits;
  final CivilDate today;

  /// Category id to localized name.
  final Map<String, String> categoryNames;

  String _money(Money m) =>
      MoneyFormat.format(m, languageCode: languageCode, digits: digits);

  String _n(int n) => digits.render('$n');

  String _date(CivilDate d) =>
      ZDateFormat.date(DateTime(d.year, d.month, d.day), languageCode, digits);

  String _span(ChartPeriod p) {
    final m = ChartPeriod.month(today.year, today.month);
    if (p == m) return l.chatPeriodThisMonth;
    final prev = today.month == 1
        ? ChartPeriod.month(today.year - 1, 12)
        : ChartPeriod.month(today.year, today.month - 1);
    if (p == prev) return l.chatPeriodLastMonth;
    return l.chatPeriodRange(_date(p.from), _date(p.to));
  }

  String _subject(AskTarget t, String? categoryId, String? label) =>
      switch (t) {
        AskTarget.category =>
          categoryNames[categoryId] ?? label ?? l.budgetEditOverall,
        AskTarget.merchant || AskTarget.card => label ?? l.budgetEditOverall,
        AskTarget.everything => l.budgetEditOverall,
      };

  /// With two or more currencies each line is led by its currency.
  List<String> _perCurrency(List<(String, String)> lines) => [
    for (final (code, text) in lines)
      lines.length > 1 ? '${l.chatAnswerCurrencyLead(code)} $text' : text,
  ];

  AskBubbleContent build(AskAnswer a) => switch (a) {
    AskSpendAnswer() => AskBubbleContent(
      _perCurrency([
        for (final m in a.figures)
          (
            m.currency.code,
            a.target == AskTarget.card
                ? l.chatAnswerSpendCard(
                    _money(m),
                    a.targetLabel ?? l.budgetEditOverall,
                    _span(a.period),
                  )
                : l.chatAnswerSpendOn(
                    _money(m),
                    _subject(a.target, a.categoryId, a.targetLabel),
                    _span(a.period),
                  ),
          ),
      ]),
    ),
    AskCompareAnswer() => _compare(a),
    AskTopMerchantsAnswer() => _top(a),
    AskBalanceAnswer() => _balance(a),
    AskBudgetAnswer() => AskBubbleContent(
      _perCurrency([
        for (final f in a.figures)
          (
            f.budget.currency.code,
            f.isOver
                ? l.chatAnswerBudgetOver(
                    l.budgetEditOverall,
                    _money(f.remaining.abs()),
                  )
                : l.chatAnswerBudgetLeft(
                    _money(f.remaining),
                    l.budgetEditOverall,
                  ),
          ),
      ]),
    ),
    AskDuesAnswer() => _dues(a),
    AskBiggestAnswer() => AskBubbleContent(
      _perCurrency([
        for (final e in a.figures)
          (
            e.amount.currency.code,
            l.chatAnswerBiggest(
              _span(a.period),
              _money(e.amount),
              e.merchant ?? l.budgetEditOverall,
              _date(e.date),
            ),
          ),
      ]),
    ),
    AskSavingsAnswer() => AskBubbleContent(
      _perCurrency([
        for (final f in a.figures)
          (f.income.currency.code, _savings(a.period, f)),
      ]),
    ),
    AskRoastAnswer() => AskBubbleContent([_roast(a)]),
    AskNoDataAnswer(:final reason) => AskBubbleContent([
      reason == AskNoDataReason.noDues
          ? l.chatAnswerDues(0, l.chatPeriodUntilPayday, '', '', '0')
          : l.chatAnswerNoDataGeneric,
    ]),
    AskFallbackAnswer() => AskBubbleContent([l.chatFallbackText]),
    AskUnavailableAnswer() => AskBubbleContent([l.chatAnswerError]),
  };

  AskBubbleContent _compare(AskCompareAnswer a) {
    final lines = <(String, String)>[];
    final charts = <AskMiniChart>[];
    for (final f in a.figures) {
      final diff = f.current - f.previous;
      final trend = diff.minor > 0 ? 'up' : (diff.minor < 0 ? 'down' : 'other');
      lines.add((
        f.current.currency.code,
        l.chatAnswerCompare(
          _money(f.current),
          _span(a.current),
          trend,
          _span(a.previous),
          _money(diff.abs()),
        ),
      ));
      charts.add(
        AskMiniChart(f.current.currency.code, [
          AskBar(_span(a.previous), _permille(f.previous.minor, f)),
          AskBar(_span(a.current), _permille(f.current.minor, f)),
        ]),
      );
    }
    return AskBubbleContent(_perCurrency(lines), charts: charts);
  }

  int _permille(int minor, AskCompareFigure f) {
    final top = f.current.minor > f.previous.minor
        ? f.current.minor
        : f.previous.minor;
    return top <= 0 ? 0 : minor * 1000 ~/ top;
  }

  AskBubbleContent _top(AskTopMerchantsAnswer a) {
    final lines = <(String, String)>[];
    final charts = <AskMiniChart>[];
    for (final list in a.byCurrency) {
      if (list.isEmpty) continue;
      final code = list.first.amount.currency.code;
      lines.add((
        code,
        l.chatAnswerTopMerchants(
          _span(a.period),
          [for (final m in list) '${m.name} ${_money(m.amount)}'].join('، '),
        ),
      ));
      final top = list.first.amount.minor;
      charts.add(
        AskMiniChart(code, [
          for (final m in list)
            AskBar(m.name, top <= 0 ? 0 : m.amount.minor * 1000 ~/ top),
        ]),
      );
    }
    return AskBubbleContent(_perCurrency(lines), charts: charts);
  }

  AskBubbleContent _balance(AskBalanceAnswer a) {
    final who = a.accountLabel ?? l.budgetEditOverall;
    if (a.figures.isEmpty) {
      return AskBubbleContent([l.chatAnswerBalanceUnknown(who)]);
    }
    return AskBubbleContent(
      _perCurrency([
        for (final f in a.figures)
          (
            f.amount.currency.code,
            l.chatAnswerBalance(
              f.accountLabel ?? who,
              _money(f.amount),
              _date(_civil(f.asOf)),
            ),
          ),
      ]),
    );
  }

  CivilDate _civil(DateTime utc) {
    final d = utc.toLocal();
    return CivilDate(d.year, d.month, d.day);
  }

  AskBubbleContent _dues(AskDuesAnswer a) {
    final days = a.windowEnd.difference(today).clamp(1, 366);
    final span = l.chatPeriodNextDays(days, _n(days));
    return AskBubbleContent(
      _perCurrency([
        for (final f in a.figures)
          (
            f.total.currency.code,
            l.chatAnswerDues(
              f.dues.length,
              span,
              f.dues.map((d) => d.name).join('، '),
              _money(f.total),
              _n(f.dues.length),
            ),
          ),
      ]),
    );
  }

  String _savings(ChartPeriod p, AskSavingsFigure f) {
    final net = f.net;
    final short = net.minor < 0;
    final pct = f.income.minor > 0 ? net.minor * 100 ~/ f.income.minor : 0;
    return l.chatAnswerSavings(
      short ? 'short' : 'other',
      _span(p),
      _money(net.abs()),
      _money(net),
      '${_n(pct)}%',
    );
  }

  String _roast(AskRoastAnswer a) {
    final f = a.fact;
    final span = _span(a.period);
    switch (f.kind) {
      case RoastKind.topCategory:
        final name = categoryNames[f.categoryId] ?? l.budgetEditOverall;
        return l.chatRoastTopCategory(name, '${_n((f.shareBp ?? 0) ~/ 100)}%');
      case RoastKind.merchantRegular:
        return l.chatAnswerSpendOnCount(
          _money(f.amount!),
          f.name ?? l.budgetEditOverall,
          span,
          l.commonUnitVisits(f.count ?? 0, _n(f.count ?? 0)),
        );
      case RoastKind.lateNight:
        return l.chatRoastLateNight(
          ZDateFormat.time(DateTime(2026, 1, 1), languageCode, digits),
        );
      case RoastKind.weekendHeavy:
        // 2026-11-13 is a Friday.
        return l.chatRoastWeekend(
          DateFormat.EEEE(languageCode).format(DateTime(2026, 11, 13)),
        );
      case RoastKind.biggestExpense:
        return f.name == null
            ? l.chatRoastGentle
            : l.chatRoastSplurge(_money(f.amount!), f.name!);
      case RoastKind.subscriptions:
        return l.chatRoastSubscriptions(_money(f.amount!));
      case RoastKind.calm:
        return l.chatRoastClean;
    }
  }
}
