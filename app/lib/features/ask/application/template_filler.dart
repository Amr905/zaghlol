// T-344: turns an `LlmAnswer` (T-342) into display lines (ask-llm.md 2.3 and
// section 6 "Hide amounts / digits", BR-LLM-04).
//
// SAFETY PROPERTY: every number on screen comes from the phone's computed
// values, never from the model's template text. FU-409 (number words, a
// circled digit, a vulgar fraction, a placeholder index read as an amount,
// invisible format characters) is not closed in the validators yet, so this
// file defends itself. A model template is USED only when ALL hold, else the
// app's own template for the plan is shown (never a partial template):
//  1. the answer is a single-currency data answer or a what-if answer (INVEST,
//     SUGGEST, REFUSE, FALLBACK, not-found, breakdown/top-N and any
//     multi-currency answer are always app-owned);
//  2. the template language equals the app language;
//  3. it passes `TemplateGrammar.check` again (defence in depth);
//  4. its literal text (outside `{blank}` tokens) has NO digit of any script
//     (Unicode Nd), NO number-like symbol (Unicode No and Nl: circled digits,
//     fractions, superscripts, roman numerals), NO format control (Unicode Cf:
//     bidi marks and overrides, zero-width, soft hyphen, invisible operators),
//     NO control, private-use, surrogate or unassigned code point, no `⟦ ⟧`;
//  5. every letter is Latin or Arabic script (so CJK or other-script numeral
//     ideographs are refused);
//  6. it contains no whole word from a short list of English and Arabic
//     number words (zero..twenty, tens, hundred, thousand, million, half...).
//     The list is not exhaustive; it is one more layer, not a guarantee;
//  7. every `{blank}` is allowed for the plan, appears once, and the phone has
//     a value for it.
// Accepted residual: a number word outside the list, or one spelled with
// letters the list does not know, can still pass; it carries no phone figure
// and the amounts shown stay the phone's own.
//
// Amounts are `Money` (integer minor units) through `MoneyFormat` (digits per
// the digits setting, `****` with hide amounts, grams hidden, percentages
// visible). Per-currency lists are never summed. All wording is ARB.

import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/money_format.dart';
import '../../insights/domain/chart_models.dart';
import '../domain/llm_answer_models.dart';

/// Where a PL-INVEST base came from (chooses the lead line).
enum InvestLeadState { saved, whatIf, other }

/// The lines of a bubble and whether the model's template was used.
final class FilledAnswer {
  const FilledAnswer(this.lines, {this.usedModelTemplate = false});
  final List<String> lines;
  final bool usedModelTemplate;
}

final RegExp _digitLike = RegExp(r'[\p{Nd}\p{No}\p{Nl}]', unicode: true);
final RegExp _forbiddenCode = RegExp(
  r'[\p{Cf}\p{Cc}\p{Co}\p{Cs}\p{Cn}⟦⟧]',
  unicode: true,
);
final RegExp _letterRune = RegExp(r'^\p{L}$', unicode: true);
final RegExp _blank = RegExp(r'\{([A-Za-z]+)\}');
final RegExp _wordSplit = RegExp(r'[^\p{L}\p{M}]+', unicode: true);

const Set<String> _numberWords = {
  // English.
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty', 'forty',
  'fifty', 'sixty', 'seventy', 'eighty', 'ninety', 'hundred', 'thousand',
  'million', 'billion', 'half', 'quarter', 'dozen', 'double', 'triple',
  // Arabic (standard and Egyptian).
  'صفر', 'واحد', 'اتنين', 'اثنين', 'تلاتة', 'ثلاثة', 'اربعة', 'أربعة',
  'خمسة', 'ستة', 'سبعة', 'تمانية', 'ثمانية', 'تسعة', 'عشرة', 'عشر', 'عشرين',
  'تلاتين', 'ثلاثين', 'اربعين', 'أربعين', 'خمسين', 'ستين', 'سبعين',
  'تمانين', 'ثمانين', 'تسعين', 'ميت', 'مية', 'مائة', 'مئة', 'الف', 'ألف',
  'آلاف', 'مليون', 'مليار', 'نص', 'نصف', 'ربع', 'تلت', 'ثلث',
};

