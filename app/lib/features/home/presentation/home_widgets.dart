// T-054: the pieces of Home (S-10): hero, KPIs, review pill, feed rows,
// card filter. Spending is ink, never red; every figure is one currency.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_card.dart';
import '../../../core/ui/z_chip.dart';
import '../../../core/ui/z_money_text.dart';
import '../../../core/ui/z_sheet.dart';
import '../../accounts/data/accounts_providers.dart';
import '../../accounts/domain/account.dart';
import '../../transactions/domain/transaction.dart';
import '../application/card_filter.dart';
import '../application/home_read_model.dart';
import 'home_format.dart';

/// Accounts for the card filter sheet and the filter chip label.
final homeAccountsProvider = FutureProvider<List<Account>>((ref) async {
  final repo = await ref.watch(accountsRepositoryProvider.future);
  return repo.list();
}, name: 'homeAccountsProvider');

/// C-11 hero for one currency.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.figures,
    required this.model,
    required this.format,
    required this.paydaySet,
    this.onTap,
    this.onSetBudget,
  });

  final HomeCurrencyFigures figures;
  final HomeModel model;
  final HomeFormat format;
  final bool paydaySet;
  final VoidCallback? onTap;
  final VoidCallback? onSetBudget;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final safe = figures.safeToSpend;
    final hasBudget = safe != null;
    final used = safe != null && !safe.isPositive;
    final days = model.daysRemaining;
    final rangeText = l.commonDateRange(
      format.date(model.cycle.start),
      format.date(model.cycle.end),
    );
    final label = hasBudget
        ? l.homeHeroSafeToSpend
        : (paydaySet ? l.homeHeroSpentThisCycle : l.homeHeroSpentThisMonth);
    final main = safe ?? figures.spend;
    final caption = paydaySet
        ? '${l.homeHeroDaysToPayday(days, format.count(days))} · $rangeText'
        : l.homeHeroCalendarMonth;
    return ZCard(
      color: c.primaryContainer,
      onTap: onTap,
      padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
      child: Semantics(
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: ZType.label.copyWith(color: c.onPrimaryContainer),
            ),
            const SizedBox(height: ZSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: ZMoneyText(
                    text: format.money(main),
                    size: ZMoneySize.display,
                  ),
                ),
                if (hasBudget) ...[
                  const SizedBox(width: ZSpacing.sm),
                  Text(
                    l.homeHeroPerDay,
                    style: ZType.bodySmall.copyWith(color: c.textMuted),
                  ),
                ],
              ],
            ),
            const SizedBox(height: ZSpacing.xs),
            Text(caption, style: ZType.bodySmall.copyWith(color: c.textMuted)),
            if (used) ...[
              const SizedBox(height: ZSpacing.xs),
              Text(
                l.homeHeroBudgetUsedUp,
                style: ZType.bodySmall.copyWith(color: c.text),
              ),
            ],
            if (!hasBudget) ...[
              const SizedBox(height: ZSpacing.sm),
              Text(
                l.homeHeroSetBudgetHint,
                style: ZType.bodySmall.copyWith(color: c.text),
              ),
              const SizedBox(height: ZSpacing.sm),
              ZButton(
                label: l.homeHeroSetBudget,
                onPressed: onSetBudget,
                size: ZButtonSize.small,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// C-10 KPI trio: income, spent, left (all in one currency).
class HomeKpis extends StatelessWidget {
  const HomeKpis({
    super.key,
    required this.figures,
    required this.format,
    this.onSpentTap,
  });

  final HomeCurrencyFigures figures;
  final HomeFormat format;
  final VoidCallback? onSpentTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Kpi(
              label: l.homeHeroKpiIncome,
              text: format.money(figures.income),
              kind: ZMoneyKind.income,
            ),
          ),
          const SizedBox(width: ZSpacing.sm),
          Expanded(
            child: _Kpi(
              label: l.homeHeroKpiSpent,
              text: format.money(figures.spend),
              kind: ZMoneyKind.expense,
              onTap: onSpentTap,
            ),
          ),
          const SizedBox(width: ZSpacing.sm),
          Expanded(
            child: _Kpi(
              label: l.homeHeroKpiLeft,
              text: format.money(figures.net),
              kind: ZMoneyKind.expense,
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.label,
    required this.text,
    required this.kind,
    this.onTap,
  });

  final String label;
  final String text;
  final ZMoneyKind kind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return ZCard(
      onTap: onTap,
      padding: const EdgeInsetsDirectional.all(ZSpacing.md),
      child: Semantics(
        container: true,
        label: '$label, $text',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: ZType.caption.copyWith(color: c.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: ZSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: ZMoneyText(text: text, kind: kind, size: ZMoneySize.body),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pager dots for the currency pages.
class HomePagerDots extends StatelessWidget {
  const HomePagerDots({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsetsDirectional.symmetric(
                horizontal: ZSpacing.xs,
              ),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == index ? c.primary : c.outline,
              ),
            ),
        ],
      ),
    );
  }
}

/// Review card: shown only when something needs review.
class HomeReviewPill extends StatelessWidget {
  const HomeReviewPill({
    super.key,
    required this.count,
    required this.format,
    this.onTap,
  });

  final int count;
  final HomeFormat format;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ZCard(
      onTap: onTap,
      color: ZColors.of(context).warningBg,
      padding: EdgeInsets.zero,
      child: ZListRow(
        title: l.homeBannerReview(count, format.count(count)),
        showChevron: true,
      ),
    );
  }
}

