// T-187 / D-67 / FR-HOME-06: the eye toggle masks every amount. Synthetic data.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/notifications/application/notification_providers.dart';
import 'package:zaghlol/core/ui/z_hide_amounts_button.dart';
import 'package:zaghlol/core/ui/z_money_text.dart';
import 'package:zaghlol/features/ask/domain/ask_models.dart';
import 'package:zaghlol/features/ask/presentation/ask_answer_text.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/explanations.dart';
import 'package:zaghlol/features/insights/presentation/chart_explain_l10n.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';
import 'package:zaghlol/features/insights/presentation/insights_screen.dart';
import 'package:zaghlol/features/share_cards/domain/share_figures.dart';
import 'package:zaghlol/features/share_cards/presentation/share_card.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../support/hide_amounts_support.dart';
import '../home/presentation/home_harness.dart';
import '../insights/presentation/charts/charts_test_support.dart';

final _digit = RegExp(r'[0-9٠-٩]');
const _ar = Locale('ar', 'EG');
const _en = Locale('en');

Widget _app(Widget child, HideAmountsHarness h, {Locale locale = _en}) =>
    ProviderScope(
      overrides: h.overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ZaghlolTheme.light,
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  test('notification text does not mask while the setting still loads', () {
    final shown = Provider<bool>(notificationHidden);
    final loading = ProviderContainer(
      overrides: [
        hideAmountsAppProvider.overrideWith(
          (ref) => const Stream<bool>.empty(),
        ),
      ],
    );
    addTearDown(loading.dispose);
    expect(loading.read(shown), isFalse);
    expect(
      loading.read(hideAmountsProvider),
      isTrue,
      reason: 'screens fail closed',
    );
  });

  group('eye button', () {
    for (final locale in [_en, _ar]) {
      final tag = locale.languageCode;
      testWidgets('$tag: toggles, announces the next action, 48 dp', (
        tester,
      ) async {
        final h = HideAmountsHarness();
        addTearDown(h.dispose);
        final handle = tester.ensureSemantics();
        final ticks = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            ticks.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          _app(const ZHideAmountsButton(), h, locale: locale),
        );
        await tester.pump();
        final l = AppLocalizations.of(
          tester.element(find.byType(ZHideAmountsButton)),
        );
        final size = tester.getSize(find.byType(IconButton));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(find.bySemanticsLabel(l.commonAmountsHide), findsOneWidget);
        expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

        await tester.tap(find.byKey(const Key('hide-amounts-toggle')));
        await tester.pump();
        await tester.pump();
        expect(h.value, isTrue);
        expect(find.bySemanticsLabel(l.commonAmountsShow), findsOneWidget);
        expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
        expect(
          ticks.where((c) => c.method == 'HapticFeedback.vibrate'),
          isNotEmpty,
          reason: 'haptic tick',
        );

        await tester.tap(find.byKey(const Key('hide-amounts-toggle')));
        await tester.pump();
        await tester.pump();
        expect(h.value, isFalse);
        handle.dispose();
      });
    }
  });

  group('ZMoneyText', () {
    testWidgets('masked text announces "amount hidden", not the glyphs', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = HideAmountsHarness();
      addTearDown(h.dispose);
      await tester.pumpWidget(
        _app(
          const ZMoneyText(
            text: '-****',
            unit: 'EGP',
            semanticsLabel: 'minus 450',
          ),
          h,
        ),
      );
      final l = AppLocalizations.of(tester.element(find.byType(ZMoneyText)));
      expect(find.bySemanticsLabel(l.commonAmountHidden), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'\*|450')), findsNothing);
      handle.dispose();
    });

    testWidgets('masked: true masks digits of caller-formatted text', (
      tester,
    ) async {
      final h = HideAmountsHarness();
      addTearDown(h.dispose);
      await tester.pumpWidget(
        _app(const ZMoneyText(text: '-١٬٢٣٤٫٥٠', masked: true, unit: 'ج.م'), h),
      );
      expect(find.textContaining('-****'), findsOneWidget);
      expect(find.textContaining('١'), findsNothing);
    });
  });

  group('Home', () {
    for (final locale in [_en, _ar]) {
      final tag = locale.languageCode;
      testWidgets('$tag: masking on: no digit in any amount widget', (
        tester,
      ) async {
        final h = HideAmountsHarness(hidden: true);
        addTearDown(h.dispose);
        await pumpHome(
          tester,
          locale: locale,
          platform: TargetPlatform.android,
          value: model(),
          hideAmounts: h,
        );
        await expectNoAmountDigits(tester);
        expect(find.byKey(const Key('hide-amounts-toggle')), findsOneWidget);
      });
    }

    testWidgets('one tap on the eye hides, the next shows, instantly', (
      tester,
    ) async {
      final h = HideAmountsHarness();
      addTearDown(h.dispose);
      await pumpHome(
        tester,
        locale: _en,
        platform: TargetPlatform.android,
        value: model(),
        hideAmounts: h,
      );
      expect(find.textContaining('314'), findsWidgets);
      await tester.tap(find.byKey(const Key('hide-amounts-toggle')));
      await tester.pump();
      await tester.pump();
      await expectNoAmountDigits(tester);
      expect(find.textContaining('314'), findsNothing);
      await tester.tap(find.byKey(const Key('hide-amounts-toggle')));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('314'), findsWidgets);
    });
  });

  group('Charts', () {
    for (final locale in [_en, _ar]) {
      final tag = locale.languageCode;
      testWidgets('$tag: shapes stay, no amount text or label', (tester) async {
        final h = HideAmountsHarness(hidden: true);
        addTearDown(h.dispose);
        await tester.binding.setSurfaceSize(const Size(390, 3200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          harness(
            const ChartsScreen(),
            locale: locale,
            overrides: chartOverrides(),
            hideAmounts: h,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BarChart), findsOneWidget);
        expect(find.byType(PieChart), findsOneWidget);
        await expectNoAmountDigits(tester);
        // None of the synthetic figures (1,000 / 600 / 30,000 / 18,500 ...)
        // appears in any text or semantics label, in either digit script.
        final figure = RegExp(
          r'1[,٬]?000|600|٦٠٠|30[,٬]?000|٣٠[,٬]?٠٠٠|18[,٬]?\d00|900|٩٠٠',
        );
        expect(find.textContaining(figure), findsNothing);
        expect(find.bySemanticsLabel(figure), findsNothing);
        handle.dispose();
      });
    }

    testWidgets('Insights: one tap on the eye masks the charts, a second '
        'shows them', (tester) async {
      final h = HideAmountsHarness();
      addTearDown(h.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(
          const InsightsScreen(),
          locale: _en,
          overrides: chartOverrides(),
          hideAmounts: h,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1,000'), findsWidgets);
      await tester.tap(find.byKey(const Key('hide-amounts-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1,000'), findsNothing);
      expect(find.byType(PieChart), findsOneWidget);
      await tester.tap(find.byKey(const Key('hide-amounts-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1,000'), findsWidgets);
    });

    testWidgets('masking off shows the same screen with its figures', (
      tester,
    ) async {
      final h = HideAmountsHarness();
      addTearDown(h.dispose);
      await tester.binding.setSurfaceSize(const Size(390, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(
          const ChartsScreen(),
          locale: _en,
          overrides: chartOverrides(),
          hideAmounts: h,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1,000'), findsWidgets);
    });
  });

  group('Explain this chart and Ask Zaghlol', () {
    testWidgets('explanation arguments: money masked, percent and count kept', (
      tester,
    ) async {
      final h = HideAmountsHarness(hidden: true);
      addTearDown(h.dispose);
      late ExplainFormat f;
      await tester.pumpWidget(
        _app(
          Consumer(
            builder: (context, ref, _) {
              f = ExplainFormat.of(
                context,
                ref,
                (id) => id ?? '',
                now: 'this cycle',
                prev: 'last cycle',
              );
              return const SizedBox();
            },
          ),
          h,
        ),
      );
      await tester.pump();
      final egp = Currency.of('EGP');
      expect(f.arg(MoneyArg(Money(egp, -123400))), contains('-****'));
      expect(f.arg(MoneyArg(Money(egp, -123400))), isNot(contains('1,234')));
      expect(
        f.arg(const UnitAmountArg('XAU21', 12500)),
        isNot(contains('125')),
      );
      expect(f.arg(const PercentArg(2750)), '28%');
      expect(f.arg(const CountArg(3)), '3');
    });

    String ask(String lang, DigitsMode d, {required bool hidden}) {
      final answer = AskSpendAnswer(
        period: ChartPeriod.month(2026, 11),
        periodDefaulted: true,
        target: AskTarget.everything,
        figures: [
          Money(Currency.of('EGP'), 120000),
          Money(Currency.of('USD'), 3000),
        ],
      );
      return AskAnswerTextBuilder(
        l: lookupAppLocalizations(Locale(lang)),
        languageCode: lang,
        digits: d,
        hidden: hidden,
        today: CivilDate(2026, 11, 15),
        categoryNames: const {},
      ).build(answer).lines.join(' ');
    }

    test('an Ask answer shows **** for every amount, in both languages', () {
      for (final (lang, d) in [
        ('en', DigitsMode.western),
        ('ar', DigitsMode.arabicIndic),
      ]) {
        final shown = ask(lang, d, hidden: false);
        final hidden = ask(lang, d, hidden: true);
        expect(shown, contains(_digit));
        expect(hidden, contains('****'));
        expect(hidden, isNot(contains('1,200')));
        expect(hidden, isNot(contains('١٬٢٠٠')));
        expect(hidden, isNot(contains('30')));
      }
    });
  });

  group('Share card', () {
    for (final hidden in [true, false]) {
      testWidgets('hiding ${hidden ? 'on' : 'off'}: amount variant '
          '${hidden ? 'not drawn' : 'drawn'}', (tester) async {
        final figure = ShareFigure(
          template: ShareTemplate.savings,
          percentBp: 3800,
          amount: Money(Currency.of('EGP'), 1234500),
        );
        final h = HideAmountsHarness(hidden: hidden);
        addTearDown(h.dispose);
        await tester.pumpWidget(
          _app(ShareCard(figure: figure, showAmounts: true), h),
        );
        await tester.pump();
        expect(
          find.textContaining('12,345'),
          hidden ? findsNothing : findsOneWidget,
        );
        expect(
          find.textContaining('38%'),
          hidden ? findsOneWidget : findsNothing,
        );
      });
    }
  });
}
