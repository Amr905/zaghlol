// T-102: S-25 Add / edit a bill, installment, card payment or gameya.
// Validation (spec): name 1-30, amount per its currency's exponent, next due
// required (may be future), paid <= total, total 1-120, reminder 0-30 days.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/money_columns.dart';
import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_chip.dart';
import '../../budget/application/budget_providers.dart' show todayProvider;
import '../data/recurring_repository.dart';
import 'bills_providers.dart';

const int maxBillName = 30;
const int maxBillTotal = 120;
const int maxBillReminder = 30;

const _currencies = ['EGP', 'USD', 'EUR', 'SAR', 'AED', 'KWD', 'GBP'];

class BillEditScreen extends ConsumerWidget {
  const BillEditScreen({super.key, this.itemId});

  /// Null = add.
  final String? itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final id = itemId;
    Widget body;
    if (id == null) {
      body = const BillForm();
    } else {
      final item = ref.watch(billItemProvider(id));
      body = item.hasError
          ? Center(child: Text(l.commonErrorLoadFailed))
          : !item.hasValue
          ? const Center(child: CircularProgressIndicator())
          : item.requireValue == null
          ? Center(child: Text(l.commonErrorLoadFailed))
          : BillForm(item: item.requireValue);
    }
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: Text(
          id == null
              ? l.recurringBillEditTitleAdd
              : l.recurringBillEditTitleEdit,
        ),
        leading: IconButton(
          tooltip: l.commonActionClose,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: body,
    );
  }
}

class BillForm extends ConsumerStatefulWidget {
  const BillForm({super.key, this.item});
  final RecurringItemRow? item;

  @override
  ConsumerState<BillForm> createState() => _BillFormState();
}

class _BillFormState extends ConsumerState<BillForm> {
  late String _kind;
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _paid;
  late final TextEditingController _total;
  late String _currency;
  late RecurrenceCadence _cadence;
  int? _cadenceDays;
  CivilDate? _due;
  late int _remind;
  bool _submitted = false;
  bool _saving = false;
  bool _saveFailed = false;

  bool get _editing => widget.item != null;
  bool get _counted =>
      _kind == RecurringKind.installment || _kind == RecurringKind.gameya;

  @override
  void initState() {
    super.initState();
    final r = widget.item;
    _kind = r?.kind ?? RecurringKind.subscription;
    _name = TextEditingController(text: r?.name ?? '');
    _amount = TextEditingController(
      text: r == null || r.amountMinor == 0 ? '' : r.amount.toCanonicalString(),
    );
    _paid = TextEditingController(text: '${r?.paidCount ?? 0}');
    _total = TextEditingController(text: r?.totalCount?.toString() ?? '');
    _currency = r?.currency ?? 'EGP';
    _cadence = switch (r?.cadence) {
      'yearly' => RecurrenceCadence.yearly,
      'weekly' => RecurrenceCadence.weekly,
      'custom_days' => RecurrenceCadence.customDays,
      _ => RecurrenceCadence.monthly,
    };
    _cadenceDays = r?.cadenceDays;
    _due = r == null ? null : CivilDate.tryParse(r.nextDueDate ?? '');
    _remind = r?.reminderDays ?? defaultReminderDays;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _paid.dispose();
    _total.dispose();
    super.dispose();
  }

  Money? get _money =>
      MoneyFormat.parseInput(_amount.text.trim(), Currency.of(_currency));

  int? _int(TextEditingController c) =>
      int.tryParse(normalizeDigits(c.text.trim()));

  int get _paidCount => _int(_paid) ?? 0;
  int? get _totalCount => _counted ? _int(_total) : null;

  bool get _paidBad =>
      _counted &&
      _totalCount != null &&
      (_paid.text.trim().isNotEmpty &&
          (_int(_paid) == null || _paidCount < 0 || _paidCount > _totalCount!));
  bool get _totalBad =>
      _counted &&
      (_totalCount == null || _totalCount! < 1 || _totalCount! > maxBillTotal);
  bool get _dueBad => _due == null;

