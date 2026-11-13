// T-079: the sheets behind the filter chips and the bulk actions of S-11.

import 'package:flutter/material.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_components.dart';
import '../../domain/transaction.dart';
import 'txn_list_providers.dart';
import 'txn_row.dart';

Widget _check(BuildContext context, bool on) => Icon(
  on ? Icons.check_circle : Icons.radio_button_unchecked,
  color: on ? ZColors.of(context).primary : ZColors.of(context).textMuted,
);

Widget _option(
  BuildContext context, {
  required String title,
  required bool on,
  required VoidCallback onTap,
  Widget? leading,
}) => ZListRow(
  title: title,
  leading: leading,
  trailing: _check(context, on),
  onTap: onTap,
);

/// Period sheet: this cycle / last cycle / this month / custom / all time.
/// Returns the new filter; custom opens the date-range picker (start <= end,
/// end <= today).
Future<TxnListFilter?> showPeriodSheet(
  BuildContext context, {
  required TxnListFilter current,
  required DateTime today,
}) {
  final l = AppLocalizations.of(context);
  return showZSheet<TxnListFilter>(
    context: context,
    title: l.transactionsListFilterPeriod,
    builder: (ctx) {
      Widget opt(String label, TxnPeriod p) => _option(
        ctx,
        title: label,
        on: current.period == p,
        onTap: () async {
          if (p != TxnPeriod.custom) {
            Navigator.of(ctx).pop(current.copyWith(period: p));
            return;
          }
          final range = await showDateRangePicker(
            context: ctx,
            firstDate: DateTime(2000),
            lastDate: today,
            helpText: l.transactionsListRangeTitle,
            saveText: l.commonActionDone,
          );
          if (range == null || !ctx.mounted) return;
          Navigator.of(ctx).pop(
            current.copyWith(
              period: TxnPeriod.custom,
              customFrom: CivilDate(
                range.start.year,
                range.start.month,
                range.start.day,
              ),
              customTo: CivilDate(
                range.end.year,
                range.end.month,
                range.end.day,
              ),
            ),
          );
        },
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          opt(l.commonPeriodThisCycle, TxnPeriod.thisCycle),
          opt(l.commonPeriodLastCycle, TxnPeriod.lastCycle),
          opt(l.commonPeriodThisMonth, TxnPeriod.thisMonth),
          opt(l.commonPeriodCustom, TxnPeriod.custom),
        ],
      );
    },
  );
}

/// Multi-choice category sheet; returns the chosen ids on Done.
Future<Set<String>?> showCategoriesSheet(
  BuildContext context, {
  required List<TxnCategory> categories,
  required Set<String> selected,
  required String lang,
}) {
  final l = AppLocalizations.of(context);
  var picked = {...selected};
  return showZSheet<Set<String>>(
    context: context,
    title: l.transactionsListFilterCategory,
    fullHeight: true,
    actions: Builder(
      builder: (ctx) => ZButton(
        label: l.commonActionDone,
        expand: true,
        onPressed: () => Navigator.of(ctx).pop(picked),
      ),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => ListView(
        shrinkWrap: true,
        children: [
          for (final c in categories)
            _option(
              ctx,
              title: categoryName(c, lang),
              on: picked.contains(c.id),
              leading: Text(c.icon, style: ZType.title),
              onTap: () => setState(() {
                picked = picked.contains(c.id)
                    ? ({...picked}..remove(c.id))
                    : {...picked, c.id};
              }),
            ),
        ],
      ),
    ),
  );
}

String typeLabel(AppLocalizations l, TxnTypeFilter t) => switch (t) {
  TxnTypeFilter.expense => l.commonTxnTypeExpense,
  TxnTypeFilter.income => l.commonTxnTypeIncome,
  TxnTypeFilter.transfer => l.commonTxnTypeTransfer,
  TxnTypeFilter.refund => l.commonTxnTypeRefund,
  TxnTypeFilter.declined => l.commonTxnTypeDeclined,
  TxnTypeFilter.any => '',
};