bool _isAllowedLetter(int cp) =>
    (cp >= 0x41 && cp <= 0x5A) ||
    (cp >= 0x61 && cp <= 0x7A) ||
    (cp >= 0xC0 && cp <= 0x24F && cp != 0xD7 && cp != 0xF7) ||
    (cp >= 0x0600 && cp <= 0x06FF) ||
    (cp >= 0x0750 && cp <= 0x077F) ||
    (cp >= 0x08A0 && cp <= 0x08FF) ||
    (cp >= 0xFB50 && cp <= 0xFDFF) ||
    (cp >= 0xFE70 && cp <= 0xFEFF);

/// The filler's own check of a model template's literal text (rules 4-6
/// above). Returns a short reason code or null when the text is acceptable.
/// Never echoes the text.
String? templateTextRefusal(String text) {
  final literal = text.replaceAll(_blank, ' ');
  if (_digitLike.hasMatch(literal)) return 'DIGIT_LIKE';
  if (_forbiddenCode.hasMatch(literal)) return 'FORMAT_OR_CONTROL';
  for (final rune in literal.runes) {
    final ch = String.fromCharCode(rune);
    if (_letterRune.hasMatch(ch) && !_isAllowedLetter(rune)) {
      return 'SCRIPT';
    }
  }
  for (final raw in literal.split(_wordSplit)) {
    if (raw.isEmpty) continue;
    final word = raw.toLowerCase();
    if (_numberWords.contains(word)) return 'NUMBER_WORD';
    if (word.length > 2 && 'وبلفك'.contains(word[0])) {
      if (_numberWords.contains(word.substring(1))) return 'NUMBER_WORD';
    }
  }
  return null;
}

class TemplateFiller {
  TemplateFiller({
    required this.l,
    required this.languageCode,
    required this.digits,
    required this.hidden,
    required this.today,
    required this.spanLabel,
    required this.subjectLabel,
    this.prices,
  });

  final AppLocalizations l;
  final String languageCode;
  final DigitsMode digits;

  /// D-67: amounts show as `****`, grams are hidden, percentages stay.
  final bool hidden;
  final CivilDate today;

  /// The phone's words for a period ("last month") and a target ("Dining").
  final String Function(ChartPeriod) spanLabel;
  final String Function(LlmTarget) subjectLabel;

  /// Gold price per gram and FX for the PL-INVEST rows.
  final InvestPrices? prices;

  bool get _ar => languageCode == 'ar';
  String get _sep => _ar ? '، ' : ', ';

  String _money(Money m) => MoneyFormat.format(
    m,
    languageCode: languageCode,
    digits: digits,
    hidden: hidden,
    dropZeroFraction: true,
  );

  String _n(int n) => digits.render('$n');

  /// Text that came out of ICU formatting: digits of either script moved to
  /// the digits setting.
  String _redigit(String s) {
    final out = StringBuffer();
    for (final u in s.runes) {
      final v = (u >= 0x0660 && u <= 0x0669)
          ? u - 0x0660
          : (u >= 0x30 && u <= 0x39 ? u - 0x30 : -1);
      if (v < 0) {
        out.writeCharCode(u);
      } else {
        out.write(digits.render('$v'));
      }
    }
    return out.toString();
  }

  String _months(int m) => _redigit(l.chatUnitMonths(m, m));

  String _date(CivilDate d) =>
      ZDateFormat.date(DateTime(d.year, d.month, d.day), languageCode, digits);

  String _dayMonth(DateTime when) {
    final d = when.toLocal();
    return ZDateFormat.dayMonth(
      DateTime(d.year, d.month, d.day),
      languageCode,
      digits,
    );
  }

  /// A percentage; always visible, also with hide amounts.
  String _pct(int whole) => '${_n(whole)}${_ar ? '٪' : '%'}';

  /// Basis points as a whole percent (half up): "6.25%" reads "6%".
  String _wholeBp(int bp) => _pct((bp.abs() + 50) ~/ 100);

  /// Basis points with up to two decimals (an example certificate rate).
  String _bp(int bp) {
    final abs = bp.abs();
    if (abs % 100 == 0) return _pct(abs ~/ 100);
    final frac = (abs % 100)
        .toString()
        .padLeft(2, '0')
        .replaceAll(RegExp(r'0$'), '');
    final sep = digits == DigitsMode.arabicIndic ? '٫' : '.';
    return '${_n(abs ~/ 100)}$sep${digits.render(frac)}${_ar ? '٪' : '%'}';
  }

