import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_models.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_providers.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_screen.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

Money egp(int minor) => Money.tryMinor(Currency.of('EGP'), minor)!;

/// Records calls; synthetic data only.
class FakeActions implements ReviewActions {
  final List<String> calls = [];
  Object? failWith;

  Future<void> _rec(String c) async {
    if (failWith != null) throw failWith!;
    calls.add(c);
  }

  @override
  Future<void> categorize(CategoryCardModel card, String categoryId) =>
      _rec('categorize:${card.itemId}:$categoryId');
  @override
  Future<void> dismiss(String itemId) => _rec('dismiss:$itemId');
  @override
  Future<void> accept(String itemId) => _rec('accept:$itemId');
  @override
  Future<void> confirmSubscription(SubscriptionCardModel card) =>
      _rec('subConfirm:${card.recurringItemId}');
  @override
  Future<void> dismissSubscription(SubscriptionCardModel card) =>
      _rec('subDismiss:${card.recurringItemId}');
  @override
  Future<void> resolveTransfer(
    TransferCardModel card,
    ReviewTransferOption? option,
  ) => _rec('transfer:${card.itemId}:${option?.txnId}');
  @override
  Future<void> requestBank(
    String itemId, {
    required String name,
    required String country,
    required String channel,
  }) => _rec('bank:$itemId:$name:$country:$channel');
}

final sampleCards = <ReviewCardModel>[
  CategoryCardModel(
    itemId: 'r1',
    txnId: 't1',
    amount: egp(35000),
    isIncome: false,
    counterparty: 'sample.user@instapay',
  ),
  MessageCardModel(
    itemId: 'r2',
    sender: 'XYZ BANK',
    isNewSender: true,
    txnId: 't2',
    amount: Money.tryMinor(Currency.of('USD'), 22000),
    merchant: 'AMAZON',
  ),
  MessageCardModel(itemId: 'r3', sender: 'ABC BANK', isNewSender: false),
  TransferCardModel(
    itemId: 'r4',
    txnId: 't4',
    amount: egp(100000),
    accountLabel: 'CIB •1234',
    isIncomeLeg: true,
    options: [
      ReviewTransferOption(
        txnId: 'o1',
        amount: egp(100000),
        accountLabel: 'NBE',
        occurredAt: DateTime.utc(2026, 1, 1, 12),
      ),
      ReviewTransferOption(
        txnId: 'o2',
        amount: egp(100000),
        accountLabel: 'QNB',
        occurredAt: DateTime.utc(2026, 1, 1, 12, 2),
      ),
    ],
  ),
  SubscriptionCardModel(
    itemId: 'r5',
    recurringItemId: 'rec1',
    name: 'Streamly',
    amount: egp(9900),
  ),
  const SuggestionCardModel(
    itemId: 'r6',
    kind: 'reimbursement_suggestion',
    ambiguousRefund: true,
  ),
];

const sampleCategories = [
  ReviewCategory(id: 'c1', nameAr: 'إيجار', nameEn: 'Rent'),
  ReviewCategory(id: 'c2', nameAr: 'أكل', nameEn: 'Food'),
];

/// The screen in a themed, localised app. [queue] null means loading.
Widget reviewApp({
  required FakeActions actions,
  List<ReviewCardModel>? queue,
  Object? error,
  Locale locale = const Locale('en'),
  bool dark = false,
  double scale = 1.0,
}) {
  return ProviderScope(
    overrides: [
      reviewActionsProvider.overrideWithValue(actions),
      reviewCategoriesProvider.overrideWith((ref) async => sampleCategories),
      reviewQueueProvider.overrideWith((ref) async {
        if (error != null) throw error;
        if (queue == null) return Completer<List<ReviewCardModel>>().future;
        return queue;
      }),
      digitsModeProvider.overrideWith(
        (ref, lang) =>
            lang == 'ar' ? DigitsMode.arabicIndic : DigitsMode.western,
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ZaghlolTheme.light,
      darkTheme: ZaghlolTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: app!,
      ),
      home: const ReviewScreen(),
    ),
  );
}

Future<void> pumpReview(
  WidgetTester tester,
  Widget app, {
  Size size = const Size(390, 4000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump();
}
