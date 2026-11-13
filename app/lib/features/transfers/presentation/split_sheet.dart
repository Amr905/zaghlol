// T-093 / S-15 Mode A: split an expense with other people and track who has
// paid back (FR-XFR-04…09, BR-XFR-04). The user's own share and the net paid
// figure update as they type. Spending is shown in ink, never red.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import 'transfers_format.dart';
import 'transfers_parts.dart';
import 'transfers_port.dart';
import 'transfers_providers.dart';

/// Longest person name (S-15 validation).
const int splitNameMaxChars = 30;

/// Opens S-15 Mode A for [expenseId]. Resolves to true when saved.
Future<bool?> showSplitSheet(BuildContext context, String expenseId) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SplitSheet(expenseId: expenseId),
    );

class _Row {
  _Row({this.id, String name = '', String share = ''})
    : name = TextEditingController(text: name),
      share = TextEditingController(text: share);

  final String? id;
  final TextEditingController name;
  final TextEditingController share;

  void dispose() {
    name.dispose();
    share.dispose();
  }
}

class SplitSheet extends ConsumerStatefulWidget {
  const SplitSheet({super.key, required this.expenseId});
  final String expenseId;

  @override
  ConsumerState<SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends ConsumerState<SplitSheet> {
  final List<_Row> _rows = [];
  final List<_Row> _gone = [];
  final Set<String> _removed = {};
  bool _inited = false;
  bool _busy = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    for (final r in [..._rows, ..._gone]) {
      r.dispose();
    }
    super.dispose();
  }

  void _init(SplitData d, TransfersFmt f) {
    if (_inited) return;
    _inited = true;
    for (final p in d.people) {
      _rows.add(_Row(id: p.id, name: p.name, share: f.input(p.share)));
    }
    if (_rows.isEmpty) _rows.add(_Row());
  }

  Money? _share(_Row r, Currency c, TransfersFmt f) =>
      f.parsePositive(r.share.text, c);

  String? _validate(AppLocalizations l, SplitData d, TransfersFmt f) {
    final c = d.amount.currency;
    var sum = 0;
    for (final r in _rows) {
      final name = r.name.text.trim();
      if (name.isEmpty) return l.commonValidationNameRequired;
      if (name.runes.length > splitNameMaxChars) {
        return l.commonValidationNameLength(
          splitNameMaxChars,
          f.count(splitNameMaxChars),
        );
      }
      final s = _share(r, c, f);
      if (s == null) return l.transfersSplitErrorShareZero;
      sum += s.minor;
    }
    if (sum > d.amount.minor) return l.transfersSplitErrorSharesExceed;
    return null;
  }

  void _splitEvenly(SplitData d, TransfersFmt f) {
    final parts = equalSplit(d.amount, _rows.length + 1);
    setState(() {
      for (var i = 0; i < _rows.length; i++) {
        _rows[i].share.text = f.input(parts[i + 1]);
      }
    });
  }