  String _lead(String code, String text) =>
      '${l.chatAnswerCurrencyLead(code)} $text';

  List<String> _perCurrency(List<(String, String)> lines) => [
    for (final (code, text) in lines)
      lines.length > 1 ? _lead(code, text) : text,
  ];

  /// Fills [answer]. [template] is the model's template that already passed
  /// the grammar; it is used only when every rule in the file header holds.
  /// [whatIfMode] and [investState] come from the plan (the answer models do
  /// not carry them); without a mode the cut percent is derived from the
  /// computed figures.
  FilledAnswer fill(
    LlmAnswer answer, {
    PlanTemplate? template,
    WhatIfMode? whatIfMode,
    InvestLeadState investState = InvestLeadState.saved,
  }) {
    if (template != null) {
      final text = _useTemplate(answer, template);
      if (text != null) return FilledAnswer([text], usedModelTemplate: true);
    }
    return FilledAnswer(_appLines(answer, whatIfMode, investState));
  }

  // ---- model template ----------------------------------------------------

  /// plan code and blank values for the answers a model template may serve,
  /// or null (always app-owned).
  (String, Map<String, String>)? _blanksFor(LlmAnswer a) {
    switch (a) {
      case LlmDataAnswer(:final figures) when figures.length == 1:
        return (
          'PL-SPEND',
          {
            'target': subjectLabel(a.target),
            'period': spanLabel(a.period),
            'amount': _money(figures.first),
          },
        );
      case LlmCompareAnswer(:final figures) when figures.length == 1:
        final f = figures.first;
        return (
          'PL-COMPARE',
          {
            'target': subjectLabel(a.target),
            'period': spanLabel(a.periodA),
            'periodB': spanLabel(a.periodB),
            'amount': _money(f.current),
            'amountB': _money(f.previous),
            'diff': _money(f.difference.abs()),
            if (f.deltaBp != null) 'pct': _wholeBp(f.deltaBp!),
          },
        );
      case LlmAverageAnswer(:final figures) when figures.length == 1:
        return (
          'PL-AVERAGE',
          {
            'target': subjectLabel(a.target),
            'period': spanLabel(a.period),
            'amount': _money(figures.first.average),
            'count': _n(figures.first.units),
          },
        );
      case LlmIncomeAnswer(:final figures) when figures.length == 1:
        return (
          'PL-INCOME',
          {'period': spanLabel(a.period), 'amount': _money(figures.first)},
        );
      case LlmSavedAnswer(:final figures) when figures.length == 1:
        return (
          'PL-SAVED',
          {
            'period': spanLabel(a.period),
            'amount': _money(figures.first.saved),
          },
        );
      case LlmBudgetLeftAnswer(:final figures) when figures.length == 1:
        return (
          'PL-BUDGET-LEFT',
          {
            'target': subjectLabel(a.target),
            'amount': _money(figures.first.remaining),
          },
        );
      case LlmSafeSpendAnswer(:final figures) when figures.length == 1:
        return ('PL-SAFE-SPEND', {'amount': _money(figures.first)});
      case LlmBalanceAnswer(:final figures) when figures.length == 1:
        return ('PL-BALANCE', {'amount': _money(figures.first.balance)});
      case LlmBillsAnswer(:final figures)
          when figures.length == 1 && figures.first.dues.isNotEmpty:
        final f = figures.first;
        final first = f.dues
            .map((d) => d.date)
            .reduce((x, y) => x.epochDay <= y.epochDay ? x : y);
        return (
          'PL-BILLS-DUE',
          {
            'count': _n(f.dues.length),
            'amount': _money(f.total),
            'date': _date(first),
          },
        );
      case LlmWhatIfAnswer(:final outcomes)
          when outcomes.length == 1 && outcomes.first.result != null:
        final r = outcomes.first.result!;
        return (
          'PL-WHATIF-CUT',
          {
            'target': subjectLabel(a.target),
            'pct': _pct(_derivedPercent(r)),
            'monthly': _money(r.monthlySaving),
            'total': _money(r.total),
            'months': _months(r.months),
          },
        );
      case LlmWhatIfSaveAnswer():
        return (
          'PL-WHATIF-SAVE',
          {
            'monthly': _money(a.amount),
            'total': _money(a.total),
            'months': _months(a.months),
          },
        );
      default:
        return null;
    }
  }

