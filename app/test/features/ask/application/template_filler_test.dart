// T-344: template filler. Synthetic data only.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'package:zaghlol/core/l10n/card_number.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/ask/application/template_filler.dart';
import 'package:zaghlol/features/ask/domain/llm_answer_models.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';

final _egp = Currency.of('EGP');
final _usd = Currency.of('USD');
Money egp(int minor) => Money(_egp, minor);
Money usd(int minor) => Money(_usd, minor);

String clean(String s) =>
    s.replaceAll(RegExp('[\u2066\u2067\u2068\u2069]'), '');

TemplateFiller filler(
  String lang, {
  bool hidden = false,
  DigitsMode? digits,
  InvestPrices? prices,
}) => TemplateFiller(
  l: lookupAppLocalizations(Locale(lang)),
  languageCode: lang,
  digits:
      digits ?? (lang == 'ar' ? DigitsMode.arabicIndic : DigitsMode.western),
  hidden: hidden,
  today: CivilDate(2026, 11, 26),
  spanLabel: (p) => p == _a ? 'SPAN-A' : 'SPAN-B',
  subjectLabel: (t) => t.label ?? 'SUBJ',
  prices: prices,
);

final _a = ChartPeriod.month(2026, 10);
final _b = ChartPeriod.month(2026, 9);

LlmWhatIfAnswer whatIf() => LlmWhatIfAnswer(
  target: LlmTarget.category('c', label: 'DINING'),
  months: 12,
  outcomes: [
    LlmWhatIfOutcome(
      _egp,
      WhatIfCutResult(
        base: egp(320000),
        monthlySaving: egp(160000),
        total: egp(1920000),
        months: 12,
        basisPeriods: 3,
        capped: false,
      ),
    ),
  ],
);

LlmDataAnswer spend(List<Money> figs) =>
    LlmDataAnswer(period: _a, target: LlmTarget.everything, figures: figs);

LlmCompareFigure cmp(Money cur, Money prev, int? bp) =>
    LlmCompareFigure(current: cur, previous: prev, deltaBp: bp);

PlanTemplate tpl(String lang, String text) => PlanTemplate(lang, text);

