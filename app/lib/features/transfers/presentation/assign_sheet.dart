// T-093 / S-15 Mode B: "This is money back for…". Assigns an incoming
// transfer to one or more expenses of the same currency (FR-XFR-06/07,
// BR-XFR-06). What is not assigned stays income, shown live.

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

/// Opens S-15 Mode B for the incoming transfer [sourceId].
Future<bool?> showAssignSheet(BuildContext context, String sourceId) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AssignSheet(sourceId: sourceId),
    );

class AssignSheet extends ConsumerStatefulWidget {
  const AssignSheet({super.key, required this.sourceId});
  final String sourceId;

  @override
  ConsumerState<AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<AssignSheet> {
  final Map<String, TextEditingController> _amounts = {};
  final Set<String> _picked = {};
  final TextEditingController _search = TextEditingController();
  bool _all = false;
  bool _busy = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _amounts.values) {
      c.dispose();
    }
    _search.dispose();
    super.dispose();
  }

  ({String id, bool all}) get _key => (id: widget.sourceId, all: _all);

  Currency _cur(AssignData d) => d.amount.currency;

  Money? _parsed(String id, AssignData d, TransfersFmt f) {
    final ctl = _amounts[id];
    return ctl == null ? null : f.parsePositive(ctl.text, _cur(d));
  }

  int _assigned(AssignData d, TransfersFmt f) {
    var sum = 0;
    for (final id in _picked) {
      sum += _parsed(id, d, f)?.minor ?? 0;
    }
    return sum;
  }

  void _toggle(AssignCandidate c, AssignData d, TransfersFmt f, bool on) {
    setState(() {
      if (on) {
        final spare = d.left.minor - _assigned(d, f);
        final take = spare < c.room.minor ? spare : c.room.minor;
        _amounts.putIfAbsent(c.expenseId, () => TextEditingController());
        _amounts[c.expenseId]!.text = take > 0
            ? f.input(Money(_cur(d), take))
            : '';
        _picked.add(c.expenseId);
      } else {
        _picked.remove(c.expenseId);
      }
    });
  }

  String? _validate(AppLocalizations l, AssignData d, TransfersFmt f) {
    if (_picked.isEmpty) return l.transfersSplitErrorShareZero;
    var sum = 0;
    for (final id in _picked) {
      final m = _parsed(id, d, f);
      if (m == null) return l.transfersSplitErrorShareZero;
      final room = d.candidates.firstWhere((c) => c.expenseId == id).room;
      if (m.minor > room.minor) return l.transfersAssignErrorExceedsExpense;
      sum += m.minor;
    }
    if (sum > d.left.minor) return l.transfersAssignErrorExceedsIncoming;
    return null;
  }

  Future<void> _save(AssignData d, TransfersFmt f) async {
    final l = AppLocalizations.of(context);
    setState(() => _submitted = true);
    if (_validate(l, d, f) != null) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final port = await ref.read(transfersSheetPortProvider.future);
      await port.assign(d.sourceId, [
        for (final id in _picked)
          AssignLine(expenseId: id, amountMinor: _parsed(id, d, f)!.minor),
      ]);
      ref.invalidate(assignSheetDataProvider(_key));
      messenger.showSnackBar(SnackBar(content: Text(l.transfersAssignSaved)));
      nav.pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final f = transfersFmtOf(context, ref);
    final async = ref.watch(assignSheetDataProvider(_key));
    // Keep showing the previous list while "search all" loads.
    final data = async.value;
    final Widget body;
    if (async.hasError || (!async.isLoading && data == null)) {
      body = SheetError(
        onRetry: () => ref.invalidate(assignSheetDataProvider(_key)),
      );
    } else if (data == null) {
      body = const SheetSkeleton();
    } else {
      body = _content(context, l, f, data);
    }
    return ZSheetBody(
      title: l.transfersAssignTitle,
      actions: data == null
          ? null
          : ZButton(
              label: l.commonActionSave,
              expand: true,
              loading: _busy,
              onPressed: data.candidates.isEmpty ? null : () => _save(data, f),
            ),
      child: body,
    );
  }

  Widget _content(
    BuildContext context,
    AppLocalizations l,
    TransfersFmt f,
    AssignData d,
  ) {
    final c = ZColors.of(context);
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final e in d.candidates)
        if (q.isEmpty || e.merchant.toLowerCase().contains(q)) e,
    ];
    final unassigned = d.left.minor - _assigned(d, f);
    final validation = _submitted ? _validate(l, d, f) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.transfersAssignHeader(f.money(d.amount), d.person),
          style: ZType.titleSmall.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.md),
        Semantics(
          textField: true,
          label: l.transfersAssignSearch,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l.transfersAssignSearch,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(height: ZSpacing.sm),
        if (shown.isEmpty)
          _empty(l, f, d)
        else
          for (final e in shown) _candidate(context, l, f, d, e),
        if (!d.searchedAll && shown.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ZButton(
              label: l.transfersAssignSearchAll,
              variant: ZButtonVariant.text,
              onPressed: () => setState(() => _all = true),
            ),
          ),
        const SizedBox(height: ZSpacing.sm),
        Semantics(
          liveRegion: true,
          child: Text(
            l.transfersAssignUnassigned(
              f.money(Money(_cur(d), unassigned < 0 ? 0 : unassigned)),
            ),
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
        ),
        if (validation != null || _error != null) ...[
          const SizedBox(height: ZSpacing.md),
          ZBanner(message: validation ?? _error!, tone: ZBannerTone.error),
        ],
        const SizedBox(height: ZSpacing.md),
      ],
    );
  }

  Widget _empty(AppLocalizations l, TransfersFmt f, AssignData d) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: ZSpacing.lg),
      child: Column(
        children: [
          Text(
            l.transfersAssignEmpty(d.windowDays, f.count(d.windowDays)),
            textAlign: TextAlign.center,
            style: ZType.body.copyWith(color: c.textMuted),
          ),
          if (!d.searchedAll)
            ZButton(
              label: l.transfersAssignSearchAll,
              variant: ZButtonVariant.secondary,
              onPressed: () => setState(() => _all = true),
            ),
        ],
      ),
    );
  }

  Widget _candidate(
    BuildContext context,
    AppLocalizations l,
    TransfersFmt f,
    AssignData d,
    AssignCandidate e,
  ) {
    final c = ZColors.of(context);
    final on = _picked.contains(e.expenseId);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              checked: on,
              child: InkWell(
                onTap: () => _toggle(e, d, f, !on),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Checkbox(
                        value: on,
                        onChanged: (v) => _toggle(e, d, f, v ?? false),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.merchant,
                            style: ZType.body.copyWith(color: c.text),
                          ),
                          Text(
                            '${f.date(e.date)} · ${f.money(-e.amount)}',
                            style: ZType.caption.copyWith(color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (on)
            AmountField(
              controller: _amounts[e.expenseId]!,
              semanticsLabel: e.merchant,
              onChanged: (_) => setState(() {}),
              width: 110,
            ),
        ],
      ),
    );
  }
}
