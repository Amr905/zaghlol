// T-080: S-13 Add / edit transaction (FR-TXN-02/04, FR-CARD-05, FR-ACC-03).
//
// Also the Quick add target for "type it". The amount is parsed exactly from
// text (any digit script) into integer minor units; saving goes through
// [TxnEditorPort] (repository + own-transfer pairing + refund matching), so
// the screen never touches the database. Raw message text passed in is shown
// only on screen, never logged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/date_format.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_components.dart';
import '../../../../core/ui/shell/add_sheet.dart' show AddAction;
import '../../../budget/application/budget_providers.dart';
import '../../data/transactions_providers.dart';
import '../../domain/transaction.dart';
import '../detail/txn_detail_providers.dart';
import '../list/txn_list_providers.dart';
import '../list/txn_row.dart';
import 'txn_edit_providers.dart';
import 'txn_form.dart';

const int _msPerDay = 86400000;

/// Opens S-13 full screen over the current route. [existing] = edit mode;
/// [rawText] is shown for review when the message came from a share/paste.
Future<bool?> showTransactionEditor(
  BuildContext context, {
  TransactionRecord? existing,
  String? rawText,
  TxnEditType initialType = TxnEditType.expense,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => TransactionEditScreen(
        existing: existing,
        rawText: rawText,
        initialType: initialType,
      ),
    ),
  );
}

class TransactionEditScreen extends ConsumerStatefulWidget {
  const TransactionEditScreen({
    super.key,
    this.existing,
    this.rawText,
    this.initialType = TxnEditType.expense,
  });

  final TransactionRecord? existing;
  final String? rawText;
  final TxnEditType initialType;

  @override
  ConsumerState<TransactionEditScreen> createState() => _EditState();
}

class _EditState extends ConsumerState<TransactionEditScreen> {
  late TxnEditType _type;
  late final TextEditingController _amount;
  late final TextEditingController _merchant;
  late final TextEditingController _note;
  late Currency _currency;
  bool _currencyTouched = false;
  String? _categoryId;
  String? _accountId;
  String? _toAccountId;
  CivilDate? _date;
  bool _submitted = false;
  bool _saving = false;
  bool _failed = false;
  bool _dirty = false;
  Map<TxnField, TxnFormError> _errors = const {};

  TransactionRecord? get _existing => widget.existing;
  bool get _isEdit => _existing != null;
  bool get _isTransferEdit =>
      _isEdit &&
      (_existing!.direction == TxnDirection.transferOut ||
          _existing!.direction == TxnDirection.transferIn);

