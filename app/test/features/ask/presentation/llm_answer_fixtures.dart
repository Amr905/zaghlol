// T-347: synthetic answers for the online-helper views (ask-llm-ux section 5
// and every D-93 band). No real names or amounts.

import 'package:zaghlol/features/ask/application/llm_ask_flow.dart';
import 'package:zaghlol/features/ask/domain/llm_answer_models.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

final egpCur = Currency.of('EGP');
Money egpM(int minor) => Money(egpCur, minor);

final ChartPeriod fixLast = ChartPeriod.month(2026, 10);
final ChartPeriod fixPrev = ChartPeriod.month(2026, 9);

final DateTime fixNow = DateTime.utc(2026, 11, 26, 9);

/// 21K gold at EGP 4,000 a gram, dated 25 Nov. G = 0.25 g = EGP 1,000.
final InvestPrices fixPrices = InvestPrices(
  gold: [
    GoldQuote(
      karat: 21,
      pricePerGram: egpM(400000),
      asOf: DateTime.utc(2026, 11, 25, 9),
    ),
  ],
  usdEgp: InvestFxQuote(
    egpPerUsd: egpM(5000),
    asOf: DateTime.utc(2026, 11, 25, 9),
  ),
  certificateRateBp: 2000,
);

InvestPrices get fixPricesNoGold => InvestPrices(
  usdEgp: fixPrices.usdEgp,
  certificateRateBp: fixPrices.certificateRateBp,
);

LlmInvestAnswer investAnswer(int savedMinor, {InvestPrices? prices}) {
  final saved = egpM(savedMinor);
  final p = prices ?? fixPrices;
  final thresholds = InvestThresholds.defaults();
  final ill = illustrate(
    saved: saved,
    prices: p,
    instruments: {
      InvestInstrument.gold,
      InvestInstrument.usd,
      InvestInstrument.certificate,
    },
    horizonMonths: 12,
    now: fixNow,
    thresholds: thresholds,
  );
  return LlmInvestAnswer(
    horizonMonths: 12,
    figures: [LlmInvestFigure(saved: saved, illustration: ill)],
    instruments: const {
      InvestInstrument.gold,
      InvestInstrument.usd,
      InvestInstrument.certificate,
    },
  );
}

final LlmWhatIfAnswer whatIfAnswer = LlmWhatIfAnswer(
  target: LlmTarget.category('sys:dining', label: 'Dining out'),
  months: 12,
  outcomes: [
    LlmWhatIfOutcome(
      egpCur,
      WhatIfCutResult(
        base: egpM(320000),
        monthlySaving: egpM(160000),
        total: egpM(1920000),
        months: 12,
        basisPeriods: 3,
        capped: false,
      ),
    ),
  ],
);

const Plan whatIfPlan = PlanWhatIfCut(
  PlanFilter(slug: 'dining'),
  PlanMode(kind: WhatIfKind.percent, percent: 50),
  12,
);

final LlmAverageAnswer averageAnswer = LlmAverageAnswer(
  per: AveragePer.day,
  period: fixLast,
  range: fixLast,
  target: LlmTarget.everything,
  figures: [
    LlmAverageFigure(total: egpM(2050000), units: 31, average: egpM(66129)),
  ],
  partialExcluded: true,
);

final LlmCompareAnswer compareAnswer = LlmCompareAnswer(
  periodA: fixLast,
  periodB: fixPrev,
  target: LlmTarget.everything,
  figures: [
    LlmCompareFigure(
      current: egpM(340000),
      previous: egpM(320000),
      deltaBp: 625,
    ),
  ],
);

final LlmSuggestAnswer suggestAnswer = LlmSuggestAnswer(
  perCurrency: [
    CurrencySuggestions(egpCur, [
      Suggestion(
        kind: SuggestionKind.s1AboveAverage,
        category: 'Delivery',
        monthlySaving: egpM(50000),
        basisPeriods: 3,
      ),
    ]),
  ],
);

AskLlmAnswered answered(
  LlmAnswer a, {
  Plan? plan,
  String sent = 'q ⟦MERCHANT_1⟧',
}) => AskLlmAnswered(answer: a, sentText: sent, counted: true, plan: plan);
