// T-279: harness for the per-currency view. Synthetic data only: the PO story
// (USD salary 1,000, exchanged 600 into EGP 29,700, USD 400 left).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/setting_key.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/budget/application/cycle_overview.dart';
import 'package:zaghlol/features/home/application/currency_view_providers.dart';
import 'package:zaghlol/features/home/application/home_read_model.dart';
import 'package:zaghlol/features/home/presentation/currency_view_screen.dart';
import 'package:zaghlol/features/home/presentation/home_screen.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/domain/transaction_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

HomeCurrencyFigures figures(
  Currency c, {
  required int income,
  required int spend,
  int exchangedOut = 0,
  int exchangedIn = 0,
  int? budget,
}) {
  Money m(int v) => Money(c, v * 100);
  final totals = CycleTotals(
    currency: c,
    income: m(income),
    spend: m(spend),
    pendingSpend: m(0),
    byCategoryMinor: const {},
    exchangedIn: m(exchangedIn),
    exchangedOut: m(exchangedOut),
  );
  return HomeCurrencyFigures(
    overview: CurrencyOverview(
      currency: c,
      totals: totals,
      budget: budget == null ? null : m(budget),
      safeToSpend: budget == null ? null : m(budget - spend),
      underIdealLine: null,
    ),
    safeToSpend: budget == null ? null : m(budget - spend),
    net: totals.left,
  );
}

Money usdMoney(int units) => Money(usd, units * 100);

TransactionRecord usdRow(
  String id, {
  required int minor,
  required TxnDirection dir,
  String? merchant,
  bool internal = false,
  Currency? currency,
}) => TransactionRecord(
  id: id,
  accountId: 'a1',
  source: TxnSource.manual,
  direction: dir,
  status: TxnStatus.posted,
  amount: Money(currency ?? usd, minor),
  occurredAt: DateTime.utc(2026, 11, 12, 12),
  occurredTzOffsetMin: 120,
  merchantNorm: merchant,
  categorySource: CategorySource.none,
  isUserVerified: false,
  isInternal: internal,
  createdAt: DateTime.utc(2026, 11, 12),
  updatedAt: DateTime.utc(2026, 11, 12),
);

final story = [
  usdRow(
    'salary',
    minor: 100000,
    dir: TxnDirection.income,
    merchant: 'Salary USD',
  ),
  usdRow(
    'exch',
    minor: 60000,
    dir: TxnDirection.transferOut,
    merchant: 'Exchange',
    internal: true,
  ),
  // Another currency's row must never reach the view.
  usdRow(
    'egp-row',
    minor: 2970000,
    dir: TxnDirection.transferIn,
    merchant: 'EGP leg',
    internal: true,
    currency: egp,
  ),
];

final cycle = Cycle(
  start: CivilDate(2026, 11, 1),
  end: CivilDate(2026, 11, 30),
);

HomeModel storyModel({int? usdBudget}) => HomeModel(
  cycle: cycle,
  today: CivilDate(2026, 11, 14),
  daysRemaining: 16,
  currencies: [
    figures(egp, income: 0, spend: 0, exchangedIn: 29700),
    figures(usd, income: 1000, spend: 0, exchangedOut: 600, budget: usdBudget),
  ],
  recent: const [],
  reviewCount: 0,
  scanInProgress: false,
  cardFilter: const {},
);

class FakeTxns implements TransactionRepository {
  FakeTxns(this.rows);
  final List<TransactionRecord> rows;

  @override
  Future<List<TransactionRecord>> query({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
    PageRequest page = const PageRequest(),
  }) async => [
    for (final r in rows)
      if (filter.currencies.isEmpty ||
          filter.currencies.contains(r.amount.currency))
        r,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In-memory settings: only the offers key is supported.
class FakeSettings implements SettingsRepository {
  FakeSettings(this.store);
  final StreamController<Set<String>> store;
  Set<String> value = {};

  @override
  Future<T> get<T>(SettingKey<T> key) async => value as T;

  @override
  Future<void> set<T>(SettingKey<T> key, T v) async {
    expect(key.name, Settings.budgetOffersHandled.name);
    value = v as Set<String>;
    store.add(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ViewEnv {
  ViewEnv({Set<String> handled = const {}}) {
    settings = FakeSettings(controller)..value = {...handled};
  }
  final controller = StreamController<Set<String>>.broadcast();
  late final FakeSettings settings;
}

Widget viewApp({
  required String iso,
  required ViewEnv env,
  Locale locale = const Locale('ar', 'EG'),
  bool dark = false,
  double textScale = 1.0,
  HomeModel? model,
  List<TransactionRecord>? rows,
  Future<HomeModel>? future,
  bool fail = false,
  ValueChanged<Currency>? onSeeAll,
  ValueChanged<Currency>? onEditor,
  List<Override> extra = const [],
}) {
  final m = model ?? storyModel();
  return ProviderScope(
    overrides: [
      hideAmountsProvider.overrideWithValue(false),
      homePaydaySetProvider.overrideWith((ref) => true),
      homeModelProvider.overrideWith((ref) async {
        if (fail) throw StateError('synthetic');
        return future ?? m;
      }),
      primaryCurrencyProvider.overrideWith((ref) => Stream.value(egp)),
      budgetOffersHandledProvider.overrideWith((ref) async* {
        yield env.settings.value;
        yield* env.controller.stream;
      }),
      settingsRepositoryProvider.overrideWith((ref) async => env.settings),
      transactionRepositoryProvider.overrideWith(
        (ref) async => FakeTxns(rows ?? story),
      ),
      ...extra,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ZaghlolTheme.light,
      darkTheme: ZaghlolTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: CurrencyViewScreen(
        iso: iso,
        onSeeAll: onSeeAll,
        onOpenBudgetEditor: onEditor,
      ),
    ),
  );
}

Future<void> pumpView(
  WidgetTester tester,
  Widget app, {
  bool settle = true,
  double height = 844,
}) async {
  await initDateFormatting();
  await tester.binding.setSurfaceSize(Size(390, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app);
  if (settle) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}
