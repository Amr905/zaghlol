// T-346: S-50 online-helper states (ask-llm-ux §1). The flow is faked; data
// is synthetic.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart' show AbortSignal;
import 'package:zaghlol/core/flags/flags_providers.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/llm/llm_quota_snapshot.dart';
import 'package:zaghlol/features/ask/application/llm_ask_flow.dart';
import 'package:zaghlol/features/ask/data/ask_providers.dart';
import 'package:zaghlol/features/ask/data/llm_ask_providers.dart';
import 'package:zaghlol/features/ask/domain/ask_models.dart';
import 'package:zaghlol/features/ask/domain/llm_answer_models.dart';
import 'package:zaghlol/features/ask/presentation/ask_screen.dart';
import 'package:zaghlol/features/ask/presentation/llm_ask_ui.dart';
import 'package:zaghlol/features/ask/presentation/sent_disclosure.dart';
import 'package:zaghlol/features/ask/presentation/sent_text_parser.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/settings/presentation/privacy_ask_llm_section.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../budget/presentation/budget_test_support.dart';
import 'ask_screen_test.dart' show FakeEngine, FixedToday;

typedef Script = Stream<AskLlmState> Function(String q, AbortSignal? stop);

class FakeFlow implements LlmAskFlow {
  FakeFlow(this.script);
  final Script script;
  final List<String> asked = [];

  @override
  Stream<AskLlmState> ask(String question, {AbortSignal? stop}) {
    asked.add(question);
    return script(question, stop);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Gold extends EntitlementNotifier {
  @override
  EntitlementState build() {
    Future.microtask(() => applyVerified(verified: true, status: 'active'));
    return EntitlementState.free;
  }
}

final _quota = LlmQuotaSnapshot(
  limit: 5,
  remaining: 3,
  resetsAt: DateTime.utc(2026, 11, 30, 22),
);

Stream<AskLlmState> _one(AskLlmState s) => Stream.value(s);

Future<List<Object>> pumpLlm(
  WidgetTester tester,
  Script script, {
  Locale locale = const Locale('en'),
  bool dark = false,
  double scale = 1.0,
  bool flag = true,
  bool gold = false,
  LlmQuotaSnapshot? quota,
  bool pausedStored = false,
  List<Override> extra = const [],
}) async {
  await initDateFormatting();
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final flow = FakeFlow(script);
  final trig = <GoldCapability>[];
  await tester.pumpWidget(
    harness(
      const AskScreen(),
      locale: locale,
      dark: dark,
      scale: scale,
      overrides: [
        askEngineProvider.overrideWith(
          (ref) async =>
              FakeEngine((_, _) async => const AskUnavailableAnswer()),
        ),
        askCategoryNamesProvider.overrideWith((ref) async => {}),
        todayProvider.overrideWith(FixedToday.new),
        featureFlagProvider.overrideWith((ref, f) => flag),
        llmAskFlowProvider.overrideWith((ref) async => flow),
        askQuotaSnapshotProvider.overrideWith((ref) async => quota),
        askQuotaStateProvider.overrideWith(
          (ref) async => (snapshot: quota, paused: pausedStored),
        ),
        paywallTriggerProvider.overrideWithValue(trig.add),
        if (gold) entitlementStateProvider.overrideWith(_Gold.new),
        ...extra,
      ],
    ),
  );
  await tester.pump();
  return [flow, trig];
}

AppLocalizations l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(AskScreen)));

Future<void> ask(WidgetTester t, [String q = 'hello there']) async {
  await t.enterText(find.byType(TextField), q);
  await t.pump();
  await t.tap(find.byKey(const ValueKey('ask-send')));
  await t.pump();
  await t.pump();
}

