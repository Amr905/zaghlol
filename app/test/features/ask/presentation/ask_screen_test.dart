// T-111: S-50 states. Synthetic data only; the engine is faked.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/ask/application/ask_engine.dart';
import 'package:zaghlol/features/ask/data/ask_providers.dart';
import 'package:zaghlol/features/ask/domain/ask_models.dart';
import 'package:zaghlol/features/ask/presentation/ask_screen.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../budget/presentation/budget_test_support.dart';

class FixedToday extends TodayNotifier {
  @override
  CivilDate build() => CivilDate(2026, 11, 13);
}

class FakeEngine implements AskEngine {
  FakeEngine(this.onAsk);
  final Future<AskAnswer> Function(String? q, AskChip? chip) onAsk;
  final List<String> asked = [];

  @override
  Future<AskAnswer> ask(
    String question, {
    int roastSeed = 0,
    Set<RoastKind> recentRoasts = const {},
  }) {
    asked.add(question);
    return onAsk(question, null);
  }

  @override
  Future<AskAnswer> askChip(
    AskChip chip, {
    int roastSeed = 0,
    Set<RoastKind> recentRoasts = const {},
  }) => onAsk(null, chip);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ChartPeriod _month(int m) => ChartPeriod.month(2026, m);

AskAnswer spend2() => AskSpendAnswer(
  period: _month(11),
  periodDefaulted: true,
  target: AskTarget.everything,
  figures: [egpM(1200), usdM(30)],
);

AskAnswer compare() => AskCompareAnswer(
  current: _month(11),
  previous: _month(10),
  target: AskTarget.everything,
  figures: [
    AskCompareFigure(current: egpM(1200), previous: egpM(800), deltaBp: 5000),
  ],
);

List<Override> overrides(FakeEngine e) => [
  askEngineProvider.overrideWith((ref) async => e),
  askCategoryNamesProvider.overrideWith((ref) async => {}),
  todayProvider.overrideWith(FixedToday.new),
];

Future<void> pump(
  WidgetTester tester,
  FakeEngine e, {
  Locale locale = const Locale('en'),
  bool dark = false,
  double scale = 1.0,
}) async {
  await initDateFormatting();
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    harness(
      const AskScreen(),
      locale: locale,
      dark: dark,
      scale: scale,
      overrides: overrides(e),
    ),
  );
  await tester.pump();
}

AppLocalizations l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(AskScreen)));

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    final lang = locale.languageCode;

    testWidgets('empty: greeting + 3 chips, send disabled ($lang)', (
      tester,
    ) async {
      await pump(
        tester,
        FakeEngine((_, _) async => spend2()),
        locale: locale,
        scale: 1.3,
      );
      final l = l10n(tester);
      expect(find.text(l.chatMainGreeting), findsOneWidget);
      expect(find.byType(ActionChip), findsNWidgets(3));
      final send = tester.widget<IconButton>(
        find.byKey(const ValueKey('ask-send')),
      );
      expect(send.onPressed, isNull);
      expect(find.byKey(const ValueKey('zaghlol-avatar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one figure per currency, never summed ($lang)', (
      tester,
    ) async {
      final e = FakeEngine((_, _) async => spend2());
      await pump(tester, e, locale: locale, scale: 1.3);
      await tester.enterText(find.byType(TextField), 'x');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ask-send')));
      await tester.pumpAndSettle();
      expect(e.asked, ['x']);
      expect(find.textContaining('USD'), findsOneWidget);
      expect(find.textContaining('1,230'), findsNothing);
      expect(find.textContaining('1230'), findsNothing);
      expect(find.textContaining('١٬٢٣٠'), findsNothing);
    });

    testWidgets('compare answer shows a mini chart ($lang)', (tester) async {
      await pump(tester, FakeEngine((_, _) async => compare()), locale: locale);
      await tester.tap(find.byType(ActionChip).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ask-mini-chart')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unknown question: fallback with chips, no number ($lang)', (
      tester,
    ) async {
      final e = FakeEngine(
        (_, _) async => const AskFallbackAnswer(
          AskUnrecognizedReason.noIntent,
          askFallbackChips,
        ),
      );
      await pump(tester, e, locale: locale);
      await tester.enterText(find.byType(TextField), 'blah');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ask-send')));
      await tester.pumpAndSettle();
      final l = l10n(tester);
      expect(find.text(l.chatFallbackText), findsOneWidget);
      expect(find.byType(ActionChip), findsNWidgets(3));
    });

    testWidgets('no data ($lang)', (tester) async {
      final e = FakeEngine(
        (_, _) async => const AskNoDataAnswer(
          AskIntent.spend,
          AskNoDataReason.noTransactions,
        ),
      );
      await pump(tester, e, locale: locale);
      await tester.tap(find.byType(ActionChip).first);
      await tester.pumpAndSettle();
      expect(find.text(l10n(tester).chatAnswerNoDataGeneric), findsOneWidget);
    });

    testWidgets('loading shows the typing indicator ($lang)', (tester) async {
      final c = Completer<AskAnswer>();
      await pump(tester, FakeEngine((_, _) => c.future), locale: locale);
      await tester.tap(find.byType(ActionChip).first);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('ask-typing')), findsOneWidget);
      c.complete(spend2());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ask-typing')), findsNothing);
    });

    testWidgets('error then retry ($lang)', (tester) async {
      var fail = true;
      final e = FakeEngine((_, _) async {
        if (fail) return const AskUnavailableAnswer();
        return spend2();
      });
      await pump(tester, e, locale: locale);
      await tester.tap(find.byType(ActionChip).first);
      await tester.pumpAndSettle();
      final l = l10n(tester);
      expect(find.text(l.chatAnswerError), findsOneWidget);
      fail = false;
      await tester.tap(find.text(l.commonActionTryAgain));
      await tester.pumpAndSettle();
      expect(find.text(l.chatAnswerError), findsNothing);
      expect(find.textContaining('USD'), findsOneWidget);
    });

    testWidgets('roast toggle posts a note; clear empties ($lang)', (
      tester,
    ) async {
      await pump(tester, FakeEngine((_, _) async => spend2()), locale: locale);
      final l = l10n(tester);
      await tester.tap(find.byKey(const ValueKey('ask-roast-toggle')));
      await tester.pumpAndSettle();
      expect(find.text(l.chatRoastOn), findsOneWidget);
      await tester.tap(find.byTooltip(l.chatMainClear));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.chatMainClear).last);
      await tester.pumpAndSettle();
      expect(find.text(l.chatRoastOn), findsNothing);
      expect(find.text(l.chatMainGreeting), findsOneWidget);
    });
  }

  testWidgets('input over 300 characters disables send', (tester) async {
    await pump(tester, FakeEngine((_, _) async => spend2()));
    await tester.enterText(find.byType(TextField), 'a' * 301);
    await tester.pump();
    final send = tester.widget<IconButton>(
      find.byKey(const ValueKey('ask-send')),
    );
    expect(send.onPressed, isNull);
    expect(find.text(l10n(tester).chatMainTooLong(300, '300')), findsOneWidget);
  });

  testWidgets('dark RTL compare renders without overflow', (tester) async {
    await pump(
      tester,
      FakeEngine((_, _) async => compare()),
      locale: const Locale('ar', 'EG'),
      dark: true,
    );
    await tester.tap(find.byType(ActionChip).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
