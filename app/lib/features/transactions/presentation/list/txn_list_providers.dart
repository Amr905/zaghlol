// T-079: state of the transactions list S-11 (FR-TXN-01, FR-TXN-06, FR-CARD-01).
//
// The screen reads only these providers; no widget touches the database.
// Search text, filters and the selection live here; the debounce (250 ms) is
// the search field's job. Money is never summed across currencies.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/db/app_database_providers.dart';
import '../../../../core/db/daos/accounts_dao.dart';
import '../../../../core/db/daos/categories_dao.dart';
import '../../../budget/application/budget_providers.dart';
import '../../../budget/application/cycle_app_wiring.dart'
    show domainEventBusProvider;
import '../../../home/application/card_filter.dart';
import '../../application/bulk_actions.dart';
import '../../application/bulk_edit.dart';
import '../../application/refund_matching.dart';
import '../../application/transfer_pairing.dart';
import '../../data/transactions_providers.dart';
import '../../domain/transaction.dart';

const int _msPerDay = 86400000;

/// Rows per page; the repository caps a page at 500.
const int txnListPageSize = 50;

enum TxnPeriod { all, thisCycle, lastCycle, thisMonth, custom }

/// The "Type" chip. Single choice, so "declined" (a status) never has to be
/// combined with a direction.
enum TxnTypeFilter { any, expense, income, transfer, refund, declined }

/// The filters the chips edit.
final class TxnListFilter {
  const TxnListFilter({
    this.period = TxnPeriod.thisCycle,
    this.customFrom,
    this.customTo,
    this.categoryIds = const {},
    this.type = TxnTypeFilter.any,
    this.sources = const {},
    this.currency,
  });

  final TxnPeriod period;
  final CivilDate? customFrom;
  final CivilDate? customTo;
  final Set<String> categoryIds;
  final TxnTypeFilter type;
  final Set<TxnSource> sources;
  final Currency? currency;

  /// Everything narrowed beyond the default period.
  bool get hasNarrowing =>
      period != TxnPeriod.all ||
      categoryIds.isNotEmpty ||
      type != TxnTypeFilter.any ||
      sources.isNotEmpty ||
      currency != null;

  TxnListFilter copyWith({
    TxnPeriod? period,
    CivilDate? customFrom,
    CivilDate? customTo,
    Set<String>? categoryIds,
    TxnTypeFilter? type,
    Set<TxnSource>? sources,
    Currency? currency,
    bool clearCurrency = false,
  }) => TxnListFilter(
    period: period ?? this.period,
    customFrom: customFrom ?? this.customFrom,
    customTo: customTo ?? this.customTo,
    categoryIds: categoryIds ?? this.categoryIds,
    type: type ?? this.type,
    sources: sources ?? this.sources,
    currency: clearCurrency ? null : (currency ?? this.currency),
  );
}

class TxnListFilterNotifier extends Notifier<TxnListFilter> {
  @override
  TxnListFilter build() => const TxnListFilter();

  void set(TxnListFilter next) => state = next;

  /// "Clear search & filters": every filter off, including the period.
  void clearAll() => state = const TxnListFilter(period: TxnPeriod.all);
}

final txnListFilterProvider =
    NotifierProvider.autoDispose<TxnListFilterNotifier, TxnListFilter>(
      TxnListFilterNotifier.new,
      name: 'txnListFilterProvider',
    );

class TxnSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String text) => state = text;
}

/// The (already debounced) search text.
final txnSearchProvider =
    NotifierProvider.autoDispose<TxnSearchNotifier, String>(
      TxnSearchNotifier.new,
      name: 'txnSearchProvider',
    );

/// What the list needs to show a row: category and card names.
final class TxnCategory {
  const TxnCategory({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.icon,
    required this.color,
  });
  final String id;
  final String nameAr;
  final String nameEn;
  final String icon;
  final String color;
}

final class TxnAccount {
  const TxnAccount({
    required this.id,
    required this.label,
    this.last4,
    required this.currencyCode,
  });
  final String id;
  final String label;
  final String? last4;
  final String currencyCode;
}

final class TxnLookups {
  const TxnLookups({required this.categories, required this.accounts});
  final List<TxnCategory> categories;
  final List<TxnAccount> accounts;

