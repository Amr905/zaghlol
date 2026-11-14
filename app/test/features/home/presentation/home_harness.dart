import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/budget/application/cycle_overview.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/home/application/card_filter.dart';
import 'package:zaghlol/features/home/application/home_read_model.dart';
import 'package:zaghlol/features/home/presentation/home_screen.dart';
import 'package:zaghlol/features/home/presentation/home_widgets.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

Money egpM(int major) => Money(egp, major * 100);

HomeCurrencyFigures figs(
  Currency c, {
  int income = 32000,
  int spend = 19800,
  int? safe = 314,
}) {
  Money m(int v) => Money(c, v * 100);
  return HomeCurrencyFigures(
    overview: CurrencyOverview(
      currency: c,
      totals: CycleTotals(
        currency: c,
        income: m(income),
        spend: m(spend),
        pendingSpend: m(0),
        byCategoryMinor: const {},
      ),
      budget: safe == null ? null : m(25000),
      safeToSpend: safe == null ? null : m(safe),
      underIdealLine: null,
    ),
    safeToSpend: safe == null ? null : m(safe),
    net: m(income - spend),
  );
}

TransactionRecord rec(
  String id, {
  String? merchant,
  int amount = 450,
  TxnDirection dir = TxnDirection.expense,
  bool internal = false,
}) => TransactionRecord(
  id: id,
  accountId: 'a1',
  source: TxnSource.sms,
  direction: dir,
  status: TxnStatus.posted,
  amount: egpM(amount),
  occurredAt: DateTime.utc(2026, 11, 10, 12, 14),
  occurredTzOffsetMin: 120,
  merchantNorm: merchant,
  categorySource: CategorySource.none,
  isUserVerified: false,
  isInternal: internal,
  createdAt: DateTime.utc(2026, 11, 10),
  updatedAt: DateTime.utc(2026, 11, 10),
);

HomeModel model({
  List<HomeCurrencyFigures>? currencies,
  List<HomeFeedItem>? recent,
  int review = 0,
  bool scanning = false,
  Set<String> filter = const {},
}) => HomeModel(
  cycle: Cycle(start: CivilDate(2026, 10, 25), end: CivilDate(2026, 11, 24)),
  today: CivilDate(2026, 11, 10),
  daysRemaining: 14,
  currencies: currencies ?? [figs(egp)],
  recent:
      recent ??
      [
        HomeFeedItem(
          record: rec('t1', merchant: 'Carrefour Maadi'),
          excludedFromTotals: false,
        ),
        HomeFeedItem(
          record: rec('t2', merchant: 'Talabat', amount: 285),
          excludedFromTotals: false,
        ),
        HomeFeedItem(
          record: rec('t3', amount: 1000, dir: TxnDirection.transferOut),
          excludedFromTotals: true,
        ),
      ],
  reviewCount: review,
  scanInProgress: scanning,
  cardFilter: filter,
);

Account account(String id, String label, String last4) => Account(
  id: id,
  kind: AccountKind.values.first,
  label: label,
  defaultCurrency: egp,
  isHidden: false,
  isDefaultCash: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  last4: last4,
);

/// [future] null means the value in [model].
Widget homeApp({
  required Locale locale,
  required TargetPlatform platform,
  Future<HomeModel>? future,
  HomeModel? value,
  bool dark = false,
  double textScale = 1.0,
  bool smsWaiting = false,
  Set<String> filter = const {},
  List<Account> accounts = const [],
  HomeActions? actions,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      homeModelProvider.overrideWith((ref) => future ?? Future.value(value)),
      homeAccountsProvider.overrideWith((ref) async => accounts),
      homePaydaySetProvider.overrideWith((ref) => true),
      captureSmsEnabledProvider.overrideWith((ref) => Stream.value(smsWaiting)),
      captureSupportedProvider.overrideWith((ref) => smsWaiting),
      ...extraOverrides,
      if (filter.isNotEmpty)
        cardFilterProvider.overrideWith(() => _Filter(filter)),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ZaghlolTheme.light.copyWith(platform: platform),
      darkTheme: ZaghlolTheme.dark.copyWith(platform: platform),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(body: HomeScreen(actions: actions)),
    ),
  );
}

class _Filter extends CardFilterNotifier {
  _Filter(this.initial);
  final Set<String> initial;
  @override
  Set<String> build() => initial;
}

Future<void> pumpHome(
  WidgetTester tester, {
  required Locale locale,
  required TargetPlatform platform,
  Future<HomeModel>? future,
  HomeModel? value,
  bool dark = false,
  double textScale = 1.0,
  bool smsWaiting = false,
  Set<String> filter = const {},
  List<Account> accounts = const [],
  bool settle = true,
  HomeActions? actions,
  List<Override> extraOverrides = const [],
}) async {
  await initDateFormatting();
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    homeApp(
      locale: locale,
      platform: platform,
      future: future,
      value: value,
      dark: dark,
      textScale: textScale,
      smsWaiting: smsWaiting,
      filter: filter,
      accounts: accounts,
      actions: actions,
      extraOverrides: extraOverrides,
    ),
  );
  if (settle) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Completer<HomeModel> pending() => Completer<HomeModel>();
