// T-085: S-43 card details form (mockup 30), used to create a card (after the
// type and bank steps) and to edit one. Merge and hide live here too.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/db/daos/capture_controls_dao.dart';
import '../../../../core/l10n/digits_mode.dart' show DigitsMode;
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_banner.dart';
import '../../../../core/ui/z_button.dart';
import '../../../../core/ui/z_card.dart';
import '../../data/accounts_providers.dart';
import '../../domain/account.dart';
import 'card_form_logic.dart';
import 'edit_card_providers.dart';
import 'merge_flow.dart';

/// Maps Arabic-Indic digits to ASCII as the user types (CLAUDE.md §2.5).
class NormalizeDigitsFormatter extends TextInputFormatter {
  const NormalizeDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = normalizeDigits(newValue.text).replaceAll('٫', '.');
    if (t == newValue.text) return newValue;
    return newValue.copyWith(
      text: t,
      selection: TextSelection.collapsed(
        offset: newValue.selection.baseOffset.clamp(0, t.length),
      ),
    );
  }
}

class CardDetailsScreen extends ConsumerStatefulWidget {
  /// Create mode: [kind] and [institution] come from the earlier steps.
  const CardDetailsScreen.create({
    super.key,
    required AccountKind this.kind,
    required InstitutionOption this.institution,
    this.onSaved,
    this.onOpenExisting,
  }) : account = null,
       onOpenCapture = null;

  /// Edit mode.
  const CardDetailsScreen.edit({
    super.key,
    required Account this.account,
    this.onSaved,
    this.onOpenExisting,
    this.onOpenCapture,
  }) : kind = null,
       institution = null;

  final Account? account;
  final AccountKind? kind;
  final InstitutionOption? institution;

  /// Called with the saved account (create: the shell opens S-41).
  final void Function(Account account)? onSaved;

  /// "This card already exists - open it?"
  final void Function(Account existing)? onOpenExisting;

  /// "What Zaghlol reads" (S-62).
  final void Function(Account account)? onOpenCapture;

  bool get isEdit => account != null;

  @override
  ConsumerState<CardDetailsScreen> createState() => _CardDetailsState();
}