  TxnCategory? category(String? id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  TxnAccount? account(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }
}

final txnLookupsProvider = FutureProvider.autoDispose<TxnLookups>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final cats = await CategoriesDao(db).active();
  final accs = await AccountsDao(db).listLive(includeHidden: true);
  return TxnLookups(
    categories: [
      for (final c in cats)
        TxnCategory(
          id: c.id,
          nameAr: c.nameAr,
          nameEn: c.nameEn,
          icon: c.icon,
          color: c.color,
        ),
    ],
    accounts: [
      for (final a in accs)
        TxnAccount(
          id: a.id,
          label: a.label,
          last4: a.last4,
          currencyCode: a.defaultCurrency,
        ),
    ],
  );
}, name: 'txnLookupsProvider');

/// The UTC range of [f.period]; null bounds mean open.
({DateTime? from, DateTime? to}) txnPeriodRange(
  TxnListFilter f, {
  required PaydaySchedule schedule,
  required CivilDate today,
  required int offsetMin,
}) {
  DateTime ms(CivilDate d) => DateTime.fromMillisecondsSinceEpoch(
    d.epochDay * _msPerDay - offsetMin * 60000,
    isUtc: true,
  );
  switch (f.period) {
    case TxnPeriod.all:
      return (from: null, to: null);
    case TxnPeriod.thisCycle:
      final c = schedule.cycleOn(today);
      return (from: ms(c.start), to: ms(c.end.plusDays(1)));
    case TxnPeriod.lastCycle:
      final c = schedule.before(schedule.cycleOn(today));
      return (from: ms(c.start), to: ms(c.end.plusDays(1)));
    case TxnPeriod.thisMonth:
      final first = CivilDate(today.year, today.month, 1);
      final next = today.month == 12
          ? CivilDate(today.year + 1, 1, 1)
          : CivilDate(today.year, today.month + 1, 1);
      return (from: ms(first), to: ms(next));
    case TxnPeriod.custom:
      final a = f.customFrom;
      final b = f.customTo;
      return (
        from: a == null ? null : ms(a),
        to: b == null ? null : ms(b.plusDays(1)),
      );
  }
}

/// The repository filter for the chips and the global card filter.
TransactionFilter txnToRepoFilter(
  TxnListFilter f, {
  required Set<String> cardIds,
  required ({DateTime? from, DateTime? to}) range,
}) {
  final directions = switch (f.type) {
    TxnTypeFilter.expense => {TxnDirection.expense, TxnDirection.fee},
    TxnTypeFilter.income => {TxnDirection.income},
    TxnTypeFilter.transfer => {
      TxnDirection.transferOut,
      TxnDirection.transferIn,
    },
    TxnTypeFilter.refund => {TxnDirection.refund},
    _ => <TxnDirection>{},
  };
  return TransactionFilter(
    from: range.from,
    to: range.to,
    accountIds: cardIds,
    categoryIds: f.categoryIds,
    directions: directions,
    sources: f.sources,
    currencies: {?f.currency},
    statuses: f.type == TxnTypeFilter.declined ? {TxnStatus.declined} : {},
  );
}

final class TxnListState {
  const TxnListState({
    required this.items,
    required this.hasMore,
    required this.hasAnyTransaction,
  });
  final List<TransactionRecord> items;
  final bool hasMore;

  /// Whether the database holds any live transaction at all (tells "no data"
  /// from "no results").
  final bool hasAnyTransaction;
}

class TxnListController extends AsyncNotifier<TxnListState> {
  TransactionFilter _filter = const TransactionFilter();
  String? _text;
  bool _loadingMore = false;

  @override
  Future<TxnListState> build() async {
    final f = ref.watch(txnListFilterProvider);
    final search = ref.watch(txnSearchProvider).trim();
    final cards = ref.watch(cardFilterProvider);
    final schedule = await ref.watch(paydayScheduleProvider.future);
    final today = ref.watch(todayProvider);
    final repo = await ref.watch(transactionRepositoryProvider.future);
    final now = ref.read(clockProvider)().toUtc().millisecondsSinceEpoch;
    final offset = ref.read(localZoneProvider).offsetAtInstant(now);
    final sub = ref.watch(transactionsChangedProvider).listen((_) {
      ref.invalidateSelf();
    });
    ref.onDispose(() => unawaited(sub.cancel()));

    _filter = txnToRepoFilter(
      f,
      cardIds: cards,
      range: txnPeriodRange(
        f,
        schedule: schedule,
        today: today,
        offsetMin: offset,
      ),
    );
    _text = search.isEmpty ? null : search;
    final page = await repo.query(
      filter: _filter,
      text: _text,
      page: const PageRequest(limit: txnListPageSize),
    );
    final any = page.isNotEmpty || await repo.count() > 0;
    return TxnListState(
      items: page,
      hasMore: page.length == txnListPageSize,
      hasAnyTransaction: any,
    );
  }

