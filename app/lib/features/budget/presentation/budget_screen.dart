// T-101: S-22 Budget (mockup 09). Reads [budgetScreenDataProvider]; every
// amount is shown per currency and never summed across currencies. Spending
// stays in ink; terracotta appears only from 85% and always with a text cue.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_card.dart';
import '../../../core/ui/z_chip.dart';
import '../../../core/db/app_database.dart' show CategoryRow;
import '../../categorization/presentation/category_tile.dart';
import '../../insights/presentation/charts/chart_format.dart';
import '../../insights/presentation/charts/chart_palette.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
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
            ZSpacing.fabClearance,
          ),
          children: [
            if (views.length > 1) ...[
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
            if (views.length > 1) const SizedBox(height: ZSpacing.md),
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
  return trimZeroFraction(
    MoneyFormat.format(
      m,
      languageCode: lang,
      digits: ref.watch(digitsModeProvider(lang)),
    ),
  );
}

String _percent(WidgetRef ref, BuildContext context, int p) {
  final lang = Localizations.localeOf(context).languageCode;
  return ref.watch(digitsModeProvider(lang)).render('$p%');
}

/// The cycle line of the hero card: "25 Oct to 24 Nov . 7 days left", with
/// previous/next chevrons only when there is another cycle to go to.
class _CycleLine extends ConsumerWidget {
  const _CycleLine({required this.data});
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
    String short(CivilDate x) => digits.render(
      DateFormat.MMMd(lang)
          .format(d(x))
          .replaceAllMapped(
            RegExp('[٠-٩]'),
            (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x0660 + 0x30),
          ),
    );
    final range = l.budgetOverviewCycle(
      short(data.cycle.start),
      short(data.cycle.end),
    );
    final left = data.isCurrent
        ? l.budgetOverviewDaysLeft(
            data.daysRemaining,
            digits.render('${data.daysRemaining}'),
          )
        : null;
    final offsetNotifier = ref.read(budgetCycleOffsetProvider.notifier);
    final canGoBack = data.hasPrevious;
    final canGoNext = !data.isCurrent;
    Widget nav(String tip, IconData icon, VoidCallback? onTap) => IconButton(
      tooltip: tip,
      constraints: const BoxConstraints(
        minWidth: ZSpacing.minTarget,
        minHeight: ZSpacing.minTarget,
      ),
      onPressed: onTap,
      icon: Icon(icon, color: c.text),
    );
    return Row(
      children: [
        if (canGoBack || canGoNext)
          nav(
            l.budgetOverviewPrevA11y,
            startChevron(context),
            canGoBack ? offsetNotifier.previous : null,
          ),
        Expanded(
          child: Text(
            [
              if (data.calendarMonth) l.budgetOverviewCalendarMonth else range,
              ?left,
            ].join(' · '),
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
        ),
        if (canGoBack || canGoNext)
          nav(
            l.budgetOverviewNextA11y,
            endChevron(context),
            canGoNext ? offsetNotifier.next : null,
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
    final cats = {
      for (final r in ref.watch(categoryRowsProvider).value ?? <CategoryRow>[])
        r.id: r,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!view.hasBudget)
          _EmptyBudget(onSet: onEdit, spentText: null)
        else
          ZCard(
            padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CycleLine(data: data),
                const SizedBox(height: ZSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Semantics(
                        label: l.budgetOverviewOverall(
                          _money(ref, context, view.spent),
                          _money(ref, context, view.limit!),
                        ),
                        excludeSemantics: true,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: trimCurrency(
                                  _money(ref, context, view.spent),
                                ),
                                style: ZType.display.copyWith(color: c.text),
                              ),
                              TextSpan(
                                text:
                                    ' ${l.budgetOverviewOfLimit(_money(ref, context, view.limit!))}',
                                style: ZType.body.copyWith(color: c.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Text(
                      _percent(ref, context, view.percent ?? 0),
                      style: ZType.titleSmall.copyWith(
                        color: _percentColor(c, view.percent ?? 0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZSpacing.sm),
                _Bar(percent: view.percent ?? 0),
                if (view.safePerDay != null) ...[
                  const SizedBox(height: ZSpacing.md),
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
          _ZaghlolWarn(
            text: l.budgetOverviewZaghlolWarn(
              name(hot.first),
              _percent(ref, context, hot.first.progress.percent!),
              data.daysRemaining,
              ref
                  .watch(
                    digitsModeProvider(
                      Localizations.localeOf(context).languageCode,
                    ),
                  )
                  .render('${data.daysRemaining}'),
            ),
          ),
        ],
        const SizedBox(height: ZSpacing.md),
        if (view.rows.isNotEmpty)
          ZCard(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.lg,
              vertical: ZSpacing.xs,
            ),
            child: Column(
              children: [
                for (var i = 0; i < view.rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: c.outline),
                  _CategoryRow(
                    name: name(view.rows[i]),
                    row: view.rows[i],
                    category: cats[view.rows[i].categoryId],
                    onTap: onCategoryTap == null
                        ? null
                        : () => onCategoryTap!(
                            view.rows[i].categoryId,
                            data.cycle,
                          ),
                  ),
                ],
              ],
            ),
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

/// Mockup 09: green below the warning line, apricot from it, terracotta at
/// or over the limit. The number next to the bar always says it in text.
Color _fillColor(ZColors c, int percent) => percent >= 95
    ? ZChartColors.spend
    : percent >= budgetWarnPercent
    ? c.accent
    : c.primary;

Color _percentColor(ZColors c, int percent) => percent >= 95
    ? c.dangerText
    : percent >= budgetWarnPercent
    ? c.warningText
    : c.textMuted;

/// Captain Zaghlol on the terracotta strip (shocked), text beside him. The
/// bird ignores pointers.
class _ZaghlolWarn extends StatelessWidget {
  const _ZaghlolWarn({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return ZCard(
      color: c.dangerBg,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: ZSpacing.md,
        vertical: ZSpacing.sm,
      ),
      child: Row(
        children: [
          const ZaghlolAvatar(moment: ZaghlolMoment.shocked, size: 72),
          const SizedBox(width: ZSpacing.sm),
          Expanded(
            child: Text(text, style: ZType.body.copyWith(color: c.text)),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final fill = percent.clamp(0, 100) / 100;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ZRadius.pill),
        child: SizedBox(
          height: ZSpacing.md,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: c.surfaceAlt)),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: fill,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _fillColor(c, percent),
                      borderRadius: BorderRadius.circular(ZRadius.pill),
                    ),
                    child: const SizedBox.expand(),
                  ),
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
    required this.category,
    required this.onTap,
  });

  final String name;
  final BudgetRowView row;
  final CategoryRow? category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final p = row.progress;
    final pct = p.percent ?? 0;
    final spent = _money(ref, context, p.spent);
    final limit = _money(ref, context, p.effectiveLimit);
    // The status words are for screen readers (the number and bar colour
    // already say it on screen, mockup 09).
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
    final label = l.budgetOverviewRowA11y(
      name,
      spent,
      limit,
      _percent(ref, context, pct),
    );
    return Semantics(
      button: onTap != null,
      excludeSemantics: true,
      label: status == null ? label : '$label. $status',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: ZSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, box) => Row(
                    children: [
                      CategoryTile(
                        iconKey: category?.icon,
                        colorHex: category?.color,
                        size: 40,
                      ),
                      const SizedBox(width: ZSpacing.md),
                      Expanded(
                        child: Text(
                          name,
                          style: ZType.titleSmall.copyWith(
                            color: c.text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: ZSpacing.sm),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: box.maxWidth * 0.55,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: trimCurrency(spent),
                                  style: ZType.label.copyWith(
                                    color: c.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text: ' / ${trimCurrency(limit)}   ',
                                  style: ZType.caption.copyWith(
                                    color: c.textMuted,
                                  ),
                                ),
                                TextSpan(
                                  text: _percent(ref, context, pct),
                                  style: ZType.label.copyWith(
                                    color: _percentColor(c, pct),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZSpacing.sm),
                _Bar(percent: pct),
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

/// Chevrons that follow the reading direction: `chevron_left` / `chevron_right`
/// mirror themselves in RTL (matchTextDirection), so no branching here.
IconData startChevron(BuildContext context) => Icons.chevron_left;

IconData endChevron(BuildContext context) => Icons.chevron_right;