  String? _useTemplate(LlmAnswer answer, PlanTemplate t) {
    final spec = _blanksFor(answer);
    if (spec == null) return null;
    final (plan, values) = spec;
    if (t.lang != languageCode) return null;
    if (TemplateGrammar.check(
          plan: plan,
          requestLang: languageCode,
          templateLang: t.lang,
          text: t.text,
        ) !=
        null) {
      return null;
    }
    if (templateTextRefusal(t.text) != null) return null;
    final used = [for (final m in _blank.allMatches(t.text)) m.group(1)!];
    if (used.toSet().length != used.length) return null;
    final allowed = planTemplateBlanks[plan];
    if (allowed == null) return null;
    for (final name in used) {
      if (!allowed.contains(name) || !values.containsKey(name)) return null;
    }
    return t.text.replaceAllMapped(_blank, (m) => values[m.group(1)!]!);
  }

  int _derivedPercent(WhatIfCutResult r) => r.base.minor <= 0
      ? 0
      : (r.monthlySaving.minor * 100 + r.base.minor ~/ 2) ~/ r.base.minor;

  // ---- app templates -----------------------------------------------------

  List<String> _appLines(
    LlmAnswer a,
    WhatIfMode? mode,
    InvestLeadState investState,
  ) => switch (a) {
    LlmDataAnswer() => _perCurrency([
      for (final m in a.figures)
        (
          m.currency.code,
          l.chatAnswerSpendOn(
            _money(m),
            subjectLabel(a.target),
            spanLabel(a.period),
          ),
        ),
    ]),
    LlmCompareAnswer() => _perCurrency([
      for (final f in a.figures) (f.current.currency.code, _compare(a, f)),
    ]),
    LlmBreakdownAnswer() => _breakdown(a),
    LlmTopNAnswer() => _topN(a),
    LlmAverageAnswer() => _perCurrency([
      for (final f in a.figures) (f.average.currency.code, _average(a, f)),
    ]),
    LlmIncomeAnswer() => _perCurrency([
      for (final m in a.figures)
        (
          m.currency.code,
          l.chatLlmAnswerIncome(_money(m), spanLabel(a.period)),
        ),
    ]),
    LlmSavedAnswer() => _perCurrency([
      for (final f in a.figures) (f.income.currency.code, _saved(a, f)),
    ]),
    LlmBillsAnswer() => _bills(a),
    LlmBudgetLeftAnswer() => _budget(a),
    LlmSafeSpendAnswer() =>
      a.hasBudget
          ? _perCurrency([
              for (final m in a.figures)
                (m.currency.code, l.chatLlmAnswerSafeSpend(_money(m))),
            ])
          : [l.chatLlmAnswerSafeSpendNone],
    LlmBalanceAnswer() => _balance(a),
    LlmWhatIfAnswer() => _whatIf(a, mode),
    LlmWhatIfSaveAnswer() => [
      _redigit(
        l.chatWhatIfSave(_money(a.total), _money(a.amount), _months(a.months)),
      ),
    ],
    LlmSuggestAnswer() => _suggest(a),
    LlmInvestAnswer() => _invest(a, investState),
    LlmNotFoundAnswer() => [l.chatFallbackText],
    LlmFallbackAnswer() => [l.chatFallbackText],
    LlmRefuseAnswer() => [
      switch (a.reason) {
        RefuseReason.offTopic => l.chatRefuseOffTopic,
        RefuseReason.unsafe => l.chatRefuseUnsafe,
        RefuseReason.specificPick => l.chatRefuseSpecificPick,
      },
      if (a.selfHarm) l.chatRefuseSupport,
    ],
  };

  String _compare(LlmCompareAnswer a, LlmCompareFigure f) {
    final d = f.difference.minor;
    final trend = d > 0 ? 'up' : (d < 0 ? 'down' : 'other');
    final base = l.chatAnswerCompare(
      _money(f.current),
      spanLabel(a.periodA),
      trend,
      spanLabel(a.periodB),
      _money(f.difference.abs()),
    );
    final bp = f.deltaBp;
    if (bp == null || d == 0) return base;
    return '$base ${l.chatLlmAnswerChangePct(_wholeBp(bp))}';
  }