  Future<void> _save(SplitData d, TransfersFmt f) async {
    final l = AppLocalizations.of(context);
    setState(() => _submitted = true);
    if (_validate(l, d, f) != null) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final c = d.amount.currency;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final port = await ref.read(transfersSheetPortProvider.future);
      await port.saveSplit(d.expenseId, [
        for (final r in _rows)
          SplitEdit(
            id: r.id,
            name: r.name.text.trim(),
            shareMinor: _share(r, c, f)!.minor,
          ),
      ], _removed);
      ref.invalidate(splitSheetDataProvider(d.expenseId));
      messenger.showSnackBar(SnackBar(content: Text(l.transfersSplitSaved)));
      nav.pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l, e);
      });
    }
  }

  Future<void> _linkSuggestion(SplitData d, SplitSuggestion s) async {
    final l = AppLocalizations.of(context);
    setState(() => _error = null);
    try {
      final port = await ref.read(transfersSheetPortProvider.future);
      await port.assign(s.sourceId, [
        AssignLine(expenseId: d.expenseId, amountMinor: s.amount.minor),
      ], participantId: s.participantId);
      ref.invalidate(splitSheetDataProvider(d.expenseId));
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorMessage(l, e));
    }
  }

  Future<void> _unassign(SplitData d, SplitPerson p, SplitRepayment r) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _error = null);
    try {
      final port = await ref.read(transfersSheetPortProvider.future);
      await port.unassign(r.linkId);
      ref.invalidate(splitSheetDataProvider(d.expenseId));
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(l.transfersSplitUnassigned),
            action: SnackBarAction(
              label: l.commonActionUndo,
              onPressed: () async {
                await port.assign(r.sourceId, [
                  AssignLine(
                    expenseId: d.expenseId,
                    amountMinor: r.amount.minor,
                  ),
                ], participantId: p.id);
                if (mounted) {
                  ref.invalidate(splitSheetDataProvider(d.expenseId));
                }
              },
            ),
          ),
        );
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorMessage(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final f = transfersFmtOf(context, ref);
    final async = ref.watch(splitSheetDataProvider(widget.expenseId));
    final data = async.value;

    if (data != null) _init(data, f);
    final Widget body;
    if (async.hasError || (!async.isLoading && data == null)) {
      body = SheetError(
        onRetry: () => ref.invalidate(splitSheetDataProvider(widget.expenseId)),
      );
    } else if (data == null) {
      body = const SheetSkeleton();
    } else {
      body = _content(context, l, f, data);
    }

    return ZSheetBody(
      title: l.transfersSplitTitle,
      actions: data == null
          ? null
          : ZButton(
              label: l.commonActionSave,
              expand: true,
              loading: _busy,
              onPressed: () => _save(data, f),
            ),
      child: body,
    );
  }

  Widget _content(
    BuildContext context,
    AppLocalizations l,
    TransfersFmt f,
    SplitData d,
  ) {
    final c = ZColors.of(context);
    final cur = d.amount.currency;
    final shares = [for (final r in _rows) _share(r, cur, f) ?? Money(cur, 0)];
    final own = ownShare(d.amount, shares);
    final net = netOfOffsets(d.amount, d.reimbursed);
    final validation = _submitted ? _validate(l, d, f) : null;
    final people = {for (final p in d.people) p.id: p};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: false,
          child: Text(
            l.transfersSplitHeader(f.money(d.amount), d.merchant),
            style: ZType.titleSmall.copyWith(color: c.text),
          ),
        ),
        SheetLabel(l.transfersSplitPeople),
        for (var i = 0; i < _rows.length; i++)
          _personRow(context, l, f, d, _rows[i], people[_rows[i].id]),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(
            spacing: ZSpacing.sm,
            children: [
              ZButton(
                label: l.transfersSplitAddPerson,
                icon: Icons.add,
                variant: ZButtonVariant.text,
                onPressed: () => setState(() => _rows.add(_Row())),
              ),
              ZButton(
                label: l.transfersSplitEqual,
                variant: ZButtonVariant.text,
                onPressed: () => _splitEvenly(d, f),
              ),
            ],
          ),
        ),
        const SizedBox(height: ZSpacing.sm),
        ZCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.transfersSplitYourShare,
                        style: ZType.body.copyWith(color: c.text),
                      ),
                    ),
                    ZMoneyText(
                      text: f.money(own),
                      size: ZMoneySize.body,
                      semanticsLabel:
                          '${l.transfersSplitYourShare} ${f.money(own)}',
                    ),
                  ],
                ),
              ),
              if (d.reimbursed.minor > 0) ...[
                const SizedBox(height: ZSpacing.xs),
                Text(
                  l.transactionsRowReimbursed(
                    f.money(d.reimbursed),
                    f.money(net),
                  ),
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
              ],
            ],
          ),
        ),
        if (d.suggestions.isNotEmpty) ...[
          SheetLabel(l.transfersSplitSuggestions),
          for (final s in d.suggestions)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
              child: ZCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.transfersSplitSuggestion(
                          f.money(s.amount),
                          f.date(s.date),
                          s.person,
                        ),
                        style: ZType.bodySmall.copyWith(color: c.text),
                      ),
                    ),
                    const SizedBox(width: ZSpacing.sm),
                    ZButton(
                      label: l.commonActionLink,
                      size: ZButtonSize.small,
                      variant: ZButtonVariant.secondary,
                      onPressed: () => _linkSuggestion(d, s),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (validation != null || _error != null) ...[
          const SizedBox(height: ZSpacing.md),
          ZBanner(message: validation ?? _error!, tone: ZBannerTone.error),
        ],
        const SizedBox(height: ZSpacing.md),
      ],
    );
  }

  Widget _personRow(
    BuildContext context,
    AppLocalizations l,
    TransfersFmt f,
    SplitData d,
    _Row r,
    SplitPerson? person,
  ) {
    final c = ZColors.of(context);
    final name = r.name.text.trim();
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  textField: true,
                  label: l.transfersSplitPersonHint,
                  child: TextField(
                    controller: r.name,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: l.transfersSplitPersonHint,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: ZSpacing.sm),
              AmountField(
                controller: r.share,
                semanticsLabel: l.transfersSplitShareA11y(name),
                onChanged: (_) => setState(() {}),
              ),
              IconButton(
                tooltip: l.transfersSplitRemovePerson(name),
                constraints: const BoxConstraints(
                  minWidth: ZSpacing.minTarget,
                  minHeight: ZSpacing.minTarget,
                ),
                icon: Icon(Icons.close, color: c.textMuted),
                onPressed: () => setState(() {
                  if (r.id != null) _removed.add(r.id!);
                  _rows.remove(r);
                  _gone.add(r);
                }),
              ),
            ],
          ),
          if (person != null) ...[
            const SizedBox(height: ZSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ZPill(
                label: person.paidBack
                    ? l.transfersSplitPaidBack
                    : l.transfersSplitWaiting,
                tone: person.paidBack ? ZPillTone.success : ZPillTone.neutral,
                icon: person.paidBack
                    ? Icons.check_circle_outline
                    : Icons.schedule,
              ),
            ),
            for (final rep in person.repayments) ...[
              Padding(
                padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                child: Text(
                  l.transfersSplitPaidDetail(
                    f.money(rep.amount),
                    f.date(rep.date),
                    rep.sourceLabel,
                  ),
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ZButton(
                  label: l.transfersSplitUnassign,
                  size: ZButtonSize.small,
                  variant: ZButtonVariant.text,
                  onPressed: () => _unassign(d, person, rep),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
