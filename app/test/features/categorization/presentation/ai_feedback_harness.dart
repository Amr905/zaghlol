// T-361: pump helper and fake service for the AI chip / feedback widgets.
// All data synthetic.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/categorization/presentation/ai_feedback_controls.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_list_providers.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_row.dart';

import '../../transactions/presentation/list/list_harness.dart' show txnRec;

const cats = [
  TxnCategory(
    id: 'food',
    nameAr: 'أكل',
    nameEn: 'Food',
    icon: 'restaurant',
    color: '#0F7A55',
  ),
  TxnCategory(
    id: 'transport',
    nameAr: 'مواصلات',
    nameEn: 'Transport',
    icon: 'directions_car',
    color: '#0F7A55',
  ),
  TxnCategory(
    id: 'custom1',
    nameAr: 'قهوتي',
    nameEn: 'My coffee',
    icon: 'coffee',
    color: '#0F7A55',
  ),
];
const lookups = TxnLookups(categories: cats, accounts: []);

TransactionRecord aiRec({
  CategorySource source = CategorySource.ai,
  String? merchant = 'Carrefour',
}) => txnRec('t1', merchant: merchant ?? '').copyWithSource(source);

extension on TransactionRecord {
  TransactionRecord copyWithSource(CategorySource s) => TransactionRecord(
    id: id,
    accountId: accountId,
    source: source,
    direction: direction,
    status: status,
    amount: amount,
    occurredAt: occurredAt,
    occurredTzOffsetMin: occurredTzOffsetMin,
    merchantNorm: merchantNorm,
    categoryId: categoryId,
    categorySource: s,
    isUserVerified: isUserVerified,
    isInternal: isInternal,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

final class FakeActions implements AiFeedbackActions {
  final calls = <String>[];

  @override
  Future<AiFeedbackResult> confirm(String m) async {
    calls.add('confirm:$m');
    return const AiFeedbackResult(categoryId: 'food', token: 'r1');
  }

  @override
  Future<AiFeedbackResult> correct(String m, String c) async {
    calls.add('correct:$m:$c');
    return AiFeedbackResult(categoryId: c, token: 'r2');
  }

  @override
  Future<void> undo(Object token) async => calls.add('undo:$token');
}

Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  FakeActions? actions,
  Locale locale = const Locale('en'),
  bool dark = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (actions != null)
          aiFeedbackActionsProvider.overrideWith((ref) async => actions),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: dark ? ZaghlolTheme.dark : ZaghlolTheme.light,
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: Scaffold(
          body: Center(child: SizedBox(width: 380, child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget row(TransactionRecord t) => TxnRow(
  txn: t,
  lookups: lookups,
  fmt: const TxnFmt('en', DigitsMode.western, hidden: false),
  selecting: false,
  selected: false,
  onTap: () {},
  onLongPress: () {},
);

Widget bar([String lang = 'en']) => AiSuggestionBar(
  merchantNorm: 'Carrefour',
  merchantLabel: 'Carrefour',
  categoryId: 'food',
  lookups: lookups,
  lang: lang,
);