  @override
  void initState() {
    super.initState();
    final e = _existing;
    _type = e == null ? widget.initialType : _typeOf(e.direction);
    _currency = e?.amount.currency ?? Currency.of('EGP');
    _currencyTouched = e != null;
    _amount = TextEditingController(
      text: e == null ? '' : e.amount.abs().toCanonicalString(),
    );
    _merchant = TextEditingController(
      text: e == null ? '' : (e.merchantNorm ?? e.merchantRaw ?? ''),
    );
    _note = TextEditingController(text: e?.note ?? '');
    _categoryId = e?.categoryId;
    _accountId = e?.accountId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  static TxnEditType _typeOf(TxnDirection d) => switch (d) {
    TxnDirection.income || TxnDirection.refund => TxnEditType.income,
    TxnDirection.transferIn || TxnDirection.transferOut => TxnEditType.transfer,
    _ => TxnEditType.expense,
  };

  void _touch() {
    if (!_dirty) setState(() => _dirty = true); // PopScope must rebuild
    if (_submitted) _revalidate();
  }

  CivilDate _today() => ref.read(todayProvider);

  void _revalidate() {
    setState(() {
      _errors = validateForm(
        type: _type,
        amountText: _amount.text,
        currency: _currency,
        categoryId: _isTransferEdit ? 'n/a' : _categoryId,
        accountId: _accountId,
        toAccountId: _isTransferEdit ? null : _toAccountId,
        date: _date ?? _today(),
        today: _today(),
        note: _note.text,
      );
      if (_isTransferEdit) _errors = {..._errors}..remove(TxnField.to);
    });
  }

  void _setAccount(String id, TxnLookups lk) {
    setState(() {
      _accountId = id;
      final cur = Currency.tryOf(lk.account(id)?.currencyCode ?? '');
      if (!_currencyTouched && cur != null) _currency = cur;
      _touch();
    });
  }

  String _errorText(AppLocalizations l, TxnFormError e) => switch (e) {
    TxnFormError.amountRequired => l.commonValidationAmountRequired,
    TxnFormError.amountTooLarge => l.commonValidationAmountTooLarge,
    TxnFormError.amountDecimals => l.commonValidationAmountDecimals(
      _currency.exponent,
      _currency.code,
      '${_currency.exponent}',
    ),
    TxnFormError.categoryRequired => l.commonValidationCategoryRequired,
    TxnFormError.accountRequired ||
    TxnFormError.toAccountRequired => l.commonValidationAccountRequired,
    TxnFormError.sameAccount => l.transactionsEditSameAccount,
    TxnFormError.dateFuture => l.commonValidationDateFuture,
    TxnFormError.noteTooLong => l.commonValidationNoteLength(
      formNoteMaxChars,
      '$formNoteMaxChars',
    ),
  };

  /// The UTC instant for the chosen day: now when it is today, else noon.
  DateTime _instant(CivilDate date, int offsetMin) {
    if (date.epochDay == _today().epochDay) {
      return ref.read(clockProvider)().toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(
      date.epochDay * _msPerDay + 12 * 3600000 - offsetMin * 60000,
      isUtc: true,
    );
  }

  Future<void> _save() async {
    _submitted = true;
    _revalidate();
    if (_errors.isNotEmpty || _saving) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      final editor = await ref.read(transactionEditorProvider.future);
      final amount = parseAmount(_amount.text, _currency).money!;
      final nowMs = ref.read(clockProvider)().toUtc().millisecondsSinceEpoch;
      final offset = ref.read(localZoneProvider).offsetAtInstant(nowMs);
      final date = _date ?? _today();
      final merchant = _merchant.text.trim();
      final note = _note.text.trim();
      var removed = const <String>[];
      if (_isEdit) {
        final e = _existing!;
        final dateChanged = _date != null;
        final direction = _isTransferEdit || _typeOf(e.direction) == _type
            ? null
            : (_type == TxnEditType.income
                  ? TxnDirection.income
                  : TxnDirection.expense);
        final outcome = await editor.update(
          e.id,
          TransactionEdit(
            accountId: _accountId != e.accountId ? _accountId : null,
            direction: direction,
            amount: amount == e.amount.abs() ? null : amount,
            occurredAt: dateChanged ? _instant(date, offset) : null,
            occurredTzOffsetMin: dateChanged ? offset : null,
            categoryId: _isTransferEdit || _categoryId == e.categoryId
                ? null
                : Maybe(_categoryId),
            merchant: merchant == (e.merchantNorm ?? e.merchantRaw ?? '')
                ? null
                : Maybe(merchant.isEmpty ? null : merchant),
            note: note == (e.note ?? '')
                ? null
                : Maybe(note.isEmpty ? null : note),
          ),
        );
        removed = outcome.removedLinkIds;
        ref.invalidate(txnDetailProvider(e.id));
      } else {
        final at = _instant(date, offset);
        final isTransfer = _type == TxnEditType.transfer;
        final legs = <NewTransaction>[
          NewTransaction(
            accountId: _accountId!,
            direction: isTransfer
                ? TxnDirection.transferOut
                : (_type == TxnEditType.income
                      ? TxnDirection.income
                      : TxnDirection.expense),
            amount: amount,
            occurredAt: at,
            occurredTzOffsetMin: offset,
            categoryId: isTransfer ? null : _categoryId,
            merchant: merchant.isEmpty ? null : merchant,
            note: note.isEmpty ? null : note,
          ),
          // The incoming leg only when both accounts hold the same currency;
          // otherwise the out leg waits for its match (nothing is converted).
          if (isTransfer &&
              (ref
                      .read(txnLookupsProvider)
                      .value
                      ?.account(_toAccountId!)
                      ?.currencyCode ==
                  amount.currency.code))
            NewTransaction(
              accountId: _toAccountId!,
              direction: TxnDirection.transferIn,
              amount: amount,
              occurredAt: at,
              occurredTzOffsetMin: offset,
              note: note.isEmpty ? null : note,
            ),
        ];
        await editor.add(legs);
      }
      ref.invalidate(txnListProvider);
      if (removed.isNotEmpty) {
        // EC-40: some money-back / split links no longer fit the new amount.
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(l.transfersAssignErrorExceedsExpense)),
          );
      }
      navigator.pop(true);
    } on SafeException {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.commonDiscardTitle),
        content: Text(l.commonDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.commonDiscardKeep),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.commonDiscardConfirm),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _pickDate() async {
    final today = _today();
    final cur = _date ?? (_existing == null ? today : null);
    final base = cur ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month, base.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (picked == null) return;
    setState(() {
      _date = CivilDate(picked.year, picked.month, picked.day);
      _touch();
    });
  }

  Future<void> _pickCategory(TxnLookups lk, String lang) async {
    final l = AppLocalizations.of(context);
    final id = await showZSheet<String>(
      context: context,
      title: l.transactionsEditCategory,
      fullHeight: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in lk.categories)
            ZListRow(
              title: categoryName(c, lang),
              leading: Text(c.icon, style: ZType.title),
              onTap: () => Navigator.of(ctx).pop(c.id),
            ),
        ],
      ),
    );
    if (id != null) {
      setState(() {
        _categoryId = id;
        _touch();
      });
    }
  }

  Future<String?> _pickAccount(TxnLookups lk, TxnFmt fmt, String title) {
    return showZSheet<String>(
      context: context,
      title: title,
      fullHeight: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in lk.accounts)
            ZListRow(
              title: accountName(a, fmt),
              subtitle: a.currencyCode,
              onTap: () => Navigator.of(ctx).pop(a.id),
            ),
        ],
      ),
    );
  }

  Future<void> _pickCurrency() async {
    final l = AppLocalizations.of(context);
    final c = await showZSheet<Currency>(
      context: context,
      title: l.transactionsEditCurrency,
      fullHeight: true,
      builder: (ctx) => _CurrencyList(selected: _currency),
    );
    if (c != null) {
      setState(() {
        _currency = c;
        _currencyTouched = true;
        _touch();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final fmt = TxnFmt(lang, ref.watch(digitsModeProvider(lang)));
    final lk = ref.watch(txnLookupsProvider).value;
    final cash = ref.watch(defaultCashAccountIdProvider).value;
    if (_accountId == null && !_isEdit && lk != null) {
      // FR-ACC-03: Cash is the default account.
      final id = cash ?? (lk.accounts.isEmpty ? null : lk.accounts.first.id);
      if (id != null) {
        _accountId = id;
        final cur = Currency.tryOf(lk.account(id)?.currencyCode ?? '');
        if (cur != null) _currency = cur;
      }
    }
    final date = _date ?? _today();
    final isToday = date.epochDay == _today().epochDay;
    final dateText = _isEdit && _date == null
        ? ZDateFormat.date(_existing!.occurredAt, lang, fmt.digits)
        : isToday
        ? l.commonDateToday
        : ZDateFormat.date(
            DateTime(date.year, date.month, date.day),
            lang,
            fmt.digits,
          );
    final title = _isEdit
        ? l.transactionsEditTitleEdit
        : l.transactionsEditTitleAdd(_type.name);
    String? err(TxnField k) =>
        _errors[k] == null ? null : _errorText(l, _errors[k]!);

    final segments = <ZSegment<TxnEditType>>[
      ZSegment(value: TxnEditType.expense, label: l.commonTxnTypeExpense),
      ZSegment(value: TxnEditType.income, label: l.commonTxnTypeIncome),
      if (!_isEdit)
        ZSegment(value: TxnEditType.transfer, label: l.commonTxnTypeTransfer),
    ];
    final isTransfer = _type == TxnEditType.transfer;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: l.commonActionClose,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(title),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: ZSpacing.sm),
              child: ZButton(
                label: l.commonActionSave,
                size: ZButtonSize.small,
                variant: ZButtonVariant.text,
                loading: _saving,
                onPressed: lk == null ? null : _save,
              ),
            ),
          ],
        ),
        body: lk == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
                children: [
                  if (_failed)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        bottom: ZSpacing.md,
                      ),
                      child: ZBanner(
                        message: l.commonErrorSaveFailed,
                        tone: ZBannerTone.error,
                      ),
                    ),
                  if (widget.rawText != null) ...[
                    ZBanner(message: l.transactionsEditFromShared),
                    const SizedBox(height: ZSpacing.sm),
                    Semantics(
                      label: l.transactionsEditRawTitle,
                      child: Container(
                        padding: const EdgeInsetsDirectional.all(ZSpacing.md),
                        decoration: BoxDecoration(
                          color: c.surfaceAlt,
                          borderRadius: BorderRadius.circular(ZRadius.md),
                        ),
                        child: SelectableText(
                          widget.rawText!,
                          style: ZType.bodySmall.copyWith(
                            color: c.text,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: ZSpacing.lg),
                  ],
                  if (!_isTransferEdit) ...[
                    Semantics(
                      label: l.transactionsEditTypeA11y,
                      child: ZSegmentedControl<TxnEditType>(
                        segments: segments,
                        selected: _type,
                        onChanged: (t) => setState(() {
                          _type = t;
                          _touch();
                        }),
                      ),
                    ),
                    const SizedBox(height: ZSpacing.lg),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          top: ZSpacing.sm,
                          end: ZSpacing.md,
                        ),
                        child: ZChip(
                          label: _currency.code,
                          icon: Icons.arrow_drop_down,
                          onTap: _pickCurrency,
                        ),
                      ),
                      Expanded(
                        child: Semantics(
                          label: l.transactionsEditAmountA11y,
                          child: TextField(
                            controller: _amount,
                            autofocus: !_isEdit,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: amountInputFormatters,
                            style: ZType.display.copyWith(color: c.text),
                            onChanged: (_) => _touch(),
                            decoration: InputDecoration(
                              hintText: fmt.digits.render(
                                _currency.exponent == 0
                                    ? '0'
                                    : '0.${'0' * _currency.exponent}',
                              ),
                              errorText: err(TxnField.amount),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ZSpacing.md),
                  if (!_isTransferEdit && !isTransfer)
                    _SelectRow(
                      label: l.transactionsEditCategory,
                      value: lk.category(_categoryId) == null
                          ? l.transactionsEditChoose
                          : categoryName(lk.category(_categoryId)!, lang),
                      error: err(TxnField.category),
                      onTap: () => _pickCategory(lk, lang),
                    ),
                  if (!isTransfer || _isTransferEdit) ...[
                    TextField(
                      controller: _merchant,
                      onChanged: (_) => _touch(),
                      decoration: InputDecoration(
                        labelText: l.transactionsEditMerchant,
                      ),
                    ),
                    const SizedBox(height: ZSpacing.sm),
                  ],
                  _SelectRow(
                    label: isTransfer
                        ? l.transactionsEditFrom
                        : l.transactionsEditAccount,
                    value: lk.account(_accountId ?? '') == null
                        ? l.transactionsEditChoose
                        : accountName(lk.account(_accountId!)!, fmt),
                    error: err(TxnField.account),
                    onTap: () async {
                      final id = await _pickAccount(
                        lk,
                        fmt,
                        isTransfer
                            ? l.transactionsEditFrom
                            : l.transactionsEditAccount,
                      );
                      if (id != null) _setAccount(id, lk);
                    },
                  ),
                  if (isTransfer)
                    _SelectRow(
                      label: l.transactionsEditTo,
                      value: lk.account(_toAccountId ?? '') == null
                          ? l.transactionsEditChoose
                          : accountName(lk.account(_toAccountId!)!, fmt),
                      error: err(TxnField.to),
                      onTap: () async {
                        final id = await _pickAccount(
                          lk,
                          fmt,
                          l.transactionsEditTo,
                        );
                        if (id != null) {
                          setState(() {
                            _toAccountId = id;
                            _touch();
                          });
                        }
                      },
                    ),
                  _SelectRow(
                    label: l.transactionsEditDate,
                    value: dateText,
                    error: err(TxnField.date),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: ZSpacing.sm),
                  TextField(
                    controller: _note,
                    onChanged: (_) => _touch(),
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      labelText: l.transactionsEditNote,
                      errorText: err(TxnField.note),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.error,
  });

  final String label;
  final String value;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ZListRow(
          title: label,
          trailing: Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
          ),
          showChevron: true,
          onTap: onTap,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.lg,
            ),
            child: Text(
              error!,
              style: ZType.caption.copyWith(color: c.dangerText),
            ),
          ),
      ],
    );
  }
}

