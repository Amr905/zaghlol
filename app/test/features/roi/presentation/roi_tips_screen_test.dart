// T-170: S-51 states, ar/en, text scale 1.3. Synthetic figures.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/flags/feature_flags.dart';
import 'package:zaghlol/core/flags/flags_providers.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_providers.dart';
import 'package:zaghlol/features/roi/data/roi_providers.dart';
import 'package:zaghlol/features/roi/presentation/roi_tips_providers.dart';
import 'package:zaghlol/features/roi/presentation/roi_tips_screen.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

RoiSuggestion tip(RoiRule rule, Currency c, {int y1 = 1440000}) =>
    RoiSuggestion(
      rule: rule,
      kinds: const [RoiProductKind.homeAppliance],
      currency: c,
      habitYear: Money(c, 2940000),
      year1Saving: Money(c, y1),
      year2Saving: Money(c, 2400000),
      monthly: Money(c, 245000),
      altMonthly: Money(c, 125000),
      idle: Money(c, 5000000),
      balance: Money(c, 1200000),
      exampleRateBp: 350,
    );

Future<List<String>> pump(
  WidgetTester t, {
  bool flag = true,
  bool gold = true,
  Locale locale = const Locale('en'),
  double scale = 1.0,
  bool dark = false,
  List<Currency>? currencies,
  Map<String, List<RoiSuggestion>>? tips,
  bool failTips = false,
  Widget home = const RoiTipsScreen(),
}) async {
  final paywall = <String>[];
  await t.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        featureFlagProvider.overrideWith(
          (ref, f) => flag && f == FeatureFlag.smartRoi,
        ),
        entitlementStateProvider.overrideWith(
          () => gold ? _GoldNotifier() : EntitlementNotifier(),
        ),
        paywallTriggerProvider.overrideWithValue((c) => paywall.add(c.name)),
        chartsCurrenciesProvider.overrideWith(
          (ref) async => currencies ?? [egp],
        ),
        roiSuggestionsProvider.overrideWith((ref, c) async {
          if (failTips) throw StateError('x');
          return tips?[c.code] ?? const [];
        }),
      ],
      child: MaterialApp(
        locale: locale,
        theme: dark ? ZaghlolTheme.dark : ZaghlolTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await t.pumpAndSettle();
  return paywall;
}

class _GoldNotifier extends EntitlementNotifier {
  @override
  EntitlementState build() {
    super.applyVerified(verified: true, status: 'active');
    return state;
  }
}

void main() {
  for (final loc in [const Locale('en'), const Locale('ar', 'EG')]) {
    final n = loc.languageCode;

    testWidgets('tips list, disclaimer on every tip, 1.3x ($n)', (t) async {
      await pump(
        t,
        locale: loc,
        scale: 1.3,
        tips: {
          'EGP': [tip(RoiRule.coffeeMachine, egp), tip(RoiRule.idleCash, egp)],
        },
      );
      expect(t.takeException(), isNull);
      final l = await AppLocalizations.delegate.load(loc);
      expect(find.text(l.roiRuleCoffeeTitle), findsOneWidget);
      expect(find.text(l.roiRuleIdleCashTitle), findsOneWidget);
      // Top disclaimer (summary + full) plus the summary on each of 2 tips.
      expect(find.text(l.roiTipsDisclaimerSummary), findsNWidgets(3));
      expect(find.text(l.roiTipsDisclaimer), findsOneWidget);
      expect(find.text(l.roiTipsShare), findsNWidgets(2));
    });

    testWidgets('empty state ($n)', (t) async {
      await pump(t, locale: loc, scale: 1.3);
      final l = await AppLocalizations.delegate.load(loc);
      expect(find.text(l.roiTipsEmptyTitle), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('flag off: nothing is built', (t) async {
    await pump(
      t,
      flag: false,
      tips: {
        'EGP': [tip(RoiRule.coffeeMachine, egp)],
      },
    );
    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.roiRuleCoffeeTitle), findsNothing);
    expect(find.text(l.roiTipsDisclaimerSummary), findsNothing);
  });

  testWidgets('flag off: the embeddable view is empty too', (t) async {
    await pump(t, flag: false, home: const Scaffold(body: RoiTipsView()));
    expect(find.byType(RoiTipsView), findsOneWidget);
    expect(find.byType(RoiTipCard), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('Free user sees the locked state and the paywall opens', (
    t,
  ) async {
    final paywall = await pump(
      t,
      gold: false,
      tips: {
        'EGP': [tip(RoiRule.coffeeMachine, egp)],
      },
    );
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.roiTipsLockedBody), findsOneWidget);
    expect(find.byType(RoiTipCard), findsNothing);
    await t.tap(find.text(l.commonGoldUnlock));
    expect(paywall, isNotEmpty);
  });

  testWidgets('error state offers retry', (t) async {
    await pump(t, failTips: true);
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.chatAnswerError), findsOneWidget);
    expect(find.text(l.commonActionTryAgain), findsOneWidget);
  });

  testWidgets('not for me hides the tip', (t) async {
    await pump(
      t,
      tips: {
        'EGP': [tip(RoiRule.coffeeMachine, egp)],
      },
    );
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await t.tap(find.text(l.roiTipsNotForMe));
    await t.pumpAndSettle();
    expect(find.text(l.roiRuleCoffeeTitle), findsNothing);
    expect(find.text(l.roiTipsDismissed), findsOneWidget);
    expect(find.text(l.roiTipsEmptyTitle), findsOneWidget);
  });

  testWidgets('each currency keeps its own figures, no summing', (t) async {
    await pump(
      t,
      currencies: [egp, usd],
      tips: {
        'EGP': [tip(RoiRule.coffeeMachine, egp)],
        'USD': [tip(RoiRule.bulkStaples, usd)],
      },
    );
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l.roiRuleCoffeeTitle), findsOneWidget);
    expect(find.text(l.roiRuleStaplesTitle), findsNothing);
    await t.tap(find.text('USD'));
    await t.pumpAndSettle();
    expect(find.text(l.roiRuleStaplesTitle), findsOneWidget);
    expect(find.text(l.roiRuleCoffeeTitle), findsNothing);
  });

  testWidgets('share opens through the opener', (t) async {
    RoiSuggestion? shared;
    await t.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          featureFlagProvider.overrideWith((ref, f) => true),
          entitlementStateProvider.overrideWith(() => _GoldNotifier()),
          chartsCurrenciesProvider.overrideWith((ref) async => [egp]),
          roiSuggestionsProvider.overrideWith(
            (ref, c) async => [tip(RoiRule.waterFilter, egp)],
          ),
          roiShareOpenerProvider.overrideWithValue((ctx, s) async {
            shared = s;
          }),
        ],
        child: MaterialApp(
          theme: ZaghlolTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const RoiTipsScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    await t.tap(find.text(l.roiTipsShare));
    expect(shared?.rule, RoiRule.waterFilter);
  });
}