MaskUnresolved _unresolved(MaskUnresolvedReason r) => MaskUnresolved(r, const [
  MaskAccount(id: 'a1', label: 'Card A', last4: '1234'),
  MaskAccount(id: 'a2', label: 'Card B', last4: '1234'),
]);

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    final lang = locale.languageCode;

    group('S-50 online helper ($lang)', () {
      testWidgets('flag off: no counter, no Stop, plain hint', (t) async {
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmOffline()),
          locale: locale,
          flag: false,
          quota: _quota,
        );
        final l = l10n(t);
        expect(find.byKey(const ValueKey('ask-quota-counter')), findsNothing);
        expect(find.text(l.chatLlmInputHint), findsNothing);
        expect(find.text(l.chatMainInputHint), findsOneWidget);
      });

      testWidgets('idle: counter n left, tap opens the info sheet', (t) async {
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmOffline()),
          locale: locale,
          quota: _quota,
        );
        final l = l10n(t);
        expect(find.text(l.chatLlmInputHint), findsOneWidget);
        expect(find.text(l.chatQuotaRemaining(3, 3)), findsOneWidget);
        expect(
          find.bySemanticsLabel(l.chatQuotaRemainingA11y(3, 3)),
          findsOneWidget,
        );
        expect(
          t.getSize(find.byKey(const ValueKey('ask-quota-counter'))).height,
          greaterThanOrEqualTo(48),
        );
        await t.tap(find.byKey(const ValueKey('ask-quota-counter')));
        await t.pumpAndSettle();
        expect(find.text(l.chatQuotaInfoTitle), findsOneWidget);
        expect(find.text(l.chatQuotaInfoBody), findsOneWidget);
      });

      testWidgets('idle: unknown count shows the dash', (t) async {
        await pumpLlm(t, (_, _) => _one(const AskLlmOffline()), locale: locale);
        final l = l10n(t);
        expect(find.text(l.chatQuotaUnknown), findsOneWidget);
        expect(find.bySemanticsLabel(l.chatQuotaUnknownA11y), findsOneWidget);
      });

      testWidgets('typing: counter from 250, input blocked at 300', (t) async {
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmOffline()),
          locale: locale,
          quota: _quota,
        );
        final l = l10n(t);
        await t.enterText(find.byType(TextField), 'a' * 249);
        await t.pump();
        expect(find.text(l.chatLlmInputCounter(249, 300)), findsNothing);
        await t.enterText(find.byType(TextField), 'a' * 250);
        await t.pump();
        expect(find.text(l.chatLlmInputCounter(250, 300)), findsOneWidget);
        await t.enterText(find.byType(TextField), 'a' * 320);
        await t.pump();
        expect(
          t.widget<TextField>(find.byType(TextField)).controller!.text.length,
          300,
        );
        expect(find.text(l.chatMainTooLong(300, '300')), findsOneWidget);
      });

      testWidgets('last question: note above the input', (t) async {
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmOffline()),
          locale: locale,
          quota: LlmQuotaSnapshot(
            limit: 5,
            remaining: 1,
            resetsAt: DateTime.utc(2026, 11, 30, 22),
          ),
        );
        expect(find.text(l10n(t).chatQuotaLastOne), findsOneWidget);
      });

      testWidgets('sending: status row, Stop, then stopped snackbar', (
        t,
      ) async {
        final gate = Completer<void>();
        late AbortSignal? sig;
        await pumpLlm(
          t,
          (_, stop) async* {
            sig = stop;
            yield const AskLlmSending();
            await gate.future;
            yield const AskLlmStopped();
          },
          locale: locale,
          quota: _quota,
        );
        final l = l10n(t);
        await ask(t);
        expect(find.text(l.chatLlmStatusSending), findsOneWidget);
        expect(find.byKey(const ValueKey('ask-send')), findsNothing);
        final stop = find.byKey(const ValueKey('ask-stop'));
        expect(stop, findsOneWidget);
        expect(t.getSize(stop).shortestSide, greaterThanOrEqualTo(48));
        expect(
          find.bySemanticsLabel(l.chatLlmStatusThinkingA11y),
          findsOneWidget,
        );
        await t.tap(stop);
        expect(sig!.aborted, isTrue);
        gate.complete();
        await t.pump();
        await t.pump();
        expect(find.text(l.chatLlmStatusStopped), findsOneWidget);
        expect(find.byKey(const ValueKey('ask-send')), findsOneWidget);
        expect(find.byKey(const ValueKey('ask-typing')), findsNothing);
      });

      testWidgets('computing: status line changes', (t) async {
        final gate = Completer<void>();
        await pumpLlm(
          t,
          (_, _) async* {
            yield const AskLlmComputing();
            await gate.future;
          },
          locale: locale,
          quota: _quota,
        );
        await ask(t);
        expect(find.text(l10n(t).chatLlmStatusComputing), findsWidgets);
        gate.complete();
        await t.pump();
      });

      testWidgets('clarify: bubble, chips, not sent; chip fills the field', (
        t,
      ) async {
        await pumpLlm(
          t,
          (_, _) => _one(
            AskLlmClarify(_unresolved(MaskUnresolvedReason.ambiguousCard)),
          ),
          locale: locale,
          quota: _quota,
        );
        final l = l10n(t);
        await ask(t, 'spent on card 1234');
        expect(find.text(l.chatClarifySameLast4('1234')), findsOneWidget);
        expect(find.text(l.chatClarifyNotSent), findsOneWidget);
        expect(find.byKey(const ValueKey('ask-clarify-a1')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('ask-clarify-a2')));
        await t.pump();
        expect(
          t.widget<TextField>(find.byType(TextField)).controller!.text,
          'spent on card 1234 Card B',
        );
      });

      testWidgets('clarify: unknown card names the typed last 4', (t) async {
        await pumpLlm(
          t,
          (_, _) =>
              _one(AskLlmClarify(_unresolved(MaskUnresolvedReason.noSuchCard))),
          locale: locale,
          quota: _quota,
        );
        await ask(t, 'card 9876 spend');
        expect(find.text(l10n(t).chatClarifyNoCard('9876')), findsOneWidget);
      });

      testWidgets('offline: bubble, caption, 3 chips', (t) async {
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmOffline()),
          locale: locale,
          quota: _quota,
        );
        final l = l10n(t);
        await ask(t);
        expect(find.text(l.chatLlmStatusOffline), findsOneWidget);
        expect(find.text(l.chatLlmStatusNotQueued), findsOneWidget);
        expect(find.byType(ActionChip), findsNWidgets(3));
      });

      testWidgets('timeout: text + Try again resends the same question', (
        t,
      ) async {
        var n = 0;
        final r = await pumpLlm(
          t,
          (q, _) {
            n++;
            return _one(
              n == 1
                  ? const AskLlmFailed(AskLlmFailure.timeout)
                  : const AskLlmOffline(),
            );
          },
          locale: locale,
          quota: _quota,
        );
        final l = l10n(t);
        await ask(t, 'same q');
        expect(find.text(l.chatLlmStatusTimeout), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('ask-try-again')));
        await t.pump();
        await t.pump();
        expect((r[0] as FakeFlow).asked, ['same q', 'same q']);
        expect(find.text(l.chatLlmStatusTimeout), findsNothing);
        expect(find.text(l.chatMainUserA11y('same q')), findsNothing);
      });

      testWidgets('error and integrity offer Try again', (t) async {
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmFailed(AskLlmFailure.integrity)),
          locale: locale,
          quota: _quota,
        );
        final l = l10n(t);
        await ask(t);
        expect(find.text(l.chatLlmStatusIntegrity), findsOneWidget);
        expect(find.byKey(const ValueKey('ask-try-again')), findsOneWidget);
      });

      testWidgets('upstream failure shows the generic error + Try again', (
        t,
      ) async {
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmFailed(AskLlmFailure.upstream)),
          locale: locale,
          quota: _quota,
        );
        await ask(t);
        expect(find.text(l10n(t).chatLlmStatusError), findsOneWidget);
        expect(find.byKey(const ValueKey('ask-try-again')), findsOneWidget);
      });

      testWidgets('slow down: no retry button', (t) async {
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmFailed(AskLlmFailure.slowDown)),
          locale: locale,
          quota: _quota,
        );
        await ask(t);
        expect(find.text(l10n(t).chatLlmStatusSlowDown), findsOneWidget);
        expect(find.byKey(const ValueKey('ask-try-again')), findsNothing);
      });

      testWidgets('paused: bubble, counter hidden', (t) async {
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmPaused()),
          locale: locale,
          quota: _quota,
        );
        expect(find.byKey(const ValueKey('ask-quota-counter')), findsOneWidget);
        await ask(t);
        expect(find.text(l10n(t).chatLlmStatusPaused), findsOneWidget);
        expect(find.byKey(const ValueKey('ask-quota-counter')), findsNothing);
      });

      testWidgets('paused (stored): counter hidden before any question', (
        t,
      ) async {
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmOffline()),
          locale: locale,
          quota: _quota,
          pausedStored: true,
        );
        expect(find.byKey(const ValueKey('ask-quota-counter')), findsNothing);
      });

      testWidgets('consent declined: bubble + chips', (t) async {
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmConsentDeclined()),
          locale: locale,
          quota: _quota,
        );
        await ask(t);
        expect(find.text(l10n(t).chatConsentDeclined), findsOneWidget);
        expect(find.byType(ActionChip), findsNWidgets(3));
      });

      testWidgets('exhausted Free: Gold hint; See Gold opens the paywall once, '
          'only on tap', (t) async {
        final r = await pumpLlm(
          t,
          (_, _) => _one(AskLlmQuotaOut(_quota)),
          locale: locale,
          quota: _quota,
        );
        final l = l10n(t);
        await ask(t);
        expect(find.text(l.chatQuotaGoldHint(50, 50)), findsOneWidget);
        expect(find.text(l.chatLlmStatusNotQueued), findsOneWidget);
        expect(r[1], isEmpty);
        await t.pumpAndSettle();
        final see = find.byKey(const ValueKey('ask-see-gold'));
        expect(t.getSize(see).height, greaterThanOrEqualTo(48));
        await t.tap(see);
        await t.pump();
        expect(r[1], hasLength(1));
      });

      testWidgets('exhausted Gold: reset date, no Gold hint', (t) async {
        await pumpLlm(
          t,
          (_, _) => _one(AskLlmQuotaOut(_quota)),
          locale: locale,
          quota: _quota,
          gold: true,
        );
        await t.pump();
        await ask(t);
        final l = l10n(t);
        expect(find.byKey(const ValueKey('ask-see-gold')), findsNothing);
        final date = ZDateFormat.date(
          DateTime.utc(2026, 12, 1),
          lang,
          DigitsMode.resolve(DigitsPref.auto, lang),
        );
        expect(find.text(l.chatQuotaGoldOut(date)), findsOneWidget);
        expect(find.text(l.chatLlmStatusNotQueued), findsOneWidget);
      });

      testWidgets('answer: rendered through the view-builder seam', (t) async {
        await pumpLlm(
          t,
          (_, _) => _one(
            AskLlmAnswered(
              answer: LlmIncomeAnswer(period: _p, figures: const []),
              sentText: 'x',
              counted: true,
            ),
          ),
          locale: locale,
          quota: _quota,
          extra: [
            llmAnswerViewBuilderProvider.overrideWithValue(
              (context, a) => const Text('SEAM-ANSWER'),
            ),
          ],
        );
        await ask(t);
        expect(find.text('SEAM-ANSWER'), findsOneWidget);
      });

      testWidgets('130% idle: counter on its own line, no overflow', (t) async {
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmOffline()),
          locale: locale,
          quota: _quota,
          scale: 1.3,
        );
        expect(find.byKey(const ValueKey('ask-quota-counter')), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('status bubbles are polite live regions', (t) async {
        final h = t.ensureSemantics();
        await pumpLlm(
          t,
          (_, _) => _one(const AskLlmOffline()),
          locale: locale,
          quota: _quota,
        );
        await ask(t);
        final l = l10n(t);
        final node = t.getSemantics(
          find.bySemanticsLabel(
            RegExp(
              RegExp.escape(l.chatMainZaghlolA11y(l.chatLlmStatusOffline)),
            ),
          ),
        );
        expect(node.flagsCollection.isLiveRegion, isTrue);
        h.dispose();
      });
    });
  }

  test('parseSentText turns tokens into chips and hidden chips', () {
    final s = parseSentText('spent on ⟦CARD_1⟧ at ⟦MERCHANT_2⟧ call ⟦PHONE⟧?');
    expect(s.whereType<SentPlaceholder>().map((e) => e.n), [1, 2]);
    expect(s.whereType<SentPlaceholder>().first.kind, SentChipKind.card);
    expect(s.whereType<SentHidden>().single.kind, SentHiddenKind.phone);
    expect((s.first as SentPlain).text, 'spent on ');
  });
}

final _p = ChartPeriod.month(2026, 11);
