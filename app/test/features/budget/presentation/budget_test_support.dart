// T-101 test support: a localized, themed harness with the data providers
// overridden. Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/budget/domain/budget_progress.dart';
import 'package:zaghlol/features/budget/presentation/budget_view.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

Money egpM(int major) => Money(egp, major * 100);
Money usdM(int major) => Money(usd, major * 100);

BudgetRowView rowView(
  String id,
  String en,
  String ar,
  int spent,
  int limit, {
  Currency? currency,
}) {
  final c = currency ?? egp;
  final spec = BudgetSpec(
    id: 'b-$id',
    categoryId: id,
    limit: Money(c, limit * 100),
    thresholds: const [80, 100],
  );
  return BudgetRowView(
    categoryId: id,
    nameAr: ar,
    nameEn: en,
    progress: evaluateBudget(spec, {
      c: CycleTotals(
        currency: c,
        income: Money.zero(c),
        spend: Money(c, spent * 100),
        pendingSpend: Money.zero(c),
        byCategoryMinor: {id: spent * 100},
      ),
    }),
  );
}

CurrencyBudgetView egpView({bool budget = true}) => CurrencyBudgetView(
  currency: egp,
  spent: egpM(19800),
  limit: budget ? egpM(22000) : null,
  percent: budget ? 90 : null,
  safePerDay: budget ? egpM(314) : null,
  rows: budget
      ? [
          rowView('dining', 'Dining', 'مطاعم', 3850, 4000),
          rowView('groceries', 'Groceries', 'بقالة', 5400, 7000),
          rowView('bills', 'Bills', 'فواتير', 4400, 4200),
        ]
      : const [],
  notBudgeted: egpM(1350),
);

CurrencyBudgetView usdView() => CurrencyBudgetView(
  currency: usd,
  spent: usdM(120),
  limit: usdM(500),
  percent: 24,
  safePerDay: usdM(12),
  rows: [rowView('travel', 'Travel', 'سفر', 120, 500, currency: usd)],
  notBudgeted: usdM(0),
);

BudgetScreenData data(
  List<CurrencyBudgetView> currencies, {
  bool current = true,
  bool calendarMonth = false,
}) => BudgetScreenData(
  cycle: Cycle(start: CivilDate(2026, 10, 25), end: CivilDate(2026, 11, 24)),
  isCurrent: current,
  daysRemaining: 7,
  calendarMonth: calendarMonth,
  currencies: currencies,
  hasPrevious: true,
);

Widget harness(
  Widget child, {
  required Locale locale,
  bool dark = false,
  double scale = 1.0,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    digitsModeProvider.overrideWith(
      (ref, lang) => DigitsMode.resolve(DigitsPref.auto, lang),
    ),
    ...overrides,
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ZaghlolTheme.light,
    darkTheme: ZaghlolTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: app!,
    ),
    home: Scaffold(body: child),
  ),
);