/// Single-choice type sheet; tapping the chosen type again clears it.
Future<TxnTypeFilter?> showTypeSheet(
  BuildContext context, {
  required TxnTypeFilter current,
}) {
  final l = AppLocalizations.of(context);
  return showZSheet<TxnTypeFilter>(
    context: context,
    title: l.transactionsListFilterType,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in TxnTypeFilter.values.where(
          (t) => t != TxnTypeFilter.any,
        ))
          _option(
            ctx,
            title: typeLabel(l, t),
            on: current == t,
            onTap: () =>
                Navigator.of(ctx).pop(current == t ? TxnTypeFilter.any : t),
          ),
      ],
    ),
  );
}

/// Multi-choice source sheet.
Future<Set<TxnSource>?> showSourcesSheet(
  BuildContext context, {
  required Set<TxnSource> selected,
}) {
  final l = AppLocalizations.of(context);
  var picked = {...selected};
  return showZSheet<Set<TxnSource>>(
    context: context,
    title: l.transactionsListFilterSource,
    fullHeight: true,
    actions: Builder(
      builder: (ctx) => ZButton(
        label: l.commonActionDone,
        expand: true,
        onPressed: () => Navigator.of(ctx).pop(picked),
      ),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => ListView(
        shrinkWrap: true,
        children: [
          for (final s in TxnSource.values)
            _option(
              ctx,
              title: sourceLabel(l, s),
              on: picked.contains(s),
              onTap: () => setState(() {
                picked = picked.contains(s)
                    ? ({...picked}..remove(s))
                    : {...picked, s};
              }),
            ),
        ],
      ),
    ),
  );
}

/// The global card filter (FR-CARD-01); empty set = all cards.
Future<Set<String>?> showCardsSheet(
  BuildContext context, {
  required List<TxnAccount> accounts,
  required Set<String> selected,
  required TxnFmt fmt,
}) {
  final l = AppLocalizations.of(context);
  var picked = {...selected};
  return showZSheet<Set<String>>(
    context: context,
    title: l.commonCardFilterSheetTitle,
    fullHeight: true,
    actions: Builder(
      builder: (ctx) => ZButton(
        label: l.commonActionDone,
        expand: true,
        onPressed: () => Navigator.of(ctx).pop(picked),
      ),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => ListView(
        shrinkWrap: true,
        children: [
          _option(
            ctx,
            title: l.commonCardFilterAll,
            on: picked.isEmpty,
            onTap: () => setState(() => picked = {}),
          ),
          for (final a in accounts)
            _option(
              ctx,
              title: accountName(a, fmt),
              on: picked.contains(a.id),
              onTap: () => setState(() {
                picked = picked.contains(a.id)
                    ? ({...picked}..remove(a.id))
                    : {...picked, a.id};
              }),
            ),
        ],
      ),
    ),
  );
}

/// Bulk category picker with the "always use for these merchants" switch.
Future<({String id, bool always})?> showBulkCategorySheet(
  BuildContext context, {
  required List<TxnCategory> categories,
  required String lang,
}) {
  final l = AppLocalizations.of(context);
  var always = false;
  return showZSheet<({String id, bool always})>(
    context: context,
    title: l.transactionsListBulkCategory,
    fullHeight: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Column(
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.lg,
            ),
            title: Text(l.transactionsListBulkRule),
            value: always,
            onChanged: (v) => setState(() => always = v),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final c in categories)
                  ZListRow(
                    title: categoryName(c, lang),
                    leading: Text(c.icon, style: ZType.title),
                    onTap: () =>
                        Navigator.of(ctx).pop((id: c.id, always: always)),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Bulk account ("card") picker.
Future<String?> showBulkAccountSheet(
  BuildContext context, {
  required List<TxnAccount> accounts,
  required TxnFmt fmt,
}) {
  final l = AppLocalizations.of(context);
  return showZSheet<String>(
    context: context,
    title: l.transactionsListBulkAccount,
    fullHeight: true,
    builder: (ctx) => ListView(
      shrinkWrap: true,
      children: [
        for (final a in accounts)
          ZListRow(
            title: accountName(a, fmt),
            onTap: () => Navigator.of(ctx).pop(a.id),
          ),
      ],
    ),
  );
}

/// «تمسح 4 حركات؟» confirmation. True = delete.
Future<bool> confirmBulkDelete(
  BuildContext context, {
  required int count,
  required String n,
}) async {
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.transactionsListBulkDeleteTitle(count, n)),
      content: Text(l.transactionsListBulkDeleteBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.commonActionCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.commonActionDelete),
        ),
      ],
    ),
  );
  return ok ?? false;
}