class _CurrencyList extends StatefulWidget {
  const _CurrencyList({required this.selected});
  final Currency selected;

  @override
  State<_CurrencyList> createState() => _CurrencyListState();
}

class _CurrencyListState extends State<_CurrencyList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final q = _q.trim().toUpperCase();
    final featured = [
      for (final code in Currency.featuredCodes) Currency.of(code),
    ];
    final rest = [
      for (final cur in Currency.all)
        if (!Currency.featuredCodes.contains(cur.code) && !cur.isFund) cur,
    ]..sort((a, b) => a.code.compareTo(b.code));
    bool hit(Currency x) => q.isEmpty || x.code.contains(q);
    Widget row(Currency x) => ZListRow(
      title: x.code,
      trailing: x == widget.selected
          ? Icon(Icons.check, color: c.primary)
          : null,
      onTap: () => Navigator.of(context).pop(x),
    );
    Widget header(String t) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ZSpacing.lg,
        ZSpacing.md,
        ZSpacing.lg,
        ZSpacing.xs,
      ),
      child: Text(t, style: ZType.label.copyWith(color: c.textMuted)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: l.transactionsEditCurrencySearch,
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        if (featured.any(hit)) header(l.transactionsEditCurrencyFeatured),
        for (final x in featured.where(hit)) row(x),
        if (rest.any(hit)) header(l.transactionsEditCurrencyAll),
        for (final x in rest.where(hit)) row(x),
      ],
    );
  }
}

/// The Quick add sheet's handler for "Type it" (S-30 -> S-13); other entries
/// are not this screen's business and only close the sheet. Pass it as
/// `TabRoots.addSelected`.
void quickAddSelected(BuildContext context, AddAction action) {
  final nav = Navigator.of(context, rootNavigator: true);
  nav.maybePop();
  if (action == AddAction.type) showTransactionEditor(context);
}