  String _average(LlmAverageAnswer a, LlmAverageFigure f) {
    final state = a.per.name == 'month' ? 'other' : a.per.name;
    final line = l.chatLlmAnswerAverage(
      _money(f.average),
      spanLabel(a.period),
      state,
      subjectLabel(a.target),
    );
    return a.partialExcluded
        ? '$line ${l.chatLlmAnswerFullUnits(state)}'
        : line;
  }

  String _saved(LlmSavedAnswer a, LlmSavedFigure f) {
    final net = f.saved;
    final pct = f.income.minor > 0 ? net.minor * 100 ~/ f.income.minor : 0;
    return l.chatAnswerSavings(
      net.minor < 0 ? 'short' : 'other',
      spanLabel(a.period),
      _money(net.abs()),
      _money(net),
      _pct(pct),
    );
  }

  String _row(LlmRankedRow r) =>
      '${r.name ?? l.chatLlmAnswerOtherBucket} ${_money(r.amount)}';

  String _list(LlmRankedList list) => [
    for (final r in list.rows) _row(r),
    if (list.other != null)
      '${l.chatLlmAnswerOtherBucket} ${_money(list.other!)}',
  ].join(_sep);

  List<String> _breakdown(LlmBreakdownAnswer a) => _perCurrency([
    for (final list in a.lists)
      if (list.rows.isNotEmpty)
        (
          list.currency.code,
          l.chatLlmAnswerBreakdown(_list(list), spanLabel(a.period)),
        ),
  ]);

  List<String> _topN(LlmTopNAnswer a) {
    final lists = [
      for (final x in a.lists)
        if (x.rows.isNotEmpty) x,
    ];
    return _perCurrency([
      for (final list in lists)
        (
          list.currency.code,
          switch (a.of) {
            TopOf.category => l.chatLlmAnswerTopCategories(
              _list(list),
              spanLabel(a.period),
            ),
            TopOf.merchant || TopOf.expense => l.chatAnswerTopMerchants(
              spanLabel(a.period),
              _list(list),
            ),
          },
        ),
    ]);
  }

  List<String> _bills(LlmBillsAnswer a) {
    final days = a.windowEnd.difference(today).clamp(1, 366);
    final span = l.chatPeriodNextDays(days, _n(days));
    if (a.figures.isEmpty) {
      return [l.chatAnswerDues(0, span, '', '', _n(0))];
    }
    return _perCurrency([
      for (final f in a.figures)
        (
          f.total.currency.code,
          l.chatAnswerDues(
            f.dues.length,
            span,
            f.dues.map((d) => d.name).join(_sep),
            _money(f.total),
            _n(f.dues.length),
          ),
        ),
    ]);
  }

  List<String> _budget(LlmBudgetLeftAnswer a) {
    final subject = subjectLabel(a.target);
    if (!a.hasBudget) return [l.chatAnswerBudgetNone(subject)];
    return _perCurrency([
      for (final f in a.figures)
        (
          f.budget.currency.code,
          f.remaining.minor < 0
              ? l.chatAnswerBudgetOver(subject, _money(f.remaining.abs()))
              : l.chatAnswerBudgetLeft(_money(f.remaining), subject),
        ),
    ]);
  }

  List<String> _balance(LlmBalanceAnswer a) {
    if (a.figures.isEmpty) {
      return [l.chatAnswerBalanceUnknown(l.budgetEditOverall)];
    }
    // Named accounts one by one; a debit and a credit balance never add up.
    return [
      for (final f in a.figures)
        l.chatAnswerBalance(
          f.accountLabel ?? l.budgetEditOverall,
          _money(f.balance),
          _dayMonth(f.asOf),
        ),
    ];
  }