String _sourceLabel(AppLocalizations l, TxnSource s) => switch (s) {
  TxnSource.sms => l.commonSourceSms,
  TxnSource.notification => l.commonSourceNotification,
  TxnSource.shortcut => l.commonSourceShortcut,
  TxnSource.applePay => l.commonSourceApplePay,
  TxnSource.ocr => l.commonSourceScan,
  TxnSource.pdf => l.commonSourceStatement,
  TxnSource.csv => l.commonSourceCsv,
  TxnSource.voice => l.commonSourceVoice,
  TxnSource.manual => l.commonSourceManual,
  TxnSource.share => l.commonSourceShared,
};

String _typeLabel(AppLocalizations l, HomeFeedItem item) {
  if (item.excludedFromTotals) return l.commonTxnTypeInternal;
  return switch (item.record.direction) {
    TxnDirection.expense || TxnDirection.fee => l.commonTxnTypeExpense,
    TxnDirection.income => l.commonTxnTypeIncome,
    TxnDirection.transferOut ||
    TxnDirection.transferIn => l.commonTxnTypeTransfer,
    TxnDirection.refund => l.commonTxnTypeRefund,
  };
}

/// C-05 feed row.
class HomeFeedRow extends StatelessWidget {
  const HomeFeedRow({
    super.key,
    required this.item,
    required this.format,
    required this.today,
    this.onTap,
  });

  final HomeFeedItem item;
  final HomeFormat format;
  final CivilDate today;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final r = item.record;
    final title = r.merchantNorm ?? r.merchantRaw ?? _typeLabel(l, item);
    final local = r.occurredAt.toLocal();
    final sameDay =
        local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
    final when = l.commonDateDateTime(
      sameDay ? l.commonDateToday : format.dateOf(r.occurredAt),
      format.time(r.occurredAt),
    );
    final subtitle = item.excludedFromTotals
        ? '${_typeLabel(l, item)} · $when'
        : '${_sourceLabel(l, r.source)} · $when';
    final (Money shown, ZMoneyKind kind) = item.excludedFromTotals
        ? (r.amount, ZMoneyKind.neutral)
        : switch (r.direction) {
            TxnDirection.income ||
            TxnDirection.refund ||
            TxnDirection.transferIn => (r.amount, ZMoneyKind.income),
            _ => (-r.amount, ZMoneyKind.expense),
          };
    final text = format.money(shown);
    return ZListRow(
      title: title,
      subtitle: subtitle,
      leading: ZCategoryTile(
        color: item.excludedFromTotals ? c.textMuted : c.primary,
        child: Icon(
          item.excludedFromTotals
              ? Icons.swap_horiz
              : Icons.receipt_long_outlined,
          size: 20,
          color: c.text,
        ),
      ),
      trailing: ZMoneyText(text: text, kind: kind),
      onTap: onTap == null ? null : () => onTap!(r.id),
    );
  }
}

/// C-08 card filter chip; opens the multi-select sheet.
class HomeCardFilterChip extends ConsumerWidget {
  const HomeCardFilterChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final filter = ref.watch(cardFilterProvider);
    final accounts = ref.watch(homeAccountsProvider).value ?? const [];
    final names = homeFilterNames(accounts, filter);
    final label = filter.isEmpty
        ? l.commonCardFilterAll
        : (filter.length == 1 && names.length == 1
              ? names.first
              : l.commonCardFilterCount(
                  filter.length,
                  HomeFormat.of(context, ref).count(filter.length),
                ));
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
      child: Semantics(
        button: true,
        label: filter.isEmpty
            ? label
            : l.commonCardFilterActiveA11y(names.join(', ')),
        excludeSemantics: true,
        child: Center(
          child: ZChip(
            label: label,
            selected: filter.isNotEmpty,
            icon: Icons.credit_card,
            onTap: () => showZSheet<void>(
              context: context,
              title: l.commonCardFilterSheetTitle,
              builder: (_) => const HomeCardFilterSheet(),
            ),
            onClear: filter.isEmpty
                ? null
                : () => ref.read(cardFilterProvider.notifier).clear(),
            clearSemanticsLabel: l.commonCardFilterClearA11y,
          ),
        ),
      ),
    );
  }
}

/// Display names of the filtered accounts.
List<String> homeFilterNames(List<Account> accounts, Set<String> filter) => [
  for (final a in accounts)
    if (filter.contains(a.id))
      a.last4 == null ? a.label : '${a.label} •${a.last4}',
];

class HomeCardFilterSheet extends ConsumerWidget {
  const HomeCardFilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final filter = ref.watch(cardFilterProvider);
    final accounts = ref.watch(homeAccountsProvider).value ?? const [];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CheckboxListTile(
          value: filter.isEmpty,
          title: Text(l.commonCardFilterAll),
          onChanged: (_) => ref.read(cardFilterProvider.notifier).clear(),
        ),
        for (final a in accounts)
          CheckboxListTile(
            value: filter.contains(a.id),
            title: Text(a.last4 == null ? a.label : '${a.label} •${a.last4}'),
            onChanged: (_) =>
                ref.read(cardFilterProvider.notifier).toggle(a.id),
          ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ZButton(
            label: l.commonActionDone,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
