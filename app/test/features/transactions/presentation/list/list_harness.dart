// T-079: fakes and a pump helper for the transactions list widget tests.
// All data synthetic.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_ports.dart'
    show LocalZone;
import 'package:zaghlol/features/transactions/application/bulk_actions.dart';
import 'package:zaghlol/features/transactions/application/bulk_edit.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/domain/transaction_repository.dart';
import 'package:zaghlol/features/transactions/presentation/list/transactions_list_screen.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_list_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

/// 2026-11-13 12:00 UTC; the zone is UTC+2 (offset 120).
final DateTime now = DateTime.utc(2026, 11, 13, 10);
const int offset = 120;

TransactionRecord txnRec(
  String id, {
  String merchant = 'Carrefour',
  int minor = 45000,
  Currency? currency,
  TxnDirection direction = TxnDirection.expense,
  String? categoryId = 'food',
  int daysAgo = 0,
  bool internal = false,
  TxnStatus status = TxnStatus.posted,
  String account = 'acc1',
}) => TransactionRecord(
  id: id,
  accountId: account,
  source: TxnSource.sms,
  direction: direction,
  status: status,
  amount: Money(currency ?? egp, minor),
  occurredAt: now.subtract(Duration(days: daysAgo)),
  occurredTzOffsetMin: offset,
  merchantNorm: merchant,
  categoryId: categoryId,
  categorySource: CategorySource.catalog,
  isUserVerified: false,
  isInternal: internal,
  createdAt: now,
  updatedAt: now,
);

class FakeRepo implements TransactionRepository {
  FakeRepo(this.rows);
  List<TransactionRecord> rows;
  Completer<void>? gate;
  Object? failWith;
  int queries = 0;
  final List<String?> texts = [];

  @override
  Future<List<TransactionRecord>> query({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
    PageRequest page = const PageRequest(),
  }) async {
    queries++;
    texts.add(text);
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
    final hits = rows.where((t) {
      if (text != null &&
          !(t.merchantNorm ?? '').toLowerCase().contains(text.toLowerCase())) {
        return false;
      }
      if (filter.categoryIds.isNotEmpty &&
          !filter.categoryIds.contains(t.categoryId)) {
        return false;
      }
      if (filter.directions.isNotEmpty &&
          !filter.directions.contains(t.direction)) {
        return false;
      }
      if (filter.currencies.isNotEmpty &&
          !filter.currencies.contains(t.amount.currency)) {
        return false;
      }
      return true;
    }).toList();
    return hits.skip(page.offset).take(page.limit).toList();
  }

  @override
  Future<int> count({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
  }) async => rows.length;

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName}');
}

class FakeActions implements TxnBulkActions {
  FakeActions(this.repo);
  final FakeRepo repo;
  final List<String> calls = [];
  Map<String, String?> _before = {};
  List<TransactionRecord> _deleted = [];

  BulkEditResult _res(int n) => BulkEditResult(
    batchId: 'batch1',
    changed: n,
    rulesCreated: 0,
    event: TransactionsChanged(accountIds: const {}, cycleKeys: const {}),
  );

  @override
  Future<BulkEditResult> setCategory(
    Set<String> ids,
    String categoryId, {
    bool alwaysUseForMerchants = false,
  }) async {
    calls.add('category:${ids.length}:$categoryId:$alwaysUseForMerchants');
    _before = {for (final t in repo.rows) t.id: t.categoryId};
    repo.rows = [
      for (final t in repo.rows)
        if (ids.contains(t.id)) _with(t, categoryId) else t,
    ];
    return _res(ids.length);
  }

  TransactionRecord _with(TransactionRecord t, String? cat) =>
      TransactionRecord(
        id: t.id,
        accountId: t.accountId,
        source: t.source,
        direction: t.direction,
        status: t.status,
        amount: t.amount,
        occurredAt: t.occurredAt,
        occurredTzOffsetMin: t.occurredTzOffsetMin,
        merchantNorm: t.merchantNorm,
        categoryId: cat,
        categorySource: t.categorySource,
        isUserVerified: t.isUserVerified,
        isInternal: t.isInternal,
        createdAt: t.createdAt,
        updatedAt: t.updatedAt,
      );

  @override
  Future<BulkEditResult> setAccount(Set<String> ids, String accountId) async {
    calls.add('account:${ids.length}:$accountId');
    return _res(ids.length);
  }

  @override
  Future<BulkEditResult> delete(Set<String> ids) async {
    calls.add('delete:${ids.length}');
    _deleted = repo.rows.where((t) => ids.contains(t.id)).toList();
    repo.rows = repo.rows.where((t) => !ids.contains(t.id)).toList();
    return _res(ids.length);
  }

  @override
  Future<UndoResult> undo(String batchId) async {
    calls.add('undo:$batchId');
    if (_deleted.isNotEmpty) {
      repo.rows = [...repo.rows, ..._deleted];
      _deleted = [];
    } else {
      repo.rows = [for (final t in repo.rows) _with(t, _before[t.id])];
    }
    return const UndoResult(restored: 0, skipped: 0, event: null);
  }
}

class FixedToday extends TodayNotifier {
  @override
  CivilDate build() => CivilDate(2026, 11, 13);
}

class FixedZone implements LocalZone {
  const FixedZone();
  @override
  int offsetAtInstant(int utcMs) => offset;
  @override
  int offsetAtWallClock(DateTime wallClock) => offset;
}

const lookups = TxnLookups(
  categories: [
    TxnCategory(
      id: 'food',
      nameAr: 'أكل',
      nameEn: 'Food',
      icon: '🍔',
      color: '#0F7A55',
    ),
    TxnCategory(
      id: 'bills',
      nameAr: 'فواتير',
      nameEn: 'Bills',
      icon: '🧾',
      color: '#4D695C',
    ),
  ],
  accounts: [
    TxnAccount(
      id: 'acc1',
      label: 'NBE Visa',
      last4: '4567',
      currencyCode: 'EGP',
    ),
    TxnAccount(id: 'acc2', label: 'Wallet', currencyCode: 'USD'),
  ],
);

class Harness {
  Harness(this.repo) : actions = FakeActions(repo);
  final FakeRepo repo;
  final FakeActions actions;
}

Widget listApp(
  Harness h, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  bool dark = false,
}) => ProviderScope(
  overrides: [
    transactionRepositoryProvider.overrideWith((ref) async => h.repo),
    txnBulkActionsProvider.overrideWith((ref) async => h.actions),
    txnLookupsProvider.overrideWith((ref) async => lookups),
    paydayScheduleProvider.overrideWith(
      (ref) async => PaydaySchedule.single(1),
    ),
    todayProvider.overrideWith(FixedToday.new),
    clockProvider.overrideWithValue(() => now),
    localZoneProvider.overrideWithValue(const FixedZone()),
    transactionsChangedProvider.overrideWithValue(const Stream.empty()),
    digitsModeProvider.overrideWith(
      (ref, lang) => DigitsMode.resolve(DigitsPref.auto, lang),
    ),
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
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: TransactionsListScreen(onAddExpense: () {}),
  ),
);

Future<void> pumpList(
  WidgetTester tester,
  Harness h, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  bool dark = false,
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    listApp(h, locale: locale, textScale: textScale, dark: dark),
  );
  await tester.pumpAndSettle();
}
