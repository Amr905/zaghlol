// T-102: S-24 Bills & installments. Plugs into the Insights shell's Bills
// segment. KPI card, the detective's suggestion, an upcoming timeline with
// mark-paid, and the subscriptions-per-year list. Spending is ink, never red;
// overdue uses the danger text token plus words, so colour is not the only cue.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_card.dart';
import '../../insights/presentation/charts/chart_format.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import '../data/recurring_repository.dart';
import 'bill_edit_screen.dart';
import 'bills_providers.dart';
import 'bills_view.dart';

/// Shown as the zero amount when nothing is due.
final Currency _zeroCurrency = Currency.of('EGP');

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(billsDataProvider);
    // Keep showing the last list while a refresh runs.
    if (data.hasError && !data.hasValue) {
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
              ZButton(
                label: l.commonActionTryAgain,
                onPressed: () => ref.invalidate(billsDataProvider),
              ),
            ],
          ),
        ),
      );
    }
    if (!data.hasValue) {
      // No generic loading label in the copy deck yet (see T-102 notes).
      return const Center(child: CircularProgressIndicator());
    }
    return _Body(data: data.requireValue);
  }
}

void openBillEditor(BuildContext context, {String? itemId}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BillEditScreen(itemId: itemId),
    ),
  );
}

class _Fmt {
  _Fmt(this.context, WidgetRef ref)
    : lang = Localizations.localeOf(context).languageCode {
    digits = ref.watch(digitsModeProvider(lang));
  }
  final BuildContext context;
  final String lang;
  late final DigitsMode digits;

  String money(Money m) => trimZeroFraction(
    MoneyFormat.format(m, languageCode: lang, digits: digits),
  );

  String num(int n) => digits.render('$n');

  String date(CivilDate d) =>
      ZDateFormat.date(DateTime.utc(d.year, d.month, d.day, 12), lang, digits);

  /// Day of month and month name for the date column of a row.
  (String, String) dayMonth(CivilDate d) => (
    digits.render('${d.day}'),
    DateFormat.MMMM(lang).format(DateTime(d.year, d.month)),
  );

  String moneyList(List<Money> list, Currency fallback) =>
      list.isEmpty ? money(Money.zero(fallback)) : list.map(money).join(' + ');
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});
  final BillsViewData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final f = _Fmt(context, ref);
    final c = ZColors.of(context);
    if (data.isEmpty) {
      return ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          ZSpacing.screen,
          ZSpacing.screen,
          ZSpacing.screen,
          ZSpacing.fabClearance,
        ),
        children: [
          const SizedBox(height: ZSpacing.xl),
          Text(
            l.recurringBillsEmptyTitle,
            textAlign: TextAlign.center,
            style: ZType.title.copyWith(color: c.text),
          ),
          const SizedBox(height: ZSpacing.sm),
          Text(
            l.recurringBillsEmptyBody,
            textAlign: TextAlign.center,
            style: ZType.body.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.xl),
          ZButton(
            label: l.recurringBillsAdd,
            expand: true,
            onPressed: () => openBillEditor(context),
          ),
        ],
      );
    }
    final subsYearly = [for (final t in data.subTotals) t.yearly];
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ZSpacing.screen,
        ZSpacing.screen,
        ZSpacing.screen,
        ZSpacing.fabClearance,
      ),
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Kpi(
                  label: l.recurringBillsKpiDue,
                  value: f.moneyList(data.dueThisMonth, _zeroCurrency),
                ),
              ),
              const SizedBox(width: ZSpacing.md),
              Expanded(
                child: _Kpi(
                  label: l.recurringBillsKpiSubs,
                  value: f.moneyList(subsYearly, _zeroCurrency),
                ),
              ),
            ],
          ),
        ),
        for (final s in data.suggestions) ...[
          const SizedBox(height: ZSpacing.md),
          _SuggestionCard(view: s, f: f),
        ],
        const SizedBox(height: ZSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  l.recurringBillsUpcoming,
                  style: ZType.title.copyWith(color: c.text),
                ),
              ),
            ),
            ZButton(
              label: l.recurringBillsAddShort,
              icon: Icons.add,
              variant: ZButtonVariant.text,
              onPressed: () => openBillEditor(context),
            ),
          ],
        ),
        const SizedBox(height: ZSpacing.sm),
        if (data.upcoming.isNotEmpty)
          ZCard(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.lg,
              vertical: ZSpacing.xs,
            ),
            child: Column(
              children: [
                for (var i = 0; i < data.upcoming.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: c.outline),
                  _BillRow(view: data.upcoming[i], f: f),
                ],
              ],
            ),
          ),
        if (data.subscriptions.isNotEmpty) ...[
          const SizedBox(height: ZSpacing.lg),
          _Subscriptions(data: data, f: f),
        ],
        const SizedBox(height: ZSpacing.xl),
      ],
    );
  }
}

