// T-079: S-11 Transactions. Search-as-you-type (250 ms debounce, FTS in the
// repository), filter chips and sheets, day headers with per-currency totals,
// selection mode with bulk category / card / delete, Undo snackbar.
//
// Reads state through the providers in txn_list_providers.dart only. Nothing
// here logs; failures show a generic message (no row data).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/date_format.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_components.dart';
import '../../../budget/application/budget_providers.dart';
import '../../../home/application/card_filter.dart';
import '../../application/bulk_actions.dart';
import '../../application/bulk_edit.dart';
import '../../domain/transaction.dart';
import 'txn_filter_sheets.dart';
import 'txn_list_providers.dart';
import 'txn_row.dart';

/// How long the search field waits after the last keystroke.
const Duration txnSearchDebounce = Duration(milliseconds: 250);

class TransactionsListScreen extends ConsumerStatefulWidget {
  const TransactionsListScreen({
    super.key,
    this.onOpenTransaction,
    this.onAddExpense,
  });

  /// Row tap (to S-12). Null until the detail screen is wired.
  final ValueChanged<String>? onOpenTransaction;

  /// Empty-state button; defaults to opening the Add sheet.
  final VoidCallback? onAddExpense;

  @override
  ConsumerState<TransactionsListScreen> createState() => _State();
}

class _State extends ConsumerState<TransactionsListScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) {
        ref.read(txnListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(txnSearchDebounce, () {
      if (mounted) ref.read(txnSearchProvider.notifier).set(text);
    });
    setState(() {});
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    ref.read(txnSearchProvider.notifier).set('');
    setState(() {});
  }

  void _clearAll() {
    _clearSearch();
    ref.read(txnListFilterProvider.notifier).clearAll();
    ref.read(cardFilterProvider.notifier).clear();
  }

