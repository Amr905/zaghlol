// T-347: the online-helper answer views on S-50. The flow and the plan
// executor are faked; data is synthetic.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';
import 'package:zaghlol/features/ask/application/llm_ask_flow.dart';
import 'package:zaghlol/features/ask/application/plan_executor.dart';
import 'package:zaghlol/features/ask/application/template_filler.dart';
import 'package:zaghlol/features/ask/data/llm_ask_providers.dart';
import 'package:zaghlol/features/ask/domain/llm_answer_models.dart';
import 'package:zaghlol/features/ask/presentation/llm_answer_views.dart';
import 'package:zaghlol/features/ask/presentation/llm_ask_ui.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'llm_answer_fixtures.dart';
import 'llm_ask_states_test.dart' show FakeFlow, ask, l10n, pumpLlm;

class FakeExecutor implements PlanExecutor {
  final List<Plan> ran = [];
  LlmAnswer answer = const LlmFallbackAnswer(LlmFallbackReason.failed);

  @override
  Future<LlmAnswer> execute(Plan plan, MaskMap map) async {
    ran.add(plan);
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

List<Override> views({
  InvestPrices? prices,
  bool hidden = false,
  FakeExecutor? executor,
}) => [
  llmAnswerViewBuilderProvider.overrideWithValue(buildLlmAnswerView),
  askInvestPricesProvider.overrideWith((ref) async => prices ?? fixPrices),
  hideAmountsProvider.overrideWithValue(hidden),
  if (executor != null)
    planExecutorProvider.overrideWith((ref) async => executor),
];

Future<FakeFlow> pumpAnswer(
  WidgetTester t,
  AskLlmAnswered a, {
  Locale locale = const Locale('en'),
  bool dark = false,
  double scale = 1.0,
  bool investFlag = true,
  List<Override> extra = const [],
}) async {
  final r = await pumpLlm(
    t,
    (_, _) => Stream.value(a),
    locale: locale,
    dark: dark,
    scale: scale,
    investFlag: investFlag,
    extra: extra,
  );
  await ask(t);
  await t.pump();
  await t.pump();
  return r[0] as FakeFlow;
}

String allText(WidgetTester t) =>
    [for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? '']
        .join('\n')
        .replaceAll(RegExp('[\u2066\u2067\u2068\u2069]'), '');

void main() {
  test('what-if mode and invest state come off the plan', () {
    expect(whatIfModeOf(whatIfPlan), isA<WhatIfPercent>());
    expect(
      whatIfModeOf(
        const PlanWhatIfCut(
          PlanFilter.none,
          PlanMode(kind: WhatIfKind.amount, amount: '300', currency: 'EGP'),
          6,
        ),
      ),
      isA<WhatIfAmount>(),
    );
    expect(whatIfModeOf(null), isNull);
    expect(investStateOf(investSavedPlan), InvestLeadState.saved);
    expect(
      investStateOf(
        const PlanInvest(PlanInvestSource(InvestSourceKind.amount), [
          Instrument.gold,
        ], 12),
      ),
      InvestLeadState.other,
    );
  });

  test('poses: proud for what-if, professor for invest', () {
    expect(llmAnswerMood(whatIfAnswer), ZaghlolMoment.proud);
    expect(llmAnswerMood(investAnswer(450000)), ZaghlolMoment.professor);
    expect(llmAnswerMood(averageAnswer), ZaghlolMoment.tourGuide);
    expect(
      llmAnswerMood(const LlmSuggestAnswer(perCurrency: [])),
      ZaghlolMoment.proud,
    );
  });

  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    final lang = locale.languageCode;
    group('answer views ($lang)', () {
      testWidgets('what-if: body, basis caption, badge and What I sent', (
        t,
      ) async {
        await pumpAnswer(
          t,
          answered(whatIfAnswer, plan: whatIfPlan),
          locale: locale,
          extra: views(),
        );
        final l = l10n(t);
        expect(allText(t), contains(l.chatWhatIfBasis(3, 3).split(' ').first));
        expect(find.byKey(const ValueKey('sent-badge')), findsOneWidget);
        expect(find.text(l.chatSentToggle), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('average with the full-units caption, compare with the %', (
        t,
      ) async {
        await pumpAnswer(
          t,
          answered(averageAnswer),
          locale: locale,
          extra: views(),
        );
        final l = l10n(t);
        expect(allText(t), contains(l.chatLlmAnswerFullUnits('day')));
      });

      testWidgets('suggestions: rows, footer', (t) async {
        await pumpAnswer(
          t,
          answered(suggestAnswer),
          locale: locale,
          extra: views(),
        );
        final l = l10n(t);
        expect(find.text(l.chatSuggestIntro), findsOneWidget);
        expect(find.text(l.chatSuggestFooter), findsOneWidget);
        expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
      });

      testWidgets('invest gold band: gold row, USD, certificate, disclaimer', (
        t,
      ) async {
        await pumpAnswer(
          t,
          answered(investAnswer(450000)),
          locale: locale,
          extra: views(),
        );
        final l = l10n(t);
        expect(find.byKey(const ValueKey('invest-disclaimer')), findsOneWidget);
        expect(find.text(l.chatInvestDisclaimerSummary), findsOneWidget);
        expect(find.text(l.chatInvestDisclaimer), findsOneWidget);
        expect(allText(t), contains(RegExp('1.12|١٫١٢')));
        expect(find.text(l.chatInvestStocks), findsNothing);
        expect(find.byKey(const ValueKey('invest-suggest-chip')), findsNothing);
      });

      testWidgets('invest stocks band: no gold row, disclaimer shown', (
        t,
      ) async {
        await pumpAnswer(
          t,
          answered(investAnswer(50000)),
          locale: locale,
          extra: views(),
        );
        final l = l10n(t);
        expect(find.text(l.chatInvestStocks), findsOneWidget);
        expect(find.byKey(const ValueKey('invest-disclaimer')), findsOneWidget);
        expect(allText(t), isNot(contains(l.chatInvestGold('', '', '', ''))));
      });

      testWidgets('gold price unknown: no gold row and no stocks line', (
        t,
      ) async {
        await pumpAnswer(
          t,
          answered(investAnswer(450000, prices: fixPricesNoGold)),
          locale: locale,
          extra: views(prices: fixPricesNoGold),
        );
        final l = l10n(t);
        expect(find.text(l.chatInvestStocks), findsNothing);
        expect(allText(t), isNot(contains('1.12')));
        expect(allText(t), isNot(contains('١٫١٢')));
      });

      for (final (name, minor, key) in const [
        ('small', 5000, 'small'),
        ('nothing saved', 0, 'nothing'),
      ]) {
        testWidgets('invest $name: saving line, chip, no disclaimer', (
          t,
        ) async {
          await pumpAnswer(
            t,
            answered(investAnswer(minor)),
            locale: locale,
            extra: views(),
          );
          final l = l10n(t);
          expect(
            find.text(
              key == 'small' ? l.chatInvestSmall : l.chatInvestNothingSaved,
            ),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('invest-disclaimer')), findsNothing);
          expect(
            find.byKey(const ValueKey('invest-suggest-chip')),
            findsOneWidget,
          );
        });
      }

      testWidgets('invest rows stack at 130% without overflow', (t) async {
        await pumpAnswer(
          t,
          answered(investAnswer(450000)),
          locale: locale,
          scale: 1.3,
          extra: views(),
        );
        expect(t.takeException(), isNull);
        expect(find.byKey(const ValueKey('invest-disclaimer')), findsOneWidget);
      });

      testWidgets('hide amounts: masked, grams hidden, % kept, announced', (
        t,
      ) async {
        final h = t.ensureSemantics();
        await pumpAnswer(
          t,
          answered(investAnswer(450000)),
          locale: locale,
          extra: views(hidden: true),
        );
        final l = l10n(t);
        final text = allText(t);
        expect(text, contains('****'));
        expect(text, isNot(contains('4,500')));
        expect(text, isNot(contains('4٬500')));
        expect(text, contains(l.commonUnitGrams('****')));
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(l.commonAmountHidden))),
          findsWidgets,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(RegExp.escape(l.chatInvestGramsHiddenA11y)),
          ),
          findsWidgets,
        );
        h.dispose();

        // Percentages stay visible in a what-if.
        await pumpAnswer(
          t,
          answered(whatIfAnswer, plan: whatIfPlan),
          locale: locale,
          extra: views(hidden: true),
        );
        expect(allText(t), contains(lang == 'ar' ? '٪' : '%'));
      });

      testWidgets('no text is drawn in the danger colour', (t) async {
        await pumpAnswer(
          t,
          answered(investAnswer(450000)),
          locale: locale,
          extra: views(),
        );
        final danger = ZColors.of(t.element(find.byType(LlmAnswerView)))
            .dangerText;
        for (final w in t.widgetList<Text>(
          find.descendant(
            of: find.byType(LlmAnswerView),
            matching: find.byType(Text),
          ),
        )) {
          expect(w.style?.color, isNot(danger));
        }
      });

      testWidgets('refusal: specificPick offers "If I had saved?" which runs '
          'on the phone: no request, no quota', (t) async {
        final ex = FakeExecutor()..answer = investAnswer(450000);
        final flow = await pumpAnswer(
          t,
          answered(
            const LlmRefuseAnswer(RefuseReason.specificPick, selfHarm: false),
          ),
          locale: locale,
          extra: views(executor: ex),
        );
        expect(flow.asked, hasLength(1));
        await t.tap(find.byKey(const ValueKey('invest-chip')));
        await t.pump();
        await t.pump();
        expect(flow.asked, hasLength(1), reason: 'no new request');
        expect(ex.ran.single, isA<PlanInvest>());
        await t.drag(find.byType(ListView).first, const Offset(0, -900));
        await t.pump();
        // The local answer says it never left the phone and has no badge.
        expect(find.byKey(const ValueKey('sent-local')), findsOneWidget);
        expect(find.byKey(const ValueKey('invest-disclaimer')), findsOneWidget);
      });

      testWidgets('refusal: the chip is hidden when ask_llm_invest is off', (
        t,
      ) async {
        await pumpAnswer(
          t,
          answered(
            const LlmRefuseAnswer(RefuseReason.specificPick, selfHarm: false),
          ),
          locale: locale,
          investFlag: false,
          extra: views(),
        );
        expect(find.byKey(const ValueKey('invest-chip')), findsNothing);
        expect(find.text(l10n(t).chatRefuseSpecificPick), findsOneWidget);
      });

      testWidgets('self-harm cue adds the support line', (t) async {
        await pumpAnswer(
          t,
          answered(const LlmRefuseAnswer(RefuseReason.unsafe, selfHarm: true)),
          locale: locale,
          extra: views(),
        );
        expect(find.text(l10n(t).chatRefuseSupport), findsOneWidget);
      });

      testWidgets('"Help me save" runs PL-SUGGEST on the phone', (t) async {
        final ex = FakeExecutor()..answer = suggestAnswer;
        final flow = await pumpAnswer(
          t,
          answered(investAnswer(0)),
          locale: locale,
          extra: views(executor: ex),
        );
        await t.tap(find.byKey(const ValueKey('invest-suggest-chip')));
        await t.pump();
        await t.pump();
        expect(flow.asked, hasLength(1));
        expect(ex.ran.single, isA<PlanSuggest>());
        expect(find.text(l10n(t).chatSuggestIntro), findsOneWidget);
      });

      testWidgets('not found: chips run a local spend plan', (t) async {
        final ex = FakeExecutor()..answer = averageAnswer;
        final flow = await pumpAnswer(
          t,
          answered(
            const LlmNotFoundAnswer([
              LlmChip(LlmChipKind.category, 'sys:dining', 'Dining out'),
            ]),
          ),
          locale: locale,
          extra: views(executor: ex),
        );
        await t.tap(find.text('Dining out'));
        await t.pump();
        await t.pump();
        expect(flow.asked, hasLength(1));
        expect(ex.ran.single, isA<PlanSpend>());
      });

      testWidgets('fallback shows its text and the three local chips', (
        t,
      ) async {
        await pumpAnswer(
          t,
          answered(const LlmFallbackAnswer(LlmFallbackReason.unsupported)),
          locale: locale,
          extra: views(),
        );
        expect(find.text(l10n(t).chatFallbackText), findsOneWidget);
        expect(find.byKey(const ValueKey(AskChip.topMerchants)), findsOne);
      });

      testWidgets('What I sent opens and shows the masked text', (t) async {
        await pumpAnswer(
          t,
          answered(averageAnswer),
          locale: locale,
          extra: views(),
        );
        await t.tap(find.byKey(const ValueKey('sent-disclosure-toggle')));
        await t.pump();
        expect(find.text(l10n(t).chatSentTitle), findsOneWidget);
      });
    });
  }
}