  /// Appends the next page (scroll to the end).
  Future<void> loadMore() async {
    final cur = state.value;
    if (cur == null || !cur.hasMore || _loadingMore) return;
    _loadingMore = true;
    try {
      final repo = await ref.read(transactionRepositoryProvider.future);
      final page = await repo.query(
        filter: _filter,
        text: _text,
        page: PageRequest(limit: txnListPageSize, offset: cur.items.length),
      );
      state = AsyncData(
        TxnListState(
          items: [...cur.items, ...page],
          hasMore: page.length == txnListPageSize,
          hasAnyTransaction: cur.hasAnyTransaction,
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }

  /// Ids of every row matching the current filters ("Select all"), capped at
  /// one bulk call's limit.
  Future<Set<String>> allMatchingIds() async {
    final repo = await ref.read(transactionRepositoryProvider.future);
    final ids = <String>{};
    var offset = 0;
    while (ids.length < 1000) {
      final page = await repo.query(
        filter: _filter,
        text: _text,
        page: PageRequest(limit: 500, offset: offset),
      );
      for (final t in page) {
        if (ids.length < 1000) ids.add(t.id);
      }
      if (page.length < 500) break;
      offset += page.length;
    }
    return ids;
  }
}

final txnListProvider =
    AsyncNotifierProvider.autoDispose<TxnListController, TxnListState>(
      TxnListController.new,
      name: 'txnListProvider',
    );

/// Selection mode and the selected ids.
final class TxnSelection {
  const TxnSelection({this.active = false, this.ids = const {}});
  final bool active;
  final Set<String> ids;
}

class TxnSelectionNotifier extends Notifier<TxnSelection> {
  @override
  TxnSelection build() => const TxnSelection();

  void enter([String? firstId]) =>
      state = TxnSelection(active: true, ids: {?firstId});

  void toggle(String id) {
    final next = {...state.ids};
    if (!next.remove(id)) next.add(id);
    state = TxnSelection(active: true, ids: next);
  }

  void setAll(Set<String> ids) => state = TxnSelection(active: true, ids: ids);

  void exit() => state = const TxnSelection();
}

final txnSelectionProvider =
    NotifierProvider.autoDispose<TxnSelectionNotifier, TxnSelection>(
      TxnSelectionNotifier.new,
      name: 'txnSelectionProvider',
    );

// Use cases wired with the real payday schedule and the app event bus
// (FU-114 77-1a).

Future<PaydaySchedule> Function() _scheduleLoader(Ref ref) =>
    () => ref.read(paydayScheduleProvider.future);

final bulkEditUseCaseProvider = FutureProvider<BulkEditUseCase>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return BulkEditUseCase(
    db,
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
    loadSchedule: _scheduleLoader(ref),
    events: ref.watch(domainEventBusProvider),
  );
}, name: 'bulkEditUseCaseProvider');

final transferPairingUseCaseProvider = FutureProvider<TransferPairingUseCase>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return TransferPairingUseCase(
    db,
    loadSchedule: _scheduleLoader(ref),
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
    events: ref.watch(domainEventBusProvider),
  );
}, name: 'transferPairingUseCaseProvider');

final refundMatchingProvider = FutureProvider<RefundMatching>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return RefundMatching(
    db,
    loadSchedule: _scheduleLoader(ref),
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
    events: ref.watch(domainEventBusProvider),
  );
}, name: 'refundMatchingProvider');

final txnBulkActionsProvider = FutureProvider<TxnBulkActions>((ref) async {
  return BulkActions(
    bulk: await ref.watch(bulkEditUseCaseProvider.future),
    pairing: await ref.watch(transferPairingUseCaseProvider.future),
    refunds: await ref.watch(refundMatchingProvider.future),
  );
}, name: 'txnBulkActionsProvider');