  TxnFmt _fmt(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return TxnFmt(lang, ref.watch(digitsModeProvider(lang)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fmt = _fmt(context);
    final sel = ref.watch(txnSelectionProvider);
    final list = ref.watch(txnListProvider);
    return PopScope(
      canPop: !sel.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(txnSelectionProvider.notifier).exit();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: sel.active
              ? IconButton(
                  tooltip: l.commonActionCancel,
                  icon: const Icon(Icons.close),
                  onPressed: ref.read(txnSelectionProvider.notifier).exit,
                )
              : null,
          title: Text(
            sel.active
                ? l.transactionsListSelectedTitle(fmt.count(sel.ids.length))
                : l.transactionsListTitle,
          ),
          actions: [
            if (sel.active)
              TextButton(
                onPressed: _selectAll,
                child: Text(l.commonActionSelectAll),
              )
            else if (list.value?.items.isNotEmpty ?? false)
              TextButton(
                onPressed: ref.read(txnSelectionProvider.notifier).enter,
                child: Text(l.commonActionSelect),
              ),
          ],
        ),
        body: Column(
          children: [
            _SearchField(
              controller: _search,
              onChanged: _onSearchChanged,
              onClear: _clearSearch,
            ),
            _FilterBar(fmt: fmt),
            Expanded(child: _body(context, list, fmt, sel)),
          ],
        ),
        bottomNavigationBar: sel.active
            ? _ActionBar(
                enabled: sel.ids.isNotEmpty,
                onCategory: () => _bulkCategory(fmt),
                onAccount: () => _bulkAccount(fmt),
                onDelete: () => _bulkDelete(fmt),
                onCancel: ref.read(txnSelectionProvider.notifier).exit,
              )
            : null,
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AsyncValue<TxnListState> list,
    TxnFmt fmt,
    TxnSelection sel,
  ) {
    final l = AppLocalizations.of(context);
    final lookups = ref.watch(txnLookupsProvider).value;
    return list.when(
      loading: () => const _Skeleton(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(ZSpacing.lg),
        child: ZBanner(
          message: l.commonErrorLoadFailed,
          tone: ZBannerTone.error,
          actionLabel: l.commonActionTryAgain,
          onAction: () => ref.invalidate(txnListProvider),
        ),
      ),
      data: (state) {
        if (state.items.isEmpty) return _emptyState(context, state);
        if (lookups == null) return const _Skeleton();
        final today = ref.watch(todayProvider);
        return _groupedList(context, state, lookups, fmt, sel, today);
      },
    );
  }

  Widget _emptyState(BuildContext context, TxnListState state) {
    final l = AppLocalizations.of(context);
    final query = ref.watch(txnSearchProvider).trim();
    if (!state.hasAnyTransaction) {
      return _Message(
        title: l.transactionsListEmptyTitle,
        body: l.transactionsListEmptyBody,
        actionLabel: l.transactionsListEmptyAdd,
        onAction:
            widget.onAddExpense ??
            () => GoRouter.of(context).push(AppRoutes.add),
      );
    }
    return _Message(
      title: query.isEmpty
          ? l.transactionsListNoResultsFilters
          : l.transactionsListNoResults(query),
      actionLabel: l.transactionsListClearAll,
      onAction: _clearAll,
    );
  }

  Widget _groupedList(
    BuildContext context,
    TxnListState state,
    TxnLookups lookups,
    TxnFmt fmt,
    TxnSelection sel,
    CivilDate today,
  ) {
    final l = AppLocalizations.of(context);
    final entries = <Object>[];
    CivilDate? day;
    var dayRows = <TransactionRecord>[];
    void flush() {
      if (day == null) return;
      entries.insert(entries.length - dayRows.length, (day, dayRows));
    }

    for (final t in state.items) {
      final d = CivilDate.fromLocalMs(
        t.occurredAt.millisecondsSinceEpoch,
        t.occurredTzOffsetMin,
      );
      if (d != day) {
        flush();
        day = d;
        dayRows = [];
      }
      dayRows.add(t);
      entries.add(t);
    }
    flush();

    String dayLabel(CivilDate d) {
      if (d == today) return l.commonDateToday;
      if (d == today.plusDays(-1)) return l.commonDateYesterday;
      return ZDateFormat.date(
        DateTime(d.year, d.month, d.day),
        fmt.lang,
        fmt.digits,
      );
    }

    final notifier = ref.read(txnSelectionProvider.notifier);
    return ListView.builder(
      controller: _scroll,
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        if (e is (CivilDate, List<TransactionRecord>)) {
          return TxnDayHeader(
            label: dayLabel(e.$1),
            totals: dayTotals(e.$2),
            fmt: fmt,
          );
        }
        final t = e as TransactionRecord;
        return TxnRow(
          key: ValueKey(t.id),
          txn: t,
          lookups: lookups,
          fmt: fmt,
          selecting: sel.active,
          selected: sel.ids.contains(t.id),
          onTap: () => sel.active
              ? notifier.toggle(t.id)
              : widget.onOpenTransaction?.call(t.id),
          onLongPress: () =>
              sel.active ? notifier.toggle(t.id) : notifier.enter(t.id),
        );
      },
    );
  }

  Future<void> _selectAll() async {
    final ids = await ref.read(txnListProvider.notifier).allMatchingIds();
    ref.read(txnSelectionProvider.notifier).setAll(ids);
  }

  // Bulk actions -----------------------------------------------------------

  Future<void> _bulkCategory(TxnFmt fmt) async {
    final lookups = await ref.read(txnLookupsProvider.future);
    if (!mounted) return;
    final pick = await showBulkCategorySheet(
      context,
      categories: lookups.categories,
      lang: fmt.lang,
    );
    if (pick == null) return;
    await _runBulk(
      fmt,
      (a, ids) =>
          a.setCategory(ids, pick.id, alwaysUseForMerchants: pick.always),
      deleted: false,
    );
  }

  Future<void> _bulkAccount(TxnFmt fmt) async {
    final lookups = await ref.read(txnLookupsProvider.future);
    if (!mounted) return;
    final id = await showBulkAccountSheet(
      context,
      accounts: lookups.accounts,
      fmt: fmt,
    );
    if (id == null) return;
    await _runBulk(fmt, (a, ids) => a.setAccount(ids, id), deleted: false);
  }

  Future<void> _bulkDelete(TxnFmt fmt) async {
    final n = ref.read(txnSelectionProvider).ids.length;
    final ok = await confirmBulkDelete(context, count: n, n: fmt.count(n));
    if (!ok) return;
    await _runBulk(fmt, (a, ids) => a.delete(ids), deleted: true);
  }

  Future<void> _runBulk(
    TxnFmt fmt,
    Future<BulkEditResult> Function(TxnBulkActions, Set<String>) op, {
    required bool deleted,
  }) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ids = {...ref.read(txnSelectionProvider).ids};
    if (ids.isEmpty) return;
    try {
      final actions = await ref.read(txnBulkActionsProvider.future);
      final result = await op(actions, ids);
      ref.read(txnSelectionProvider.notifier).exit();
      ref.invalidate(txnListProvider);
      final n = fmt.count(result.changed);
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text(
              deleted
                  ? l.transactionsListBulkDeleted(result.changed, n)
                  : l.transactionsListBulkChanged(result.changed, n),
            ),
            action: SnackBarAction(
              label: l.commonActionUndo,
              onPressed: () async {
                try {
                  await actions.undo(result.batchId);
                } on SafeException {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l.commonErrorSaveFailed)),
                  );
                }
                ref.invalidate(txnListProvider);
              },
            ),
          ),
        );
    } on SafeException {
      messenger.showSnackBar(SnackBar(content: Text(l.commonErrorSaveFailed)));
    }
  }
}

