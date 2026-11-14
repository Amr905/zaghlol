// T-101: S-22 Budget (mockup 09). Reads [budgetScreenDataProvider]; every
// amount is shown per currency and never summed across currencies. Spending
// stays in ink; terracotta appears only from 85% and always with a text cue.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_card.dart';
import '../../../core/ui/z_chip.dart';
import 'budget_providers_ui.dart';
import 'budget_view.dart';
import 'edit_budgets_screen.dart';

class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key, this.onCategoryTap, this.onSetPayday});

  /// S-11 (category + cycle); wired by the transactions feature.
  final void Function(String categoryId, Cycle cycle)? onCategoryTap;

  /// S-72 payday stepper.
  final VoidCallback? onSetPayday;

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  String? _currencyCode;

  void _edit(Currency currency) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditBudgetsScreen(initialCurrency: currency),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(budgetScreenDataProvider);
    return async.when(
      loading: () => Semantics(
        label: l.budgetOverviewLoadingA11y,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) =>
          _ErrorView(onRetry: () => ref.invalidate(budgetScreenDataProvider)),
      data: (data) {
        final views = data.currencies;
        final current = views.isEmpty
            ? null
            : views.firstWhere(
                (v) => v.currency.code == _currencyCode,
                orElse: () => views.first,
              );
        return ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(
            ZSpacing.screen,
            ZSpacing.sm,
            ZSpacing.screen,
            ZSpacing.xxl,
          ),
          children: [
            _CycleHeader(data: data),
            if (views.length > 1) ...[
              const SizedBox(height: ZSpacing.sm),
              Wrap(
                spacing: ZSpacing.sm,
                runSpacing: ZSpacing.sm,
                children: [
                  for (final v in views)
                    ZChip(
                      label: v.currency.code,
                      selected: v == current,
                      onTap: () =>
                          setState(() => _currencyCode = v.currency.code),
                    ),
                ],
              ),
            ],
            const SizedBox(height: ZSpacing.md),
            if (current == null)
              _EmptyBudget(
                onSet: () => _edit(defaultBudgetCurrency),
                spentText: null,
              )
            else ...[
              if (views.length > 1)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    bottom: ZSpacing.sm,
                  ),
                  child: Text(
                    l.budgetOverviewCurrencyNote(current.currency.code),
                    style: ZType.caption.copyWith(
                      color: ZColors.of(context).textMuted,
                    ),
                  ),
                ),
              _CurrencySection(
                data: data,
                view: current,
                onEdit: () => _edit(current.currency),
                onCategoryTap: widget.onCategoryTap,
              ),
            ],
            if (data.calendarMonth && widget.onSetPayday != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ZButton(
                  label: l.budgetOverviewSetPayday,
                  variant: ZButtonVariant.text,
                  onPressed: widget.onSetPayday,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.commonErrorLoadFailed,
              textAlign: TextAlign.center,
              style: ZType.body.copyWith(color: ZColors.of(context).text),
            ),
            const SizedBox(height: ZSpacing.lg),
            ZButton(label: l.commonActionTryAgain, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

String _money(WidgetRef ref, BuildContext context, Money m) {
  final lang = Localizations.localeOf(context).languageCode;
  return MoneyFormat.format(
    m,
    languageCode: lang,
    digits: ref.watch(digitsModeProvider(lang)),
  );
}

String _percent(WidgetRef ref, BuildContext context, int p) {
  final lang = Localizations.localeOf(context).languageCode;
  return ref.watch(digitsModeProvider(lang)).render('$p%');
}

class _CycleHeader extends ConsumerWidget {
  const _CycleHeader({required this.data});
  final BudgetScreenData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    // Noon UTC: the formatter converts to local time and the civil date
    // must survive any zone offset (no DateTime constructor in this feature).
    DateTime d(CivilDate x) => DateTime.utc(x.year, x.month, x.day, 12);
    final range = l.budgetOverviewCycle(
      ZDateFormat.date(d(data.cycle.start), lang, digits),
      ZDateFormat.date(d(data.cycle.end), lang, digits),
    );
    final offsetNotifier = ref.read(budgetCycleOffsetProvider.notifier);
    return Row(
      children: [
        IconButton(
          tooltip: l.budgetOverviewPrevA11y,
          constraints: const BoxConstraints(
            minWidth: ZSpacing.minTarget,
            minHeight: ZSpacing.minTarget,
          ),
          onPressed: data.hasPrevious ? offsetNotifier.previous : null,
          icon: Icon(startChevron(context), color: c.text),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                data.calendarMonth ? l.budgetOverviewCalendarMonth : range,
                textAlign: TextAlign.center,
                style: ZType.titleSmall.copyWith(color: c.text),
              ),
              if (data.calendarMonth)
                Text(
                  range,
                  textAlign: TextAlign.center,
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
              if (data.isCurrent)
                Text(
                  l.budgetOverviewDaysLeft(
                    data.daysRemaining,
                    digits.render('${data.daysRemaining}'),
                  ),
                  textAlign: TextAlign.center,
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: l.budgetOverviewNextA11y,
          constraints: const BoxConstraints(
            minWidth: ZSpacing.minTarget,
            minHeight: ZSpacing.minTarget,
          ),
          onPressed: data.isCurrent ? null : offsetNotifier.next,
          icon: Icon(endChevron(context), color: c.text),
        ),
      ],
    );
  }
}

class _EmptyBudget extends StatelessWidget {
  const _EmptyBudget({required this.onSet, required this.spentText});
  final VoidCallback onSet;
  final String? spentText;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.budgetOverviewEmptyTitle,
            style: ZType.titleSmall.copyWith(color: c.text),
          ),
          const SizedBox(height: ZSpacing.xs),
          Text(
            l.budgetOverviewEmptyBody,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.md),
          ZButton(label: l.budgetOverviewEmptyAction, onPressed: onSet),
        ],
      ),
    );
  }
}