/// One KPI card: muted label over a bold amount (mockup 10).
class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return ZCard(
      padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
      child: Semantics(
        container: true,
        label: '$label: $value',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: ZType.bodySmall.copyWith(color: c.textMuted)),
            const SizedBox(height: ZSpacing.xs),
            Text(
              value,
              style: ZType.title.copyWith(
                color: c.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({required this.view, required this.f});
  final SuggestionView view;
  final _Fmt f;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final actions = ref.read(billsActionsProvider);
    return ZCard(
      color: c.zaghlolBg,
      padding: const EdgeInsetsDirectional.all(ZSpacing.md),
      child: Row(
        children: [
          const ZaghlolAvatar(moment: ZaghlolMoment.detective, size: 88),
          const SizedBox(width: ZSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.recurringBillsDetected(view.name, f.money(view.amount)),
                  style: ZType.body.copyWith(color: c.text),
                ),
                const SizedBox(height: ZSpacing.sm),
                Wrap(
                  spacing: ZSpacing.sm,
                  runSpacing: ZSpacing.sm,
                  children: [
                    ZButton(
                      label: l.recurringBillsTrack,
                      size: ZButtonSize.small,
                      onPressed: () => actions.accept(view.id),
                    ),
                    ZButton(
                      label: l.recurringBillsNotSub,
                      variant: ZButtonVariant.secondary,
                      size: ZButtonSize.small,
                      onPressed: () => actions.dismiss(view.id),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BillRow extends ConsumerWidget {
  const _BillRow({required this.view, required this.f});
  final BillRowView view;
  final _Fmt f;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final title = view.name;
    final timing = switch (view.timing) {
      BillTiming.overdue => l.recurringBillsOverdue(
        -view.daysUntil,
        f.num(-view.daysUntil),
      ),
      BillTiming.today => l.recurringBillsDueToday,
      BillTiming.upcoming => l.recurringBillsDueIn(
        view.daysUntil,
        f.num(view.daysUntil),
      ),
    };
    final overdue = view.timing == BillTiming.overdue;
    final detail = switch (view.kind) {
      RecurringKind.cardDue => l.recurringBillsKindCard,
      RecurringKind.gameya when view.hasPlan => l.recurringBillsGameyaMonth(
        f.num(view.index),
        f.num(view.totalCount!),
      ),
      RecurringKind.subscription => null,
      _ when view.hasPlan =>
        view.isLast
            ? l.recurringBillsLastOne
            : l.recurringBillsInstallmentOf(
                f.num(view.index),
                f.num(view.totalCount!),
              ),
      _ => null,
    };
    // Overdue and due-today say so in words next to the date; the date
    // column already carries "in N days".
    final sub = [
      ?detail,
      if (view.timing != BillTiming.upcoming) timing,
    ].join(' · ');
    final amount = f.money(view.amount);
    final (day, month) = f.dayMonth(view.due);
    // Long pill labels (English) or large text: the pill drops below the row.
    final big =
        MediaQuery.textScalerOf(context).scale(16) > 18.5 ||
        l.recurringBillsMarkPaid.length > 6;
    final a11yExtra = view.kind == RecurringKind.gameya
        ? '. ${l.recurringBillsGameyaManual}'
        : '';
    final pill = _PaidPill(
      label: l.recurringBillsMarkPaid,
      onTap: () async {
        final ok = await ref.read(billsActionsProvider).markPaid(view.id);
        if (ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.recurringBillsPaidSnack(view.name))),
          );
        }
      },
    );
    return Semantics(
      container: true,
      label: l.recurringBillsRowA11y(title, amount, timing) + a11yExtra,
      child: InkWell(
        onTap: () => openBillEditor(context, itemId: view.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: ZSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // The row's Semantics label says it all (FU-217a): the visual
                    // pieces stay out of the tree so it reads once.
                    ExcludeSemantics(
                      child: SizedBox(
                        width: 56,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              day,
                              style: ZType.title.copyWith(
                                color: overdue ? c.dangerText : c.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              month,
                              style: ZType.caption.copyWith(color: c.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: ZType.titleSmall.copyWith(
                                color: c.text,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (sub.isNotEmpty)
                              Text(
                                sub,
                                style: ZType.caption.copyWith(
                                  color: overdue ? c.dangerText : c.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: ZSpacing.sm),
                    ExcludeSemantics(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            amount,
                            style: ZType.titleSmall.copyWith(
                              color: c.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (view.canMarkPaid && !big) ...[
                      const SizedBox(width: ZSpacing.sm),
                      pill,
                    ],
                  ],
                ),
                if (view.canMarkPaid && big)
                  Align(alignment: AlignmentDirectional.centerEnd, child: pill),
                if (view.autoAdded)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                    child: Wrap(
                      spacing: ZSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _AutoAddedBadge(label: l.recurringBillsAutoAdded),
                        ZButton(
                          label: l.recurringBillsNotABill,
                          variant: ZButtonVariant.text,
                          onPressed: () async {
                            final actions = ref.read(billsActionsProvider);
                            final messenger = ScaffoldMessenger.of(context);
                            final ok = await actions.notABill(view.id);
                            if (ok && context.mounted) {
                              messenger.hideCurrentSnackBar();
                              messenger.showSnackBar(
                                SnackBar(
                                  duration: const Duration(seconds: 6),
                                  content: Text(
                                    l.recurringBillsNotABillDone(view.name),
                                  ),
                                  action: SnackBarAction(
                                    label: l.commonActionUndo,
                                    onPressed: () =>
                                        actions.undoNotABill(view.id),
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
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

/// "Added by itself" tag on an auto-added bill (T-196, D-72). The word is
/// the cue; the colour only supports it.
class _AutoAddedBadge extends StatelessWidget {
  const _AutoAddedBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.primaryContainer,
        borderRadius: BorderRadius.circular(ZRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.md,
          vertical: ZSpacing.xs,
        ),
        child: Text(label, style: ZType.caption.copyWith(color: c.primary)),
      ),
    );
  }
}

/// The mint "paid" pill at the end of a bill row.
class _PaidPill extends StatelessWidget {
  const _PaidPill({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final shape = BorderRadius.circular(ZRadius.pill);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: c.primaryContainer,
        borderRadius: shape,
        child: InkWell(
          borderRadius: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ZSpacing.minTarget,
              minWidth: ZSpacing.minTarget,
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: ZSpacing.lg,
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: ZType.titleSmall.copyWith(color: c.primary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Subscriptions extends StatelessWidget {
  const _Subscriptions({required this.data, required this.f});
  final BillsViewData data;
  final _Fmt f;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l.recurringBillsSubsTitle,
              style: ZType.title.copyWith(color: c.text),
            ),
          ),
          Text(
            l.recurringBillsSubsYear,
            style: ZType.caption.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.md),
          for (final s in data.subscriptions)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name, style: ZType.body.copyWith(color: c.text)),
                  Text(
                    l.recurringBillsSubRow(
                      f.money(s.monthly),
                      f.money(s.yearly),
                    ),
                    style: ZType.caption.copyWith(color: c.textMuted),
                  ),
                ],
              ),
            ),
          const Divider(),
          for (final t in data.subTotals)
            Text(
              l.recurringBillsSubsTotal(f.money(t.monthly), f.money(t.yearly)),
              style: ZType.titleSmall.copyWith(color: c.text),
            ),
        ],
      ),
    );
  }
}
