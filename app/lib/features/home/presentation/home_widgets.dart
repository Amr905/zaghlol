// T-054: the pieces of Home (S-10): hero, KPIs, review pill, feed rows,
// card filter. Spending is ink, never red; every figure is one currency.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_card.dart';
import '../../../core/ui/category_glyph.dart';
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

/// C-11 hero for one currency: mint gradient card with the safe-to-spend
/// figure, the cycle progress bar and the nested income / spent / left panel
/// (mockups 03 / 20 / 21).
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.figures,
    required this.model,
    required this.format,
    required this.paydaySet,
    this.onTap,
    this.onSetBudget,
    this.onSpentTap,
  });

  final HomeCurrencyFigures figures;
  final HomeModel model;
  final HomeFormat format;
  final bool paydaySet;
  final VoidCallback? onTap;
  final VoidCallback? onSetBudget;
  final VoidCallback? onSpentTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final safe = figures.safeToSpend;
    final hasBudget = safe != null;
    final used = safe != null && !safe.isPositive;
    final days = model.daysRemaining;
    // The generated signature is (end, start): placeholders are sorted.
    final rangeText = l.commonDateRange(
      format.dayMonth(model.cycle.end),
      format.dayMonth(model.cycle.start),
    );
    final label = hasBudget
        ? l.homeHeroSafeToSpend
        : (paydaySet ? l.homeHeroSpentThisCycle : l.homeHeroSpentThisMonth);
    final main = safe ?? figures.spend;
    final caption = paydaySet
        ? '${l.homeHeroDaysToPayday(days, format.count(days))} · $rangeText'
        : l.homeHeroCalendarMonth;
    final progress = _progress(figures);
    return ZHeroCard(
      onTap: onTap,
      padding: const EdgeInsetsDirectional.fromSTEB(
        ZSpacing.xl,
        ZSpacing.xl,
        ZSpacing.xl,
        ZSpacing.xl,
      ),
      child: Semantics(
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: ZType.titleSmall.copyWith(
                color: c.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: ZSpacing.xs),
            ZMoneyText(
              text: format.number(main),
              unit: format.currency(main),
              size: ZMoneySize.hero,
              semanticsLabel: format.money(main),
            ),
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
            const SizedBox(height: ZSpacing.lg),
            ZProgressBar(value: progress),
            const SizedBox(height: ZSpacing.sm),
            HomeKpis(figures: figures, format: format, onSpentTap: onSpentTap),
          ],
        ),
      ),
    );
  }

  /// Share of the budget (or, without one, of the income) already spent.
  static double _progress(HomeCurrencyFigures f) {
    final base = f.overview.budget ?? f.income;
    if (!base.isPositive) return 0;
    final spent = f.spend.minor;
    return (spent / base.minor).clamp(0.0, 1.0).toDouble();
  }
}

/// C-10 KPI trio nested in the hero: income, spent, left (one currency).
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
    final c = ZColors.of(context);
    final radius = BorderRadius.circular(ZRadius.lg + 4);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.72),
        borderRadius: radius,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.lg,
          vertical: ZSpacing.md,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Kpi(
                  label: l.homeHeroKpiIncome,
                  text: format.number(figures.income),
                ),
              ),
              Expanded(
                child: _Kpi(
                  label: l.homeHeroKpiSpent,
                  text: format.number(figures.spend),
                  onTap: onSpentTap,
                ),
              ),
              Expanded(
                child: _Kpi(
                  label: l.homeHeroKpiLeft,
                  text: format.number(figures.net),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.text, this.onTap});

  final String label;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZRadius.md),
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
              style: ZType.bodySmall.copyWith(color: c.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                text,
                style: ZType.titleSmall.copyWith(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
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

/// Review card: shown only when something needs review (mockup 03).
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
    final c = ZColors.of(context);
    final radius = BorderRadius.circular(ZRadius.card);
    return MergeSemantics(
      child: Material(
        color: c.warningBg,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ZSpacing.minTarget + 8,
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: ZSpacing.lg,
              ),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: c.warningText,
                    ),
                  ),
                  const SizedBox(width: ZSpacing.md),
                  Expanded(
                    child: Text(
                      l.homeBannerReview(count, format.count(count)),
                      style: ZType.titleSmall.copyWith(color: c.warningText),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: c.warningText),
                ],
              ),
            ),
          ),
        ),
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

/// C-05 feed row: emoji tile, merchant, "account •1234 · time", amount.
class HomeFeedRow extends StatelessWidget {
  const HomeFeedRow({
    super.key,
    required this.item,
    required this.format,
    required this.today,
    this.accountLabel,
    this.showDivider = false,
    this.onTap,
  });

  final HomeFeedItem item;
  final HomeFormat format;
  final CivilDate today;

