// T-102: S-24 Bills & installments. Plugs into the Insights shell's Bills
// segment. KPI card, the detective's suggestion, an upcoming timeline with
// mark-paid, and the subscriptions-per-year list. Spending is ink, never red;
// overdue uses the danger text token plus words, so colour is not the only cue.

import 'package:flutter/material.dart';
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

  String money(Money m) =>
      MoneyFormat.format(m, languageCode: lang, digits: digits);

  String num(int n) => digits.render('$n');

  String date(CivilDate d) =>
      ZDateFormat.date(DateTime.utc(d.year, d.month, d.day, 12), lang, digits);

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
        padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
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
    final subsMonthly = [for (final t in data.subTotals) t.monthly];
    return ListView(
      padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
      children: [
        ZCard(
          child: Semantics(
            container: true,
            child: Text(
              l.recurringBillsSummary(
                f.moneyList(data.dueThisMonth, _zeroCurrency),
                f.moneyList(subsMonthly, _zeroCurrency),
              ),
              style: ZType.titleSmall.copyWith(color: c.text),
            ),
          ),
        ),
        for (final s in data.suggestions) ...[
          const SizedBox(height: ZSpacing.md),
          _SuggestionCard(view: s, f: f),
        ],
        if (data.upcoming.isNotEmpty) ...[
          const SizedBox(height: ZSpacing.xl),
          Semantics(
            header: true,
            child: Text(
              l.recurringBillsUpcoming,
              style: ZType.title.copyWith(color: c.text),
            ),
          ),
          const SizedBox(height: ZSpacing.sm),
          for (final b in data.upcoming) ...[
            _BillRow(view: b, f: f),
            const SizedBox(height: ZSpacing.sm),
          ],
        ],
        if (data.subscriptions.isNotEmpty) ...[
          const SizedBox(height: ZSpacing.lg),
          _Subscriptions(data: data, f: f),
        ],
        const SizedBox(height: ZSpacing.lg),
        ZButton(
          label: l.recurringBillsAdd,
          variant: ZButtonVariant.secondary,
          expand: true,
          onPressed: () => openBillEditor(context),
        ),
        const SizedBox(height: ZSpacing.xl),
      ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.recurringBillsDetected(view.name, f.money(view.amount)),
            style: ZType.body.copyWith(color: c.text),
          ),
          const SizedBox(height: ZSpacing.md),
          Wrap(
            spacing: ZSpacing.sm,
            runSpacing: ZSpacing.sm,
            children: [
              ZButton(
                label: l.recurringBillsTrack,
                onPressed: () => actions.accept(view.id),
              ),
              ZButton(
                label: l.recurringBillsNotSub,
                variant: ZButtonVariant.secondary,
                onPressed: () => actions.dismiss(view.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _kindIcon(String kind) => switch (kind) {
  RecurringKind.subscription => Icons.autorenew,
  RecurringKind.installment => Icons.payments_outlined,
  RecurringKind.cardDue => Icons.credit_card,
  RecurringKind.gameya => Icons.groups_outlined,
  _ => Icons.receipt_long_outlined,
};

class _BillRow extends ConsumerWidget {
  const _BillRow({required this.view, required this.f});
  final BillRowView view;
  final _Fmt f;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final title = view.hasPlan && view.kind != RecurringKind.subscription
        ? l.recurringBillsInstallmentRow(
            view.name,
            f.num(view.index),
            f.num(view.totalCount!),
          )
        : view.name;
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
    final extra = <String>[
      if (view.isLast && view.kind != RecurringKind.subscription)
        l.recurringBillsLastOne,
      if (view.kind == RecurringKind.gameya) l.recurringBillsGameyaManual,
    ];
    final amount = f.money(view.amount);
    return Semantics(
      container: true,
      label: l.recurringBillsRowA11y(title, amount, timing),
      child: ZCard(
        padding: const EdgeInsetsDirectional.all(ZSpacing.md),
        onTap: () => openBillEditor(context, itemId: view.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(_kindIcon(view.kind), color: c.primary),
                ),
                const SizedBox(width: ZSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: ZType.body.copyWith(color: c.text)),
                      Text(
                        '${f.date(view.due)} · $timing',
                        style: ZType.caption.copyWith(
                          color: overdue ? c.dangerText : c.textMuted,
                        ),
                      ),
                      for (final e in extra)
                        Text(
                          e,
                          style: ZType.caption.copyWith(color: c.textMuted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: ZSpacing.sm),
                Text(
                  amount,
                  style: ZType.body.copyWith(
                    color: c.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (view.canMarkPaid)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: ZButton(
                  label: l.recurringBillsMarkPaid,
                  variant: ZButtonVariant.text,
                  onPressed: () async {
                    final ok = await ref
                        .read(billsActionsProvider)
                        .markPaid(view.id);
                    if (ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l.recurringBillsPaidSnack(view.name)),
                        ),
                      );
                    }
                  },
                ),
              ),
          ],
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