InvestPrices prices() => InvestPrices(
  gold: [
    GoldQuote(
      karat: 21,
      pricePerGram: egp(400000),
      asOf: DateTime(2026, 11, 25),
    ),
  ],
  usdEgp: InvestFxQuote(egpPerUsd: egp(5000), asOf: DateTime(2026, 11, 25)),
  certificateRateBp: 2500,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('AC1 examples (exact strings)', () {
    test('1 what-if percent', () {
      final ar = filler('ar')
          .fill(whatIf(), whatIfMode: const WhatIfPercent(50));
      expect(
        clean(ar.lines[0]),
        'لو قللت DINING ٥٠٪، هتوفر حوالي ١٬٦٠٠ ج.م في الشهر، يعني ١٩٬٢٠٠ ج.م في ١٢ شهر.',
      );
      expect(ar.lines[1], 'على أساس متوسط آخر ٣ شهور كاملة');
      final en = filler('en')
          .fill(whatIf(), whatIfMode: const WhatIfPercent(50));
      expect(
        clean(en.lines[0]),
        "Cut DINING by 50% and you'd save about EGP 1,600 a month, "
        'EGP 19,200 over 12 months.',
      );
      expect(en.lines[1], 'Based on the average of your last 3 full months');
    });

    test('2 average', () {
      final a = LlmAverageAnswer(
        per: AveragePer.day,
        period: _a,
        range: _a,
        target: LlmTarget.everything,
        figures: [
          LlmAverageFigure(total: egp(2050000), units: 31, average: egp(66129)),
        ],
        partialExcluded: false,
      );
      expect(
        clean(filler('ar').fill(a).lines.single),
        'متوسط صرفك على SUBJ SPAN-A: ٦٦١٫٢٩ ج.م في اليوم.',
      );
      expect(
        clean(filler('en').fill(a).lines.single),
        'Your average spend on SUBJ SPAN-A: EGP 661.29 a day.',
      );
    });

    test('4 invest gold, with disclaimer', () {
      final a = LlmInvestAnswer(
        horizonMonths: 12,
        instruments: {InvestInstrument.gold},
        figures: [
          LlmInvestFigure(
            saved: egp(450000),
            illustration: InvestIllustration(
              band: InvestBand.gold,
              stocksInGeneral: false,
              rows: [
                GoldRow(
                  karat: 21,
                  centigrams: 112,
                  priceAsOf: DateTime(2026, 11, 25),
                  stale: false,
                ),
              ],
            ),
          ),
        ],
      );
      final en = filler('en', prices: prices()).fill(a).lines;
      expect(clean(en[0]), 'Last month you had EGP 4,500 left over.');
      expect(
        clean(en[1]),
        'It could have bought about 1.12 g of 21K gold, at EGP 4,000 per gram on Nov 25.',
      );
      expect(en.length, 4);
      final ar = filler('ar', prices: prices()).fill(a).lines;
      expect(clean(ar[0]), 'الشهر اللي فات فضل معاك ٤٬٥٠٠ ج.م.');
      expect(ar[1], contains('١٫١٢'));
      expect(ar[1], contains('٢١'));
      expect(clean(ar[1]), contains('٤٬٠٠٠ ج.م'));
    });

    test('5 invest stocks band', () {
      final a = LlmInvestAnswer(
        horizonMonths: 12,
        instruments: {InvestInstrument.usd},
        figures: [
          LlmInvestFigure(
            saved: egp(50000),
            illustration: const InvestIllustration(
              band: InvestBand.stocks,
              stocksInGeneral: true,
              rows: [],
            ),
          ),
        ],
      );
      final en = filler('en').fill(a, investState: InvestLeadState.other).lines;
      expect(clean(en[0]), 'If you had EGP 500:');
      expect(
        en[1],
        'An amount like this could be a small start in stocks in general. Learn first, and use a licensed provider.',
      );
      final ar = filler('ar').fill(a, investState: InvestLeadState.other).lines;
      expect(clean(ar[0]), 'لو معاك ٥٠٠ ج.م:');
      expect(
        ar[1],
        'مبلغ زي ده ممكن يبقى بداية صغيرة في الأسهم عمومًا. اتعلم الأول، واتعامل مع جهة مرخصة.',
      );
    });

    test('6 compare with change percent; USD block separate, never added', () {
      final a = LlmCompareAnswer(
        periodA: _a,
        periodB: _b,
        target: LlmTarget.everything,
        figures: [
          cmp(egp(340000), egp(320000), 625),
          cmp(usd(1000), usd(2000), -5000),
        ],
      );
      final en = filler('en').fill(a).lines;
      expect(en.length, 2);
      expect(
        clean(en[0]),
        '${filler('en').l.chatAnswerCurrencyLead('EGP')} You spent EGP 3,400 SPAN-A, EGP 200 more than SPAN-B. '
        "That's a 6% change.",
      );
      expect(clean(en[1]), contains('USD 10'));
      expect(clean(en[1]), contains('less than'));
      expect(clean(en.join()), isNot(contains('3,500')));
      final ar = filler('ar').fill(a).lines;
      expect(clean(ar[0]), contains('يعني فرق ٦٪'));
    });
  });

  group('other app answers', () {
    test('suggest, none and fallback/refuse', () {
      final f = filler('en');
      expect(f.fill(const LlmSuggestAnswer(perCurrency: [])).lines, [
        f.l.chatSuggestNone,
      ]);
      expect(f.fill(const LlmFallbackAnswer(LlmFallbackReason.zakah)).lines, [
        f.l.chatFallbackText,
      ]);
      final r = f
          .fill(const LlmRefuseAnswer(RefuseReason.unsafe, selfHarm: true))
          .lines;
      expect(r, [f.l.chatRefuseUnsafe, f.l.chatRefuseSupport]);
      final s = f
          .fill(
            LlmSuggestAnswer(
              perCurrency: [
                CurrencySuggestions(_egp, [
                  Suggestion(
                    kind: SuggestionKind.s1AboveAverage,
                    category: 'Delivery',
                    monthlySaving: egp(50000),
                    basisPeriods: 3,
                  ),
                ]),
              ],
            ),
          )
          .lines;
      expect(s.first, f.l.chatSuggestIntro);
      expect(clean(s[1]), contains('EGP 500'));
      expect(s.last, f.l.chatSuggestFooter);
    });

    test('negative saved and no-budget', () {
      final f = filler('en');
      final saved = LlmSavedAnswer(
        period: _a,
        figures: [LlmSavedFigure(income: egp(100000), spend: egp(150000))],
      );
      expect(clean(f.fill(saved).lines.single), contains('EGP 500'));
      expect(
        f.fill(LlmSafeSpendAnswer(daysRemaining: 4, figures: const [])).lines,
        [f.l.chatLlmAnswerSafeSpendNone],
      );
    });

    test('zero figure and card tail stay Western', () {
      final a = LlmBalanceAnswer(
        figures: [
          LlmBalanceFigure(
            balance: egp(0),
            asOf: DateTime(2026, 11, 20),
            accountLabel: formatAccountWithCard('Bank', '5075'),
          ),
        ],
      );
      for (final lang in ['ar', 'en']) {
        final line = filler(lang).fill(a).lines.single;
        expect(line, contains('•••• 5075'));
        expect(clean(line), contains(lang == 'ar' ? '٠ ج.م' : 'EGP 0'));
      }
    });
  });

  group('AC2 model template ignored when not allowed', () {
    final good = tpl('en', 'Spent {amount} {period}');
    test('used for single-currency data', () {
      final r = filler('en').fill(spend([egp(12345)]), template: good);
      expect(r.usedModelTemplate, isTrue);
      expect(clean(r.lines.single), 'Spent EGP 123.45 SPAN-A');
    });
    test('multi-currency answer uses app template', () {
      final r = filler('en').fill(spend([egp(100), usd(200)]), template: good);
      expect(r.usedModelTemplate, isFalse);
      expect(r.lines.length, 2);
    });
    test('PL-INVEST, suggest, refuse and fallback ignore the template', () {
      final f = filler('en');
      for (final a in <LlmAnswer>[
        const LlmFallbackAnswer(LlmFallbackReason.unsupported),
        const LlmRefuseAnswer(RefuseReason.offTopic, selfHarm: false),
        const LlmSuggestAnswer(perCurrency: []),
        LlmInvestAnswer(
          horizonMonths: 1,
          figures: [
            LlmInvestFigure(
              saved: egp(0),
              illustration: const InvestIllustration(
                band: InvestBand.nothingSaved,
                stocksInGeneral: false,
                rows: [],
              ),
            ),
          ],
          instruments: {InvestInstrument.gold},
        ),
      ]) {
        expect(
          f.fill(a, template: tpl('en', 'Hello {amount}')).usedModelTemplate,
          isFalse,
        );
      }
    });
    test('template language must equal app language', () {
      expect(
        filler('ar')
            .fill(spend([egp(1)]), template: tpl('en', 'Spent {amount}'))
            .usedModelTemplate,
        isFalse,
      );
    });
    test('unknown, duplicate or unsupported blank falls back', () {
      final f = filler('en');
      for (final t in [
        'Spent {pct}',
        'Spent {amount} {amount}',
        'Spent {count}',
        'Spent {nope}',
      ]) {
        expect(
          f.fill(spend([egp(1)]), template: tpl('en', t)).usedModelTemplate,
          isFalse,
          reason: t,
        );
      }
    });
  });

  group('model template safety (FU-409 defence)', () {
    final bad = <String, String>{
      'ascii digit': 'Spent 5 on {amount}',
      'arabic-indic digit': 'Spent ٥ on {amount}',
      'persian digit': 'Spent ۵ on {amount}',
      'fullwidth digit': 'Spent ５ on {amount}',
      'circled digit': 'Spent ① on {amount}',
      'vulgar fraction': 'Spent ½ on {amount}',
      'superscript': 'Spent x² on {amount}',
      'roman numeral': 'Spent Ⅻ on {amount}',
      'cjk numeral': 'Spent 一 on {amount}',
      'placeholder index': 'Spent ⟦ACCOUNT_1⟧ {amount}',
      'zero width space': 'Spent​ {amount}',
      'zero width joiner': 'Spent‍ {amount}',
      'bidi override': 'Spent \u202E {amount}',
      'bidi isolate': 'Spent \u2066 {amount}',
      'soft hyphen': 'Spe­nt {amount}',
      'invisible plus': 'Spent ⁤ {amount}',
      'bom': '﻿Spent {amount}',
      'number word': 'Spent about ten on {amount}',
      'number word capital': 'Spent Thousand {amount}',
    };
    bad.forEach((name, text) {
      test('refused: $name', () {
        final r = filler('en')
            .fill(spend([egp(100)]), template: tpl('en', text));
        expect(r.usedModelTemplate, isFalse);
        expect(clean(r.lines.single), isNot(contains('Spent')));
      });
    });
    test('arabic number words and digits refused', () {
      for (final t in [
        'صرفت ألف على {amount}',
        'صرفت وألف {amount}',
        'صرفت ٣ {amount}',
        'صرفت نص {amount}',
      ]) {
        final r = filler('ar').fill(spend([egp(100)]), template: tpl('ar', t));
        expect(r.usedModelTemplate, isFalse, reason: t);
      }
    });
    test('clean arabic template is used with phone digits', () {
      final r = filler('ar').fill(
        spend([egp(12345)]),
        template: tpl('ar', 'صرفت {amount} {period}'),
      );
      expect(r.usedModelTemplate, isTrue);
      expect(clean(r.lines.single), 'صرفت ١٢٣٫٤٥ ج.م SPAN-A');
    });
    test('templateTextRefusal never echoes the text', () {
      expect(templateTextRefusal('secret 5'), 'DIGIT_LIKE');
      expect(templateTextRefusal('plain words {amount}'), isNull);
    });
  });

  group('AC3 hide amounts', () {
    test('every blank masked, grams hidden, percentages visible', () {
      final f = filler('en', hidden: true, prices: prices());
      final w = f
          .fill(whatIf(), whatIfMode: const WhatIfPercent(50))
          .lines
          .first;
      expect(
        clean(w),
        "Cut DINING by 50% and you'd save about EGP **** a month, EGP **** over 12 months.",
      );
      final t = f.fill(spend([egp(5)]), template: tpl('en', 'Spent {amount}'));
      expect(clean(t.lines.single), 'Spent EGP ****');
      final c = f
          .fill(
            LlmCompareAnswer(
              periodA: _a,
              periodB: _b,
              target: LlmTarget.everything,
              figures: [cmp(egp(340000), egp(320000), 625)],
            ),
          )
          .lines
          .single;
      expect(
        clean(c),
        allOf(contains('****'), contains('6%'), isNot(contains('3,400'))),
      );
      final g = f
          .fill(
            LlmInvestAnswer(
              horizonMonths: 12,
              instruments: {InvestInstrument.gold},
              figures: [
                LlmInvestFigure(
                  saved: egp(450000),
                  illustration: InvestIllustration(
                    band: InvestBand.gold,
                    stocksInGeneral: false,
                    rows: [
                      GoldRow(
                        karat: 21,
                        centigrams: 112,
                        priceAsOf: DateTime(2026, 11, 25),
                        stale: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
          .lines;
      expect(clean(g[1]), contains('****'));
      expect(clean(g[1]), isNot(contains('1.12')));
      expect(clean(g.join()), isNot(contains('4,500')));
    });
  });

  group('AC4 digits', () {
    test(
      'western digits in ar when the setting says so, arabic-indic in en',
      () {
        final ar = filler(
          'ar',
          digits: DigitsMode.western,
        ).fill(whatIf(), whatIfMode: const WhatIfPercent(50)).lines;
        expect(
          clean(ar.join()),
          allOf(contains('1,600 ج.م'), contains('12 شهر'), contains('50٪')),
        );
        expect(ar.join(), isNot(matches('[٠-٩]')));
        final en = filler(
          'en',
          digits: DigitsMode.arabicIndic,
        ).fill(whatIf(), whatIfMode: const WhatIfPercent(50)).lines;
        expect(en.join(), contains('١٢'));
        expect(en.join(), isNot(matches('[0-9]')));
      },
    );
    test('derived percent when the mode is unknown', () {
      final en = filler('en').fill(whatIf()).lines.first;
      expect(en, contains('50%'));
    });
    test('amount mode wording', () {
      final en = filler('en')
          .fill(whatIf(), whatIfMode: WhatIfAmount(egp(160000)))
          .lines
          .first;
      expect(
        clean(en),
        'Cut DINING by EGP 1,600 a month and you\'d save EGP 19,200 over 12 months.',
      );
    });
    test('not enough data is app copy, per currency', () {
      final a = LlmWhatIfAnswer(
        target: LlmTarget.everything,
        months: 3,
        outcomes: [LlmWhatIfOutcome(_egp, null)],
      );
      expect(filler('en').fill(a, template: tpl('en', 'Saves {total}')).lines, [
        filler('en').l.chatWhatIfNotEnough,
      ]);
    });
  });
}