/// Per-currency net of the counted rows of one day; zero totals are dropped.
List<Money> dayTotals(List<TransactionRecord> rows) {
  final byCurrency = <String, Money>{};
  for (final t in rows.where(countsInTotal)) {
    final m = signedAmount(t);
    final cur = byCurrency[m.currency.code];
    byCurrency[m.currency.code] = cur == null ? m : cur + m;
  }
  return [
    for (final m in byCurrency.values)
      if (!m.isZero) m,
  ];
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ZSpacing.lg,
        ZSpacing.sm,
        ZSpacing.lg,
        ZSpacing.sm,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: l.transactionsListSearchHint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: l.commonActionClearFilter,
                  icon: const Icon(Icons.close),
                  onPressed: onClear,
                ),
        ),
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.fmt});
  final TxnFmt fmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final f = ref.watch(txnListFilterProvider);
    final notifier = ref.read(txnListFilterProvider.notifier);
    final cards = ref.watch(cardFilterProvider);
    final lookups = ref.watch(txnLookupsProvider).value;
    final today = ref.watch(todayProvider);

    String withCount(String label, int n) =>
        n == 0 ? label : l.transactionsListFilterCount(label, fmt.count(n));

    final periodLabel = switch (f.period) {
      TxnPeriod.all => l.transactionsListFilterPeriod,
      TxnPeriod.thisCycle => l.commonPeriodThisCycle,
      TxnPeriod.lastCycle => l.commonPeriodLastCycle,
      TxnPeriod.thisMonth => l.commonPeriodThisMonth,
      TxnPeriod.custom =>
        f.customFrom == null || f.customTo == null
            ? l.commonPeriodCustom
            : l.commonDateRange(
                ZDateFormat.date(
                  DateTime(
                    f.customFrom!.year,
                    f.customFrom!.month,
                    f.customFrom!.day,
                  ),
                  fmt.lang,
                  fmt.digits,
                ),
                ZDateFormat.date(
                  DateTime(
                    f.customTo!.year,
                    f.customTo!.month,
                    f.customTo!.day,
                  ),
                  fmt.lang,
                  fmt.digits,
                ),
              ),
    };
    final cardsLabel = cards.isEmpty
        ? l.commonCardFilterAll
        : cards.length == 1 && lookups?.account(cards.first) != null
        ? accountName(lookups!.account(cards.first)!, fmt)
        : l.commonCardFilterCount(cards.length, fmt.count(cards.length));

    final currencies = <String>{
      for (final a in lookups?.accounts ?? const <TxnAccount>[]) a.currencyCode,
    }.toList()..sort();

    Widget chip(
      String label, {
      required bool active,
      required VoidCallback onTap,
      VoidCallback? onClear,
    }) => Padding(
      padding: const EdgeInsetsDirectional.only(end: ZSpacing.sm),
      child: ZChip(
        label: label,
        selected: active,
        onTap: onTap,
        onClear: active ? onClear : null,
        clearSemanticsLabel: l.commonActionClearFilter,
      ),
    );

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.lg,
            vertical: ZSpacing.xs,
          ),
          child: Row(
            children: [
              chip(
                cardsLabel,
                active: cards.isNotEmpty,
                onClear: ref.read(cardFilterProvider.notifier).clear,
                onTap: () async {
                  final r = await showCardsSheet(
                    context,
                    accounts: lookups?.accounts ?? const [],
                    selected: cards,
                    fmt: fmt,
                  );
                  if (r != null) {
                    ref.read(cardFilterProvider.notifier).setAll(r);
                  }
                },
              ),
              chip(
                periodLabel,
                active: f.period != TxnPeriod.all,
                onClear: () => notifier.set(f.copyWith(period: TxnPeriod.all)),
                onTap: () async {
                  final r = await showPeriodSheet(
                    context,
                    current: f,
                    today: DateTime(today.year, today.month, today.day),
                  );
                  if (r != null) notifier.set(r);
                },
              ),
              chip(
                withCount(
                  l.transactionsListFilterCategory,
                  f.categoryIds.length,
                ),
                active: f.categoryIds.isNotEmpty,
                onClear: () => notifier.set(f.copyWith(categoryIds: {})),
                onTap: () async {
                  final r = await showCategoriesSheet(
                    context,
                    categories: lookups?.categories ?? const [],
                    selected: f.categoryIds,
                    lang: fmt.lang,
                  );
                  if (r != null) notifier.set(f.copyWith(categoryIds: r));
                },
              ),
              chip(
                f.type == TxnTypeFilter.any
                    ? l.transactionsListFilterType
                    : typeLabel(l, f.type),
                active: f.type != TxnTypeFilter.any,
                onClear: () =>
                    notifier.set(f.copyWith(type: TxnTypeFilter.any)),
                onTap: () async {
                  final r = await showTypeSheet(context, current: f.type);
                  if (r != null) notifier.set(f.copyWith(type: r));
                },
              ),
              chip(
                withCount(l.transactionsListFilterSource, f.sources.length),
                active: f.sources.isNotEmpty,
                onClear: () => notifier.set(f.copyWith(sources: {})),
                onTap: () async {
                  final r = await showSourcesSheet(
                    context,
                    selected: f.sources,
                  );
                  if (r != null) notifier.set(f.copyWith(sources: r));
                },
              ),
            ],
          ),
        ),
        if (currencies.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.lg,
              vertical: ZSpacing.xs,
            ),
            child: Row(
              children: [
                for (final code in currencies)
                  chip(
                    code,
                    active: f.currency?.code == code,
                    onClear: () =>
                        notifier.set(f.copyWith(clearCurrency: true)),
                    onTap: () => f.currency?.code == code
                        ? notifier.set(f.copyWith(clearCurrency: true))
                        : notifier.set(f.copyWith(currency: Currency.of(code))),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.enabled,
    required this.onCategory,
    required this.onAccount,
    required this.onDelete,
    required this.onCancel,
  });
  final bool enabled;
  final VoidCallback onCategory;
  final VoidCallback onAccount;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    Widget item(IconData icon, String label, VoidCallback? onTap) => Expanded(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Opacity(
            opacity: onTap == null ? 0.38 : 1,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                vertical: ZSpacing.sm,
                horizontal: ZSpacing.xs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: c.text),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: ZType.caption.copyWith(color: c.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Material(
      color: c.surface,
      elevation: 8,
      child: SafeArea(
        child: Row(
          children: [
            item(
              Icons.category_outlined,
              l.transactionsListBulkCategory,
              enabled ? onCategory : null,
            ),
            item(
              Icons.credit_card,
              l.transactionsListBulkAccount,
              enabled ? onAccount : null,
            ),
            item(
              Icons.delete_outline,
              l.commonActionDelete,
              enabled ? onDelete : null,
            ),
            item(Icons.close, l.commonActionCancel, onCancel),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ZSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: ZType.title.copyWith(color: c.text),
            ),
            if (body != null) ...[
              const SizedBox(height: ZSpacing.sm),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: ZType.body.copyWith(color: c.textMuted),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: ZSpacing.lg),
              ZButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    Widget bar(double w) => Container(
      width: w,
      height: 12,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(ZRadius.sm),
      ),
    );
    return ExcludeSemantics(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: ZSpacing.lg,
                vertical: ZSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: ZSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(140),
                        const SizedBox(height: ZSpacing.sm),
                        bar(90),
                      ],
                    ),
                  ),
                  bar(60),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