class _CurrencySection extends ConsumerWidget {
  const _CurrencySection({
    required this.data,
    required this.view,
    required this.onEdit,
    required this.onCategoryTap,
  });

  final BudgetScreenData data;
  final CurrencyBudgetView view;
  final VoidCallback onEdit;
  final void Function(String, Cycle)? onCategoryTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    String name(BudgetRowView r) => lang == 'ar' ? r.nameAr : r.nameEn;
    final hot = [
      for (final r in view.rows)
        if ((r.progress.percent ?? 0) >= budgetWarnPercent) r,
    ]..sort((a, b) => b.progress.percent!.compareTo(a.progress.percent!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!view.hasBudget)
          _EmptyBudget(onSet: onEdit, spentText: null)
        else
          ZCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.budgetOverviewOverall(
                    _money(ref, context, view.spent),
                    _money(ref, context, view.limit!),
                  ),
                  style: ZType.titleSmall.copyWith(color: c.text),
                ),
                const SizedBox(height: ZSpacing.sm),
                _Bar(percent: view.percent ?? 0),
                const SizedBox(height: ZSpacing.sm),
                Text(
                  _percent(ref, context, view.percent ?? 0),
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
                if (view.safePerDay != null) ...[
                  const SizedBox(height: ZSpacing.xs),
                  Text(
                    l.budgetOverviewSafePerDay(
                      _money(ref, context, view.safePerDay!),
                    ),
                    style: ZType.body.copyWith(color: c.text),
                  ),
                ],
              ],
            ),
          ),
        if (hot.isNotEmpty && data.isCurrent) ...[
          const SizedBox(height: ZSpacing.md),
          ZCard(
            color: c.zaghlolBg,
            child: Text(
              l.homeMascotShockedCategory(
                name(hot.first),
                _percent(ref, context, hot.first.progress.percent!),
              ),
              style: ZType.body.copyWith(color: c.text),
            ),
          ),
        ],
        const SizedBox(height: ZSpacing.md),
        for (final r in view.rows)
          _CategoryRow(
            name: name(r),
            row: r,
            onTap: onCategoryTap == null
                ? null
                : () => onCategoryTap!(r.categoryId, data.cycle),
          ),
        if (view.notBudgeted.minor > 0)
          _NotBudgetedRow(amount: _money(ref, context, view.notBudgeted)),
        const SizedBox(height: ZSpacing.md),
        if (view.hasBudget)
          ZButton(
            label: l.budgetOverviewEdit,
            variant: ZButtonVariant.secondary,
            onPressed: onEdit,
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final warn = percent >= budgetWarnPercent;
    final fill = percent.clamp(0, 100) / 100;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ZRadius.pill),
        child: SizedBox(
          height: ZSpacing.sm,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: c.surfaceAlt)),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: fill,
                  child: ColoredBox(color: warn ? c.dangerText : c.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({
    required this.name,
    required this.row,
    required this.onTap,
  });

  final String name;
  final BudgetRowView row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final p = row.progress;
    final pct = p.percent ?? 0;
    final spent = _money(ref, context, p.spent);
    final limit = _money(ref, context, p.effectiveLimit);
    final status = p.percent == null
        ? null
        : pct > 100 && p.spent.minor > p.effectiveLimit.minor
        ? l.budgetOverviewStatusOver(
            _money(ref, context, p.spent - p.effectiveLimit),
          )
        : pct >= 100
        ? l.budgetOverviewStatusFull
        : pct >= budgetWarnPercent
        ? l.budgetOverviewStatusNear
        : null;
    return Semantics(
      button: onTap != null,
      excludeSemantics: true,
      label: l.budgetOverviewRowA11y(
        name,
        spent,
        limit,
        _percent(ref, context, pct),
      ),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: ZSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: ZType.body.copyWith(color: c.text),
                      ),
                    ),
                    const SizedBox(width: ZSpacing.sm),
                    Text(
                      _percent(ref, context, pct),
                      style: ZType.label.copyWith(
                        color: pct >= budgetWarnPercent
                            ? c.dangerText
                            : c.textMuted,
                      ),
                    ),
                  ],
                ),
                Text(
                  l.budgetOverviewRowAmounts(spent, limit),
                  style: ZType.bodySmall.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: ZSpacing.xs),
                _Bar(percent: pct),
                if (status != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                    child: Text(
                      status,
                      style: ZType.caption.copyWith(color: c.dangerText),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotBudgetedRow extends StatelessWidget {
  const _NotBudgetedRow({required this.amount});
  final String amount;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Semantics(
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.budgetOverviewNotBudgeted,
                    style: ZType.body.copyWith(color: c.text),
                  ),
                  Text(
                    l.budgetOverviewNotBudgetedSub,
                    style: ZType.caption.copyWith(color: c.textMuted),
                  ),
                ],
              ),
            ),
            Text(amount, style: ZType.bodySmall.copyWith(color: c.text)),
          ],
        ),
      ),
    );
  }
}

/// Chevrons that follow the reading direction (no `left`/`right` branching in
/// the screens).
IconData startChevron(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? Icons.chevron_right
    : Icons.chevron_left;

IconData endChevron(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? Icons.chevron_left
    : Icons.chevron_right;
