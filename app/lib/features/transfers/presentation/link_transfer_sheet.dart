// T-093 / S-16: link two of the user's own transactions as an internal
// transfer, same or cross-currency (FR-XFR-02, FR-CUR-06). Nothing is ever
// converted; the implied rate is a hint only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import 'transfers_format.dart';
import 'transfers_parts.dart';
import 'transfers_port.dart';
import 'transfers_providers.dart';

/// Opens S-16 for [txnId]. Resolves to true when linked.
Future<bool?> showLinkTransferSheet(BuildContext context, String txnId) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LinkTransferSheet(txnId: txnId),
    );

class LinkTransferSheet extends ConsumerStatefulWidget {
  const LinkTransferSheet({super.key, required this.txnId});
  final String txnId;

  @override
  ConsumerState<LinkTransferSheet> createState() => _LinkTransferSheetState();
}

class _LinkTransferSheetState extends ConsumerState<LinkTransferSheet> {
  String? _picked;
  bool _busy = false;
  String? _error;

  LinkCandidate? _selected(LinkData d) {
    final id = _picked ?? (d.candidates.isEmpty ? null : d.candidates.first.id);
    for (final c in d.candidates) {
      if (c.id == id) return c;
    }
    return null;
  }

  String? _mismatch(AppLocalizations l, LinkData d, LinkCandidate c) =>
      c.amount.currency == d.amount.currency && c.amount != d.amount
      ? l.transfersLinkErrorAmounts
      : null;

  Future<void> _link(LinkData d, LinkCandidate c) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final port = await ref.read(transfersSheetPortProvider.future);
      await (d.isOut ? port.link(d.id, c.id) : port.link(c.id, d.id));
      ref.invalidate(linkSheetDataProvider(widget.txnId));
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.transfersLinkLinked),
          action: SnackBarAction(
            label: l.commonActionUndo,
            onPressed: () => port.unlink(d.id),
          ),
        ),
      );
      nav.pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l, e);
      });
    }
  }

  Future<void> _markAnyway(LinkData d) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final port = await ref.read(transfersSheetPortProvider.future);
      await port.markAnyway(d.id);
      messenger.showSnackBar(SnackBar(content: Text(l.transfersLinkLinked)));
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
    final async = ref.watch(linkSheetDataProvider(widget.txnId));
    final data = async.value;
    final sel = data == null ? null : _selected(data);
    final Widget body;
    if (async.hasError || (!async.isLoading && data == null)) {
      body = SheetError(
        onRetry: () => ref.invalidate(linkSheetDataProvider(widget.txnId)),
      );
    } else if (data == null) {
      body = const SheetSkeleton();
    } else {
      body = _content(context, l, f, data, sel);
    }
    final blocked =
        data != null && sel != null && _mismatch(l, data, sel) != null;
    return ZSheetBody(
      title: l.transfersLinkTitle,
      actions: data == null || sel == null
          ? null
          : ZButton(
              label: l.commonActionLink,
              expand: true,
              loading: _busy,
              onPressed: blocked ? null : () => _link(data, sel),
            ),
      child: body,
    );
  }

  Widget _content(
    BuildContext context,
    AppLocalizations l,
    TransfersFmt f,
    LinkData d,
    LinkCandidate? sel,
  ) {
    final c = ZColors.of(context);
    final canMark =
        ref.watch(transfersSheetPortProvider).value?.supportsMarkAnyway ??
        false;
    final error = sel == null ? null : _mismatch(l, d, sel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.transfersLinkSource(
            f.money(d.isOut ? -d.amount : d.amount),
            d.accountLabel,
            f.date(d.when),
          ),
          style: ZType.titleSmall.copyWith(color: c.text),
        ),
        if (d.candidates.isEmpty)
          _empty(context, l, d, canMark)
        else ...[
          SheetLabel(l.transfersLinkPick),
          RadioGroup<String>(
            groupValue: sel?.id,
            onChanged: (v) => setState(() => _picked = v),
            child: Column(
              children: [
                for (final cand in d.candidates)
                  _candidate(context, l, f, d, cand),
              ],
            ),
          ),
        ],
        if (error != null || _error != null) ...[
          const SizedBox(height: ZSpacing.md),
          ZBanner(message: error ?? _error!, tone: ZBannerTone.error),
        ],
        const SizedBox(height: ZSpacing.md),
      ],
    );
  }

  Widget _empty(
    BuildContext context,
    AppLocalizations l,
    LinkData d,
    bool canMark,
  ) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: ZSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l.transfersLinkEmptyTitle,
              style: ZType.titleSmall.copyWith(color: c.text),
            ),
          ),
          const SizedBox(height: ZSpacing.sm),
          Text(
            l.transfersLinkEmptyBody,
            style: ZType.body.copyWith(color: c.textMuted),
          ),
          if (canMark) ...[
            const SizedBox(height: ZSpacing.md),
            ZButton(
              label: l.transfersLinkMarkAnyway,
              variant: ZButtonVariant.secondary,
              loading: _busy,
              onPressed: () => _markAnyway(d),
            ),
          ],
        ],
      ),
    );
  }

  Widget _candidate(
    BuildContext context,
    AppLocalizations l,
    TransfersFmt f,
    LinkData d,
    LinkCandidate cand,
  ) {
    final c = ZColors.of(context);
    final rate = cand.amount.currency == d.amount.currency
        ? null
        : impliedRate(d.amount, cand.amount);
    final signed = d.isOut ? cand.amount : -cand.amount;
    final gap = gapLabel(l, f, cand.gapMinutes);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
      child: MergeSemantics(
        child: InkWell(
          onTap: () => setState(() => _picked = cand.id),
          child: Row(
            children: [
              Radio<String>(value: cand.id),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${f.money(signed)} · ${cand.accountLabel}',
                      style: ZType.body.copyWith(color: c.text),
                    ),
                    Text(
                      gap,
                      style: ZType.caption.copyWith(color: c.textMuted),
                    ),
                    if (rate != null)
                      Text(
                        l.transfersLinkImpliedRate(
                          rate.per.code,
                          f.money(rate.rate),
                        ),
                        style: ZType.caption.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
