// T-280: the Home ≈ line and its sheet, ar and en. Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/home/application/home_approx_providers.dart';
import 'package:zaghlol/features/home/presentation/home_approx_line.dart';
import 'package:zaghlol/features/wealth/domain/income_approx.dart';
import 'package:zaghlol/features/wealth/domain/price_feed.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../support/hide_amounts_support.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

final int now = DateTime.utc(2026, 11, 26, 12).millisecondsSinceEpoch;

IncomeApproxLine story({bool stale = false}) {
  final at = stale ? now - 30 * 3600000 : now - 3600000;
  return buildIncomeApprox(
    target: egp,
    inputs: [
      IncomeApproxInput(
        moneyIn: Money(egp, 2970000),
        exchangedOut: Money.zero(egp),
      ),
      IncomeApproxInput(
        moneyIn: Money(usd, 100000),
        exchangedOut: Money(usd, 60000),
        bankRateE9: 49500000000,
      ),
    ],
    rates: FxTable([
      FxQuote(base: usd, quote: egp, rateE9: 49600000000, asOfMs: at),
    ], reportedStale: false),
    nowMs: now,
  ) as IncomeApproxLine;
}

Widget app(Locale locale, Widget child, [List<Override> extra = const []]) =>
    ProviderScope(
      overrides: [...amountsShown(), ...extra],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ZaghlolTheme.light,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  setUpAll(initDateFormatting);

  for (final lang in ['ar', 'en']) {
    group(lang, () {
      testWidgets('line shows the ≈ amount and the rate note', (t) async {
        final h = t.ensureSemantics();
        await t.pumpWidget(
          app(Locale(lang), HomeApproxLineView(line: story())),
        );
        await t.pumpAndSettle();
        final texts = [
          for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? '',
        ];
        final main = texts.firstWhere((s) => s.contains('≈'));
        expect(main, contains(lang == 'ar' ? '٤٩٬٥٤٠' : '49,540'));
        expect(
          texts.any(
            (s) => lang == 'ar'
                ? s.startsWith('سعر البنك + سعر')
                : s.startsWith('Bank rate +'),
          ),
          isTrue,
        );
        // Screen readers hear "approximate" first.
        final label = t.getSemantics(find.byType(HomeApproxLineView)).label;
        expect(label, startsWith(lang == 'ar' ? 'تقريبي' : 'Approximate'));
        h.dispose();
      });

      testWidgets('a stale rate reads "old rate"', (t) async {
        await t.pumpWidget(
          app(Locale(lang), HomeApproxLineView(line: story(stale: true))),
        );
        await t.pumpAndSettle();
        expect(
          find.text(lang == 'ar' ? 'سعر قديم' : 'Old rate'),
          findsOneWidget,
        );
      });

      testWidgets('tap opens the sheet with each currency, rate and source', (
        t,
      ) async {
        await t.pumpWidget(
          app(Locale(lang), HomeApproxLineView(line: story())),
        );
        await t.pumpAndSettle();
        await t.tap(find.byType(HomeApproxLineView));
        await t.pumpAndSettle();
        expect(
          find.text(
            lang == 'ar' ? 'الحسبة دي تقريبية' : 'This total is approximate',
          ),
          findsOneWidget,
        );
        final all = [
          for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? '',
        ].join('\n');
        expect(all, contains('USD'));
        expect(all, contains(lang == 'ar' ? '٤٩٫٦٠' : '49.60')); // daily rate
        expect(all, contains(lang == 'ar' ? '٤٩٫٥٠' : '49.50')); // bank rate
        expect(
          all,
          contains(lang == 'ar' ? '١٩٬٨٤٠' : '19,840'),
        ); // 400 x 49.60
      });
    });
  }

  List<Override> slot({
    required bool enabled,
    required bool notice,
    IncomeApproxLine? line,
  }) => [
    homeApproxAutoOnProvider.overrideWith((ref) async {}),
    approxViewEnabledProvider.overrideWith((ref) => Stream.value(enabled)),
    approxFirstForeignNoticeProvider.overrideWith(
      (ref) => Stream.value(notice),
    ),
    homeApproxProvider.overrideWith((ref) async => line),
  ];

  testWidgets('setting off: nothing is shown', (t) async {
    await t.pumpWidget(
      app(
        const Locale('en'),
        const HomeApproxLine(),
        slot(enabled: false, notice: true, line: story()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('≈'), findsNothing);
  });

  testWidgets('missing rate (no line): nothing is shown', (t) async {
    await t.pumpWidget(
      app(
        const Locale('en'),
        const HomeApproxLine(),
        slot(enabled: true, notice: false),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(HomeApproxLineView), findsNothing);
    expect(find.textContaining('≈'), findsNothing);
  });

  testWidgets('on with a figure: the line always carries ≈', (t) async {
    await t.pumpWidget(
      app(
        const Locale('ar'),
        const HomeApproxLine(),
        slot(enabled: true, notice: false, line: story()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('≈'), findsWidgets);
  });

  testWidgets('first-foreign notice shows its line and the off link', (
    t,
  ) async {
    await t.pumpWidget(
      app(
        const Locale('ar'),
        const HomeApproxLine(),
        slot(enabled: true, notice: true, line: story()),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('عندك فلوس بعملة تانية'), findsOneWidget);
    expect(find.text('اقفلها'), findsOneWidget);
  });
}