  /// "Account •1234" for the row's card; null falls back to the source.
  final String? accountLabel;
  final bool showDivider;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final r = item.record;
    final title = r.merchantNorm ?? r.merchantRaw ?? _typeLabel(l, item);
    final local = r.occurredAt.toLocal();
    final sameDay =
        local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
    final where = accountLabel ?? _sourceLabel(l, r.source);
    final when = sameDay
        ? format.time(r.occurredAt)
        : format.dayMonthOf(r.occurredAt);
    final subtitle = item.excludedFromTotals
        ? '$where · ${l.homeFeedExcludedFromSpending}'
        : '$where · $when';
    final (Money shown, ZMoneyKind kind) = item.excludedFromTotals
        ? (r.amount, ZMoneyKind.neutral)
        : switch (r.direction) {
            TxnDirection.income ||
            TxnDirection.refund ||
            TxnDirection.transferIn => (r.amount, ZMoneyKind.income),
            _ => (-r.amount, ZMoneyKind.expense),
          };
    final income = kind == ZMoneyKind.income && !item.excludedFromTotals;
    return ZListRow(
      title: title,
      subtitle: subtitle,
      showDivider: showDivider,
      leading: ZCategoryGlyph(
        categoryId: r.categoryId,
        income: income,
        transfer: item.excludedFromTotals,
      ),
      trailing: ZMoneyText(
        text: _signed(format.number(shown), kind, shown),
        unit: format.currency(shown),
        kind: kind,
        semanticsLabel: format.money(shown),
      ),
      onTap: onTap == null ? null : () => onTap!(r.id),
    );
  }

  /// Income gets an explicit plus (the minus is already in the number).
  static String _signed(String number, ZMoneyKind kind, Money m) =>
      kind == ZMoneyKind.income && m.isPositive
      ? '\u2068+${number.replaceAll(RegExp('[\u2068\u2069]'), '')}\u2069'
      : number;
}

/// C-08 card filter: a white pill "funnel / label / chevron" on iOS, a bare
/// funnel icon button on Android (mockups 03 / 20). Opens the multi-select
/// sheet; an active filter shows the mint fill and a clear button.
class HomeCardFilterChip extends ConsumerWidget {
  const HomeCardFilterChip({super.key, this.iconOnly = false});

  final bool iconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
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
    final semantics = filter.isEmpty
        ? label
        : l.commonCardFilterActiveA11y(names.join(', '));
    void open() => showZSheet<void>(
      context: context,
      title: l.commonCardFilterSheetTitle,
      builder: (_) => const HomeCardFilterSheet(),
    );
    final active = filter.isNotEmpty;
    if (iconOnly) {
      return Semantics(
        button: true,
        label: semantics,
        excludeSemantics: true,
        child: IconButton(
          constraints: const BoxConstraints(
            minWidth: ZSpacing.minTarget,
            minHeight: ZSpacing.minTarget,
          ),
          icon: Icon(
            Icons.filter_alt_outlined,
            color: active ? c.primary : c.text,
          ),
          onPressed: open,
        ),
      );
    }
    final radius = BorderRadius.circular(ZRadius.pill);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
      child: Semantics(
        button: true,
        label: semantics,
        excludeSemantics: true,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: active ? c.primaryContainer : c.surface,
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: c.shadow,
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                borderRadius: radius,
                onTap: open,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    ZSpacing.lg,
                    ZSpacing.sm,
                    ZSpacing.md,
                    ZSpacing.sm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_alt_outlined, size: 20, color: c.text),
                      const SizedBox(width: ZSpacing.sm),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZType.titleSmall.copyWith(
                            color: c.text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: ZSpacing.sm),
                      if (active)
                        InkResponse(
                          onTap: () =>
                              ref.read(cardFilterProvider.notifier).clear(),
                          child: Semantics(
                            button: true,
                            label: l.commonCardFilterClearA11y,
                            excludeSemantics: true,
                            child: Icon(Icons.close, size: 20, color: c.text),
                          ),
                        )
                      else
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: c.textMuted,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings button: a white circle on iOS, a plain icon on Android.
class HomeSettingsButton extends StatelessWidget {
  const HomeSettingsButton({super.key, required this.onPressed, this.circle});

  final VoidCallback? onPressed;
  final bool? circle;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final l = AppLocalizations.of(context);
    final round = circle ?? Theme.of(context).platform == TargetPlatform.iOS;
    final button = IconButton(
      tooltip: l.commonNavSettingsA11y,
      constraints: const BoxConstraints(
        minWidth: ZSpacing.minTarget,
        minHeight: ZSpacing.minTarget,
      ),
      icon: Icon(Icons.settings_outlined, color: c.text),
      onPressed: onPressed,
    );
    if (!round) return button;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: button,
    );
  }
}

/// The clock behind the greeting; tests override it.
final homeNowProvider = Provider<DateTime>(
  (ref) => DateTime.now(),
  name: 'homeNowProvider',
);

/// ICU select key for [AppLocalizations.homeGreetingByTime].
String greetingPart(int hour) => hour >= 5 && hour < 12
    ? 'morning'
    : hour >= 12 && hour < 18
    ? 'afternoon'
    : 'evening';

/// Time-of-day greeting headline ("صباح الفل يا كبير ☀️").
class HomeGreeting extends ConsumerWidget {
  const HomeGreeting({super.key, this.fontSize});

  final double? fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final h = ref.watch(homeNowProvider).hour;
    final part = greetingPart(h);
    return Semantics(
      header: true,
      child: Text(
        l.homeGreetingByTime(part),
        key: const ValueKey('home-greeting'),
        style: ZType.display.copyWith(
          fontSize: fontSize ?? 34,
          height: 1.3,
          color: c.text,
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