class _CardDetailsState extends ConsumerState<CardDetailsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _last4;
  late final TextEditingController _limit;
  late final TextEditingController _dueDay;
  late AccountKind _kind;
  late String _currency;
  var _taken = <String>[];
  var _touched = false;
  var _saving = false;
  var _saveFailed = false;
  late bool _hidden;
  Account? _duplicate;
  final Set<String> _off = {};

  Account? get _acc => widget.account;

  @override
  void initState() {
    super.initState();
    final a = _acc;
    _kind = a?.kind ?? widget.kind!;
    _currency =
        a?.defaultCurrency.code ?? widget.institution!.defaultCurrency.code;
    _name = TextEditingController(text: a?.label ?? '');
    _last4 = TextEditingController(text: a?.last4 ?? '');
    _limit = TextEditingController(
      text: a?.creditLimit == null ? '' : _plain(a!.creditLimit!),
    );
    _dueDay = TextEditingController(text: a?.statementDueDay?.toString() ?? '');
    _hidden = a?.isHidden ?? false;
    _loadTaken();
  }

  static String _plain(Money m) => m.toCanonicalString();

  Future<void> _loadTaken() async {
    final repo = await ref.read(accountsRepositoryProvider.future);
    final all = await repo.list(includeHidden: true);
    if (!mounted) return;
    setState(() {
      _taken = [
        for (final a in all)
          if (a.id != _acc?.id) a.label,
      ];
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _last4.dispose();
    _limit.dispose();
    _dueDay.dispose();
    super.dispose();
  }

  Currency get _cur => Currency.tryOf(_currency) ?? Currency.of('EGP');

  CardFormErrors get _errors => validateCardForm(
    name: _name.text,
    last4: _last4.text,
    limit: _limit.text,
    dueDay: _dueDay.text,
    kind: _kind,
    currency: _cur,
    takenNames: _taken,
    editingLast4: !widget.isEdit,
  );

  Future<void> _save() async {
    if (_saving || !_errors.isValid) {
      setState(() => _touched = true);
      return;
    }
    setState(() {
      _saving = true;
      _saveFailed = false;
      _duplicate = null;
    });
    try {
      final repo = await ref.read(accountsRepositoryProvider.future);
      final Account saved;
      if (widget.isEdit) {
        saved = await saveCardEdit(
          repo,
          _acc!,
          name: _name.text,
          kind: _kind,
          limit: _limit.text,
          dueDay: _dueDay.text,
        );
      } else {
        final r = await createCard(
          repo,
          institutionCode: widget.institution!.code,
          name: _name.text,
          last4: _last4.text,
          kind: _kind,
          currency: _cur,
          limit: _limit.text,
          dueDay: _dueDay.text,
        );
        if (r.duplicateOf != null) {
          if (mounted) {
            setState(() {
              _duplicate = r.duplicateOf;
              _saving = false;
            });
          }
          return;
        }
        saved = r.account;
        await _applyCapture(saved);
      }
      if (saved.kind == AccountKind.credit && saved.statementDueDay != null) {
        await syncCardDues(ref);
      }
      if (!mounted) return;
      widget.onSaved?.call(saved);
    } on Object {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyCapture(Account saved) async {
    final port = ref.read(cardCapturePortProvider);
    if (port == null || _off.isEmpty) return;
    await port.turnOff(
      institutionCode: saved.institutionCode ?? widget.institution!.code,
      last4: saved.last4,
      offChannels: Set.of(_off),
    );
  }

  Future<void> _toggleHidden(bool v) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _hidden = v);
    try {
      final repo = await ref.read(accountsRepositoryProvider.future);
      await repo.setHidden(_acc!.id, hidden: v);
      if (v) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.accountsEditHidden)),
        );
      }
    } on Object {
      if (mounted) setState(() => _hidden = !v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final e = _touched ? _errors : const CardFormErrors();
    final valid = _errors.isValid && !_saving;
    final isCredit = _kind == AccountKind.credit;
    final port = ref.watch(cardCapturePortProvider);
    final channels = _channels(l10n);

    String? nameMsg() => switch (e.name) {
      NameError.empty => l10n.commonValidationNameRequired,
      NameError.tooLong => l10n.commonValidationNameLength(
        cardNameMax,
        digits.render('$cardNameMax'),
      ),
      NameError.taken => l10n.commonValidationNameTaken,
      null => null,
    };

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(
          widget.isEdit
              ? l10n.accountsEditTitleEdit
              : l10n.accountsEditTitleNew,
        ),
        leading: IconButton(
          tooltip: l10n.commonActionClose,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          TextButton(
            key: const Key('card-save'),
            style: TextButton.styleFrom(
              minimumSize: const Size(ZSpacing.minTarget, ZSpacing.minTarget),
            ),
            onPressed: valid ? _save : null,
            child: Text(l10n.commonActionSave),
          ),
          const SizedBox(width: ZSpacing.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
        children: [
          if (_saveFailed)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
              child: ZBanner(
                key: const Key('card-save-error'),
                message: l10n.commonErrorSaveFailed,
                tone: ZBannerTone.error,
              ),
            ),
          if (_duplicate != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ZBanner(
                    key: const Key('card-duplicate'),
                    message: l10n.accountsEditDuplicate,
                    tone: ZBannerTone.warning,
                  ),
                  const SizedBox(height: ZSpacing.sm),
                  ZButton(
                    label: l10n.accountsEditOpenExisting,
                    variant: ZButtonVariant.secondary,
                    onPressed: () => widget.onOpenExisting?.call(_duplicate!),
                  ),
                ],
              ),
            ),
          _Preview(
            name: _name.text.trim(),
            bank: _bankName(lang),
            last4: normalizeDigits(_last4.text.trim()),
            digits: digits,
          ),
          const SizedBox(height: ZSpacing.lg),
          TextField(
            key: const Key('card-name'),
            controller: _name,
            textInputAction: TextInputAction.next,
            maxLength: cardNameMax * 2,
            buildCounter: _noCounter,
            onChanged: (_) => setState(() => _touched = true),
            decoration: InputDecoration(
              labelText: l10n.accountsEditName,
              errorText: nameMsg(),
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          InputDecorator(
            decoration: InputDecoration(labelText: l10n.accountsEditBank),
            child: Text(
              widget.isEdit && _acc!.institutionCode != null
                  ? '${_bankName(lang)}  ·  ${l10n.accountsEditBankAuto}'
                  : _bankName(lang),
              style: ZType.body.copyWith(color: c.text),
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          TextField(
            key: const Key('card-last4'),
            controller: _last4,
            enabled: !widget.isEdit,
            keyboardType: TextInputType.number,
            inputFormatters: const [
              NormalizeDigitsFormatter(),
              _Last4Formatter(),
            ],
            onChanged: (_) => setState(() => _touched = true),
            decoration: InputDecoration(
              labelText: l10n.accountsEditLast4,
              helperText: l10n.accountsEditLast4Hint(digits.render('1234')),
              helperMaxLines: 3,
              errorText: e.last4 == null ? null : l10n.commonValidationLast4,
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          if (widget.isEdit)
            DropdownButtonFormField<AccountKind>(
              key: const Key('card-type'),
              initialValue: _kind,
              decoration: InputDecoration(labelText: l10n.accountsEditType),
              items: [
                for (final k in AccountKind.values)
                  if (k != AccountKind.cash || _kind == AccountKind.cash)
                    DropdownMenuItem(
                      value: k,
                      child: Text(_kindLabel(l10n, k)),
                    ),
              ],
              onChanged: _acc!.isDefaultCash
                  ? null
                  : (k) => setState(() => _kind = k ?? _kind),
            )
          else
            InputDecorator(
              decoration: InputDecoration(labelText: l10n.accountsEditType),
              child: Text(
                _kindLabel(l10n, _kind),
                style: ZType.body.copyWith(color: c.text),
              ),
            ),
          const SizedBox(height: ZSpacing.md),
          if (widget.isEdit)
            InputDecorator(
              decoration: InputDecoration(labelText: l10n.accountsEditCurrency),
              child: Text(_currency, style: ZType.body.copyWith(color: c.text)),
            )
          else
            DropdownButtonFormField<String>(
              key: const Key('card-currency'),
              initialValue: _currency,
              decoration: InputDecoration(labelText: l10n.accountsEditCurrency),
              items: [
                for (final code in {_currency, ...Currency.featuredCodes})
                  DropdownMenuItem(value: code, child: Text(code)),
              ],
              onChanged: (v) => setState(() => _currency = v ?? _currency),
            ),
          if (isCredit) ...[
            const SizedBox(height: ZSpacing.md),
            TextField(
              key: const Key('card-limit'),
              controller: _limit,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [NormalizeDigitsFormatter()],
              onChanged: (_) => setState(() => _touched = true),
              decoration: InputDecoration(
                labelText: l10n.accountsEditLimit,
                suffixText: _currency,
                errorText: e.limit == null
                    ? null
                    : e.limit == LimitError.negative
                    ? l10n.accountsEditErrorLimit
                    : l10n.commonValidationAmountDecimals(
                        _cur.exponent,
                        _currency,
                        digits.render('${_cur.exponent}'),
                      ),
              ),
            ),
            const SizedBox(height: ZSpacing.md),
            TextField(
              key: const Key('card-dueday'),
              controller: _dueDay,
              keyboardType: TextInputType.number,
              inputFormatters: const [
                NormalizeDigitsFormatter(),
                _DueDayFormatter(),
              ],
              onChanged: (_) => setState(() => _touched = true),
              decoration: InputDecoration(
                labelText: l10n.accountsEditDueDay,
                errorText: e.dueDay == null
                    ? null
                    : l10n.accountsEditErrorDueDay(
                        digits.render('$dueDayMax'),
                        digits.render('$dueDayMin'),
                      ),
              ),
            ),
          ],
          if (!widget.isEdit && port != null) ...[
            const SizedBox(height: ZSpacing.lg),
            Semantics(
              header: true,
              child: Text(
                l10n.accountsEditCaptureTitle,
                style: ZType.titleSmall.copyWith(color: c.text),
              ),
            ),
            for (final ch in channels)
              SwitchListTile(
                key: Key('capture-${ch.$1}'),
                contentPadding: EdgeInsets.zero,
                title: Text(ch.$2),
                value: !_off.contains(ch.$1),
                onChanged: (on) => setState(() {
                  on ? _off.remove(ch.$1) : _off.add(ch.$1);
                }),
              ),
          ],
          if (widget.isEdit) ...[
            const SizedBox(height: ZSpacing.lg),
            ZListRow(
              key: const Key('card-merge'),
              title: l10n.accountsEditMerge,
              leading: Icon(Icons.merge_rounded, color: c.primary),
              showChevron: true,
              enabled: !_acc!.isDefaultCash,
              onTap: () => _openMerge(context),
            ),
            SwitchListTile(
              key: const Key('card-hide'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.accountsEditHide),
              subtitle: Text(l10n.accountsEditHideHint),
              value: _hidden,
              onChanged: _acc!.isDefaultCash ? null : _toggleHidden,
            ),
            ZListRow(
              key: const Key('card-capture-link'),
              title: l10n.accountsEditCaptureLink,
              leading: Icon(Icons.tune_rounded, color: c.primary),
              showChevron: true,
              onTap: () => widget.onOpenCapture?.call(_acc!),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openMerge(BuildContext context) async {
    final target = await runMergeFlow(context, ref, source: _acc!);
    if (target != null && mounted) widget.onSaved?.call(target);
  }

  String _bankName(String lang) {
    final i = widget.institution;
    if (i != null) return i.name(lang);
    final code = _acc?.institutionCode;
    if (code == null) return '';
    for (final o in ref.read(institutionOptionsProvider)) {
      if (o.code == code) return o.name(lang);
    }
    return code;
  }

  List<(String, String)> _channels(AppLocalizations l10n) {
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return ios
        ? [
            (IgnoreChannel.sms, l10n.commonChannelSmsShort),
            (IgnoreChannel.applePay, l10n.commonChannelApplePay),
          ]
        : [
            (IgnoreChannel.sms, l10n.commonChannelSmsShort),
            (IgnoreChannel.notification, l10n.commonChannelNotificationsShort),
          ];
  }
}

Widget? _noCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) => null;

String _kindLabel(AppLocalizations l10n, AccountKind k) => switch (k) {
  AccountKind.debit => l10n.commonAccountTypeDebit,
  AccountKind.credit => l10n.commonAccountTypeCredit,
  AccountKind.account => l10n.commonAccountTypeAccount,
  AccountKind.wallet => l10n.commonAccountTypeWallet,
  AccountKind.bnpl => l10n.commonAccountTypeBnpl,
  AccountKind.cash => l10n.commonAccountTypeCash,
  AccountKind.multiCurrency => l10n.commonAccountTypeMultiCurrency,
};

class _Last4Formatter extends TextInputFormatter {
  const _Last4Formatter();
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    final t = n.text.replaceAll(RegExp('[^0-9]'), '');
    final cut = t.length > 4 ? t.substring(0, 4) : t;
    return cut == n.text
        ? n
        : n.copyWith(
            text: cut,
            selection: TextSelection.collapsed(offset: cut.length),
          );
  }
}

class _DueDayFormatter extends TextInputFormatter {
  const _DueDayFormatter();
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) {
    final t = n.text.replaceAll(RegExp('[^0-9]'), '');
    final cut = t.length > 2 ? t.substring(0, 2) : t;
    return cut == n.text
        ? n
        : n.copyWith(
            text: cut,
            selection: TextSelection.collapsed(offset: cut.length),
          );
  }
}

/// Live card preview (mockup 30).
class _Preview extends StatelessWidget {
  const _Preview({
    required this.name,
    required this.bank,
    required this.last4,
    required this.digits,
  });

  final String name;
  final String bank;
  final String last4;
  final DigitsMode digits;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final tail = last4.isEmpty ? '' : '•••• ${digits.render(last4)}';
    return Container(
      key: const Key('card-preview'),
      padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
      decoration: BoxDecoration(
        color: c.primaryContainer,
        borderRadius: BorderRadius.circular(ZRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(bank, style: ZType.label.copyWith(color: c.onPrimaryContainer)),
          const SizedBox(height: ZSpacing.sm),
          Text(
            name.isEmpty ? ' ' : name,
            style: ZType.title.copyWith(color: c.onPrimaryContainer),
          ),
          if (tail.isNotEmpty)
            Text(tail, style: ZType.body.copyWith(color: c.onPrimaryContainer)),
        ],
      ),
    );
  }
}