  List<String> _whatIf(LlmWhatIfAnswer a, WhatIfMode? mode) {
    final subject = subjectLabel(a.target);
    final out = <(String, List<String>)>[];
    for (final o in a.outcomes) {
      final r = o.result;
      if (r == null) {
        out.add((o.currency.code, [l.chatWhatIfNotEnough]));
        continue;
      }
      final months = _months(r.months);
      final lines = <String>[
        if (mode is WhatIfAmount)
          l.chatWhatIfCutAmount(
            _money(r.total),
            _money(r.monthlySaving),
            months,
            subject,
          )
        else
          l.chatWhatIfCutPercent(
            _money(r.total),
            _money(r.monthlySaving),
            months,
            _pct(mode is WhatIfPercent ? mode.percent : _derivedPercent(r)),
            subject,
          ),
        if (r.capped) l.chatWhatIfCapped(_money(r.base), subject),
        l.chatWhatIfBasis(r.basisPeriods, r.basisPeriods),
      ];
      out.add((o.currency.code, [for (final s in lines) _redigit(s)]));
    }
    return [
      for (final (code, lines) in out)
        for (var i = 0; i < lines.length; i++)
          out.length > 1 && i == 0 ? _lead(code, lines[i]) : lines[i],
    ];
  }

  List<String> _suggest(LlmSuggestAnswer a) {
    final lines = <String>[];
    final filled = [
      for (final c in a.perCurrency)
        if (c.suggestions.isNotEmpty) c,
    ];
    if (filled.isEmpty) return [l.chatSuggestNone];
    lines.add(l.chatSuggestIntro);
    for (final c in filled) {
      for (final s in c.suggestions) {
        final row = l.chatSuggestSaveLabel(_money(s.monthlySaving));
        final name = s.category == cashPoolLabel
            ? l.chatSuggestCashTip
            : s.category;
        final text = s.category == cashPoolLabel ? name : '$name: $row';
        lines.add(filled.length > 1 ? _lead(c.currency.code, text) : text);
      }
    }
    lines.add(l.chatSuggestFooter);
    return lines;
  }

  String _grams(int centigrams) {
    if (hidden) return l.commonUnitGrams(kAmountMask);
    final whole = centigrams ~/ 100;
    final frac = (centigrams % 100).toString().padLeft(2, '0');
    final sep = digits == DigitsMode.arabicIndic ? '٫' : '.';
    return l.commonUnitGrams('${_n(whole)}$sep${digits.render(frac)}');
  }

  Money? _goldPrice(int karat, Currency c) {
    for (final q in prices?.gold ?? const <GoldQuote>[]) {
      if (q.karat == karat && q.pricePerGram.currency == c) {
        return q.pricePerGram;
      }
    }
    return null;
  }

  List<String> _invest(LlmInvestAnswer a, InvestLeadState state) {
    final lines = <String>[];
    var disclaimer = false;
    for (final f in a.figures) {
      final ill = f.illustration;
      final multi = a.figures.length > 1;
      String tag(String s) => multi ? _lead(f.saved.currency.code, s) : s;
      if (ill.band == InvestBand.nothingSaved) {
        lines.add(tag(l.chatInvestNothingSaved));
        continue;
      }
      if (ill.band == InvestBand.small) {
        lines.add(tag(l.chatInvestSmall));
        continue;
      }
      disclaimer = true;
      lines.add(tag(l.chatInvestLead(_money(f.saved), state.name)));
      if (ill.stocksInGeneral) lines.add(l.chatInvestStocks);
      for (final row in ill.rows) {
        switch (row) {
          case GoldRow():
            final price = _goldPrice(row.karat, f.saved.currency);
            if (price == null) break;
            final text = l.chatInvestGold(
              _dayMonth(row.priceAsOf),
              _grams(row.centigrams),
              _n(row.karat),
              _money(price),
            );
            lines.add(row.stale ? '$text ${l.commonBadgeStale}' : text);
          case UsdRow():
            final fx = prices?.usdEgp;
            final when = row.rateAsOf;
            if (row.approximate && (fx == null || when == null)) break;
            final text = l.chatInvestUsd(
              _money(row.amount),
              when == null ? '' : _dayMonth(when),
              fx == null ? '' : _money(fx.egpPerUsd),
            );
            lines.add(row.stale ? '$text ${l.commonBadgeStale}' : text);
          case CertificateRow():
            lines.add(
              l.chatInvestCertificate(
                _bp(row.rateBp),
                _months(row.months),
                _money(row.payout),
              ),
            );
          case NoPriceRow():
            lines.add(
              l.chatInvestNoPrice(
                MoneyFormat.currencyLabel(
                  row.currency,
                  languageCode: languageCode,
                ),
              ),
            );
        }
      }
    }
    if (disclaimer) {
      lines
        ..add(l.chatInvestDisclaimerSummary)
        ..add(l.chatInvestDisclaimer);
    }
    return lines;
  }
}