  bool get _valid {
    final n = _name.text.trim();
    final m = _money;
    final okAmount =
        m != null &&
        (m.isPositive || (_kind == RecurringKind.cardDue && m.isZero));
    return n.isNotEmpty &&
        n.runes.length <= maxBillName &&
        okAmount &&
        !_dueBad &&
        !_paidBad &&
        !_totalBad;
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_valid || _saving) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await ref
          .read(billsActionsProvider)
          .save(
            BillDraft(
              kind: _kind,
              name: _name.text.trim(),
              amount: _money!,
              cadence: _cadence,
              cadenceDays: _cadence == RecurrenceCadence.customDays
                  ? _cadenceDays
                  : null,
              nextDue: _due!,
              totalCount: _counted ? _totalCount : null,
              paidCount: _counted ? _paidCount : 0,
              reminderDays: _remind,
              accountId: widget.item?.accountId,
            ),
            id: widget.item?.id,
          );
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.recurringBillEditSaved)));
        Navigator.of(context).pop();
      }
    } catch (_) {
      // Typed failures carry no user text; the entered values stay.
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
    }
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final name = widget.item!.name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.recurringBillEditDeleteTitle(name)),
        content: Text(l.recurringBillEditDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonActionDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(billsActionsProvider).delete(widget.item!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final today = ref.read(todayProvider);
    final initial = _due ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 11),
    );
    if (picked != null) {
      setState(() => _due = CivilDate(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final kinds = [
      (RecurringKind.subscription, l.recurringBillsKindSubscription),
      (RecurringKind.installment, l.recurringBillsKindInstallment),
      (RecurringKind.cardDue, l.recurringBillsKindCard),
      (RecurringKind.gameya, l.recurringBillsKindGameya),
    ];
    final cadences = [
      (RecurrenceCadence.monthly, l.commonCadenceMonthly),
      (RecurrenceCadence.weekly, l.commonCadenceWeekly),
      (RecurrenceCadence.yearly, l.commonCadenceYearly),
    ];
    final due = _due;
    final dueText = due == null
        ? l.recurringBillEditNextDue
        : ZDateFormat.date(
            DateTime.utc(due.year, due.month, due.day, 12),
            lang,
            digits,
          );
    Widget label(String t) => Padding(
      padding: const EdgeInsetsDirectional.only(
        top: ZSpacing.lg,
        bottom: ZSpacing.sm,
      ),
      child: Text(t, style: ZType.label.copyWith(color: c.textMuted)),
    );
    Widget error(String t) => Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
      child: Text(t, style: ZType.caption.copyWith(color: c.dangerText)),
    );
    final currencies = {..._currencies, _currency}.toList();
    return ListView(
      padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
      children: [
        label(l.recurringBillEditType),
        Wrap(
          spacing: ZSpacing.sm,
          runSpacing: ZSpacing.sm,
          children: [
            for (final k in kinds)
              ZChip(
                label: k.$2,
                selected: _kind == k.$1,
                onTap: () => setState(() => _kind = k.$1),
              ),
          ],
        ),
        label(l.recurringBillEditName),
        TextField(
          controller: _name,
          maxLength: maxBillName,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: l.recurringBillEditNamePlaceholder,
            counterText: '',
          ),
          onChanged: (_) => setState(() {}),
        ),
        label(l.recurringBillEditAmount),
        Row(
          children: [
            DropdownButton<String>(
              value: _currency,
              items: [
                for (final cur in currencies)
                  DropdownMenuItem(value: cur, child: Text(cur)),
              ],
              onChanged: (v) => setState(() => _currency = v ?? _currency),
            ),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textDirection: TextDirection.ltr,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        label(l.recurringBillEditRepeats),
        Wrap(
          spacing: ZSpacing.sm,
          runSpacing: ZSpacing.sm,
          children: [
            for (final k in cadences)
              ZChip(
                label: k.$2,
                selected: _cadence == k.$1,
                onTap: () => setState(() => _cadence = k.$1),
              ),
          ],
        ),
        label(l.recurringBillEditNextDue),
        ZButton(
          label: dueText,
          variant: ZButtonVariant.secondary,
          icon: Icons.event,
          expand: true,
          onPressed: _pickDate,
        ),
        if (_submitted && _dueBad) error(l.recurringBillEditErrorDue),
        if (_counted) ...[
          label(l.recurringBillEditPaid),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _paid,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: ZSpacing.md,
                ),
                child: Text(
                  l.recurringBillEditPaidOf,
                  style: ZType.body.copyWith(color: c.text),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _total,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (_submitted && _paidBad) error(l.recurringBillEditErrorPaid),
          if (_submitted && _totalBad)
            error(
              l.recurringBillEditErrorTotal(digits.render('$maxBillTotal')),
            ),
        ],
        label(l.recurringBillEditRemind(_remind, digits.render('$_remind'))),
        Slider(
          value: _remind.toDouble(),
          min: 0,
          max: maxBillReminder.toDouble(),
          divisions: maxBillReminder,
          semanticFormatterCallback: (v) => l.recurringBillEditRemind(
            v.round(),
            digits.render('${v.round()}'),
          ),
          onChanged: (v) => setState(() => _remind = v.round()),
        ),
        if (_saveFailed) error(l.commonErrorSaveFailed),
        const SizedBox(height: ZSpacing.xl),
        ZButton(
          label: l.commonActionSave,
          expand: true,
          loading: _saving,
          onPressed: _save,
        ),
        if (_editing) ...[
          const SizedBox(height: ZSpacing.md),
          ZButton(
            label: l.commonActionDelete,
            variant: ZButtonVariant.destructive,
            expand: true,
            onPressed: _delete,
          ),
        ],
        const SizedBox(height: ZSpacing.xl),
      ],
    );
  }
}
