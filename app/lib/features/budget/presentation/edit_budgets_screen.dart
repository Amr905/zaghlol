// T-101: S-23 Edit budgets. One currency at a time (FR-BUD-02); limits per
// category, two alert thresholds, roll-over. Blank or zero = no budget.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/budgets_dao.dart';
import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_chip.dart';
import '../application/budget_providers.dart';
import 'budget_screen.dart' show endChevron;
import 'budget_view.dart' show defaultBudgetCurrency;
import 'budget_edit_draft.dart';
import 'budget_providers_ui.dart';
import 'budget_saver.dart';

class EditBudgetsScreen extends ConsumerStatefulWidget {
  const EditBudgetsScreen({
    super.key,
    required this.initialCurrency,
    this.onPayday,
    this.onAnnual,
  });

  final Currency initialCurrency;

  /// S-72 payday stepper; the row is hidden when null.
  final VoidCallback? onPayday;

  /// Annual budgets list; the row is hidden when null.
  final VoidCallback? onAnnual;

  @override
  ConsumerState<EditBudgetsScreen> createState() => _EditBudgetsScreenState();
}

class _EditBudgetsScreenState extends ConsumerState<EditBudgetsScreen> {
  late Currency _currency = widget.initialCurrency;
  bool _dirty = false;

  Future<bool> _confirmDiscard() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.commonDiscardTitle),
        content: Text(l.commonDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonDiscardKeep),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDiscardConfirm),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _requestClose() async {
    if (!_dirty || await _confirmDiscard()) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _switchCurrency(Currency c) async {
    if (c == _currency) return;
    if (_dirty && !await _confirmDiscard()) return;
    setState(() {
      _currency = c;
      _dirty = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final rows = ref.watch(cycleBudgetRowsProvider);
    final cats = ref.watch(categoryRowsProvider);
    final currencies = <Currency>{
      defaultBudgetCurrency,
      widget.initialCurrency,
      ...?rows.value?.map((r) => Currency.of(r.currency)),
    }.toList()..sort((a, b) => a.code.compareTo(b.code));
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          title: Text(l.budgetEditTitle),
          leading: IconButton(
            tooltip: l.commonActionClose,
            icon: const Icon(Icons.close),
            onPressed: _requestClose,
          ),
        ),
        body: rows.hasError || cats.hasError
            ? Center(child: Text(l.commonErrorLoadFailed))
            : !rows.hasValue || !cats.hasValue
            ? Semantics(
                label: l.budgetOverviewLoadingA11y,
                child: const Center(child: CircularProgressIndicator()),
              )
            : _Form(
                key: ValueKey(_currency.code),
                currency: _currency,
                currencies: currencies,
                onCurrency: _switchCurrency,
                existing: [
                  for (final r in rows.requireValue)
                    if (r.currency == _currency.code) r,
                ],
                categories: cats.requireValue,
                onDirty: () {
                  if (!_dirty) setState(() => _dirty = true);
                },
                onSaved: () {
                  ref.read(budgetEditVersionProvider.notifier).bump();
                  ref.invalidate(currentCycleOverviewProvider);
                  Navigator.of(context).pop();
                },
                onPayday: widget.onPayday,
                onAnnual: widget.onAnnual,
              ),
      ),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({
    super.key,
    required this.currency,
    required this.currencies,
    required this.onCurrency,
    required this.existing,
    required this.categories,
    required this.onDirty,
    required this.onSaved,
    required this.onPayday,
    required this.onAnnual,
  });

  final Currency currency;
  final List<Currency> currencies;
  final ValueChanged<Currency> onCurrency;
  final List<BudgetRow> existing;
  final List<CategoryRow> categories;
  final VoidCallback onDirty;
  final VoidCallback onSaved;
  final VoidCallback? onPayday;
  final VoidCallback? onAnnual;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final Map<String, TextEditingController> _cats;
  late final TextEditingController _total;
  late final TextEditingController _first;
  late final TextEditingController _second;
  late bool _useTotal;
  late bool _rollover;
  Map<String, BudgetEditError> _errors = {};
  bool _saveFailed = false;
  bool _saving = false;

  /// Prefill in ASCII digits; typed Arabic-Indic digits are normalized on
  /// parse.
  String _text(BudgetRow? r) => r == null
      ? ''
      : Money.fromStorage(r.limitMinor, r.currency).toCanonicalString();

  @override
  void initState() {
    super.initState();
    final byCat = {for (final r in widget.existing) r.categoryId: r};
    _cats = {
      for (final c in widget.categories)
        c.id: TextEditingController(text: _text(byCat[c.id])),
    };
    final overall = byCat[null];
    _useTotal = overall != null;
    _total = TextEditingController(text: _text(overall));
    final th = widget.existing.isEmpty
        ? defaultBudgetThresholds
        : _thresholdsOf(widget.existing.first);
    _first = TextEditingController(text: '${th.first}');
    _second = TextEditingController(text: '${th.last}');
    _rollover = widget.existing.any((r) => r.rollover != 0);
  }

  List<int> _thresholdsOf(BudgetRow r) {
    try {
      final t = budgetThresholdsOf(r);
      return t.length >= 2 ? [t.first, t.last] : defaultBudgetThresholds;
    } on FormatException {
      return defaultBudgetThresholds;
    }
  }

  @override
  void dispose() {
    for (final c in _cats.values) {
      c.dispose();
    }
    _total.dispose();
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  BudgetDraft _draft() => BudgetDraft(
    currency: widget.currency,
    useTotal: _useTotal,
    totalText: _total.text,
    categoryTexts: {for (final e in _cats.entries) e.key: e.value.text},
    first: int.tryParse(normalizeDigits(_first.text)),
    second: int.tryParse(normalizeDigits(_second.text)),
    rollover: _rollover,
  );

  Future<void> _save() async {
    final draft = _draft();
    final errors = validateDraft(draft);
    setState(() {
      _errors = errors;
      _saveFailed = false;
    });
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      final save = await ref.read(budgetSaverProvider.future);
      await save(widget.currency, validated(draft), _rollover);
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.budgetEditSaved)));
      widget.onSaved();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
    }
  }

  String? _errorText(AppLocalizations l, String key) {
    final e = _errors[key];
    return switch (e) {
      null => null,
      BudgetEditError.limitNegative ||
      BudgetEditError.limitInvalid => l.budgetEditErrorLimit,
      BudgetEditError.thresholdRange => l.budgetEditErrorThreshold(
        '$budgetMinThreshold',
        '$budgetMaxThreshold',
      ),
      BudgetEditError.thresholdOrder => l.budgetEditErrorOrder,
    };
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String errorKey,
    bool percent = false,
    String? hint,
  }) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹.٫,٬]')),
          ],
          onChanged: (_) => widget.onDirty(),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            errorText: _errorText(l, errorKey),
            suffixText: percent ? '%' : widget.currency.code,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final payday = widget.onPayday == null
        ? null
        : ref.watch(paydayDayProvider).value;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ZSpacing.screen,
        ZSpacing.sm,
        ZSpacing.screen,
        ZSpacing.xxl,
      ),
      children: [
        Semantics(
          label: l.budgetEditCurrency,
          container: true,
          child: Wrap(
            spacing: ZSpacing.sm,
            runSpacing: ZSpacing.sm,
            children: [
              for (final cur in widget.currencies)
                ZChip(
                  label: cur.code,
                  selected: cur == widget.currency,
                  onTap: () => widget.onCurrency(cur),
                ),
            ],
          ),
        ),
        const SizedBox(height: ZSpacing.lg),
        Text(
          l.budgetEditOverall,
          style: ZType.titleSmall.copyWith(color: c.text),
        ),
        RadioGroup<bool>(
          groupValue: _useTotal,
          onChanged: (v) => setState(() {
            _useTotal = v ?? false;
            widget.onDirty();
          }),
          child: Column(
            children: [
              RadioListTile<bool>(
                value: false,
                title: Text(l.budgetEditOverallSum),
              ),
              RadioListTile<bool>(
                value: true,
                title: Text(l.budgetEditOverallSet),
              ),
            ],
          ),
        ),
        if (_useTotal)
          _field(
            controller: _total,
            label: l.budgetEditOverallSet,
            errorKey: budgetTotalKey,
          ),
        const SizedBox(height: ZSpacing.md),
        Text(
          l.budgetEditCategories,
          style: ZType.titleSmall.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.sm),
        for (final cat in widget.categories)
          _field(
            controller: _cats[cat.id]!,
            label: lang == 'ar' ? cat.nameAr : cat.nameEn,
            errorKey: cat.id,
            hint: l.budgetEditLimitHint,
          ),
        const SizedBox(height: ZSpacing.md),
        Text(
          l.budgetEditAlerts,
          style: ZType.titleSmall.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                controller: _first,
                label: l.budgetEditAlertFirst,
                errorKey: budgetFirstKey,
                percent: true,
              ),
            ),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: _field(
                controller: _second,
                label: l.budgetEditAlertSecond,
                errorKey: budgetSecondKey,
                percent: true,
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsetsDirectional.zero,
          title: Text(l.budgetEditRollover),
          subtitle: Text(l.budgetEditRolloverHint),
          value: _rollover,
          onChanged: (v) => setState(() {
            _rollover = v;
            widget.onDirty();
          }),
        ),
        if (widget.onAnnual != null)
          ListTile(
            contentPadding: EdgeInsetsDirectional.zero,
            minTileHeight: ZSpacing.minTarget,
            title: Text(l.budgetEditAnnual),
            subtitle: Text(l.budgetEditAnnualHint),
            trailing: Icon(endChevron(context)),
            onTap: widget.onAnnual,
          ),
        if (widget.onPayday != null)
          ListTile(
            contentPadding: EdgeInsetsDirectional.zero,
            minTileHeight: ZSpacing.minTarget,
            title: Text(l.budgetEditPayday),
            subtitle: payday == null
                ? null
                : Text(ref.watch(digitsModeProvider(lang)).render('$payday')),
            trailing: Icon(endChevron(context)),
            onTap: widget.onPayday,
          ),
        if (_saveFailed)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
            child: Text(
              l.commonErrorSaveFailed,
              style: ZType.bodySmall.copyWith(color: c.dangerText),
            ),
          ),
        ZButton(
          label: l.commonActionSave,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
