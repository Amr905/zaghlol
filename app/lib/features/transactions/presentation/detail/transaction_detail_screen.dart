// T-080: S-12 Transaction detail. See everything about one transaction and
// fix it (FR-TXN-02..05, FR-CAT-05, FR-XFR-02/04/06/09, FR-PAR-06).
//
// Reads only providers; every write goes through the repository / the shared
// bulk actions (so deletes run the pair and offset-link hooks). Spending is
// shown in ink, never red. The raw message ("How Zaghlol read this") is
// sensitive: shown on screen only, never logged.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/date_format.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_components.dart';
import '../../data/transaction_detail_reader.dart';
import '../../data/transactions_providers.dart';
import '../../domain/transaction.dart';
import '../edit/transaction_edit_screen.dart';
import '../list/txn_list_providers.dart';
import '../list/txn_row.dart';
import 'txn_detail_providers.dart';

/// Longest note, in characters (S-12 validation).
const int detailNoteMaxChars = 200;

class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({
    super.key,
    required this.transactionId,
    this.onSplit,
    this.onLinkTransfer,
    this.onMoneyBackFor,
  });

  final String transactionId;

  /// Entry points to S-15 / S-16 (their screens are other tasks); a row is
  /// shown only when its callback is given.
  final ValueChanged<String>? onSplit;
  final ValueChanged<String>? onLinkTransfer;
  final ValueChanged<String>? onMoneyBackFor;

  @override
  ConsumerState<TransactionDetailScreen> createState() => _DetailState();
}

class _DetailState extends ConsumerState<TransactionDetailScreen> {
  bool _leaving = false;

  TxnFmt _fmt(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return TxnFmt(lang, ref.watch(digitsModeProvider(lang)));
  }

  void _toast(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: action,
          duration: const Duration(seconds: 5),
        ),
      );
  }

  void _gone() {
    if (_leaving) return;
    _leaving = true;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
      messenger.showSnackBar(SnackBar(content: Text(l.transactionsDetailGone)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final detail = ref.watch(txnDetailProvider(widget.transactionId));
    final lookups = ref.watch(txnLookupsProvider);
    final fmt = _fmt(context);
    final d = detail.value;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).maybePop()),
        actions: [
          if (d != null) ...[
            IconButton(
              tooltip: l.commonActionEdit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  showTransactionEditor(context, existing: d.record),
            ),
            PopupMenuButton<String>(
              tooltip: l.commonActionMoreA11y,
              onSelected: (_) => _delete(d.record),
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(l.commonActionDelete),
                ),
              ],
            ),
          ],
        ],
      ),
      body: detail.when(
        loading: () => const _Skeleton(),
        error: (_, _) => Padding(
          padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
          child: ZBanner(
            message: l.commonErrorLoadFailed,
            tone: ZBannerTone.error,
            actionLabel: l.commonActionTryAgain,
            onAction: () =>
                ref.invalidate(txnDetailProvider(widget.transactionId)),
          ),
        ),
        data: (data) {
          if (data == null) {
            _gone();
            return const _Skeleton();
          }
          final lk = lookups.value;
          if (lk == null) return const _Skeleton();
          return _Body(
            detail: data,
            lookups: lk,
            fmt: fmt,
            onCategory: () => _changeCategory(data.record, lk, fmt),
            onNote: () => _editNote(data.record),
            onUnlink: () => _unlink(data.record),
            onSplit: widget.onSplit,
            onLinkTransfer: widget.onLinkTransfer,
            onMoneyBackFor: widget.onMoneyBackFor,
          );
        },
      ),
    );
  }

  // Category ---------------------------------------------------------------

  Future<void> _changeCategory(
    TransactionRecord t,
    TxnLookups lk,
    TxnFmt fmt,
  ) async {
    final l = AppLocalizations.of(context);
    final picked = await showZSheet<String>(
      context: context,
      title: l.transactionsEditCategory,
      fullHeight: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in lk.categories)
            ZListRow(
              title: categoryName(c, fmt.lang),
              leading: Text(c.icon, style: ZType.title),
              trailing: c.id == t.categoryId
                  ? Icon(Icons.check, color: ZColors.of(ctx).primary)
                  : null,
              onTap: () => Navigator.of(ctx).pop(c.id),
            ),
        ],
      ),
    );
    if (picked == null || picked == t.categoryId || !mounted) return;
    final merchant = (t.merchantNorm ?? t.merchantRaw ?? '').trim();
    var always = false;
    if (merchant.isNotEmpty) {
      // FR-CAT-05: ask whether to remember it. Dismissing cancels the change.
      final answer = await _askRule(
        categoryName(lk.category(picked)!, fmt.lang),
        merchant,
      );
      if (answer == null || !mounted) return;
      always = answer;
    }
    await _run(() async {
      final actions = await ref.read(txnBulkActionsProvider.future);
      final r = await actions.setCategory(
        {t.id},
        picked,
        alwaysUseForMerchants: always,
      );
      ref.invalidate(txnDetailProvider(t.id));
      ref.invalidate(txnListProvider);
      if (!mounted) return;
      _toast(
        r.rulesCreated > 0
            ? l.categorizationRuleSaved
            : l.transactionsDetailCategoryChanged,
        action: SnackBarAction(
          label: l.commonActionUndo,
          onPressed: () async {
            await _run(() async {
              await actions.undo(r.batchId);
              ref.invalidate(txnDetailProvider(t.id));
              ref.invalidate(txnListProvider);
            });
          },
        ),
      );
    });
  }

  /// True = always, false = just this once, null = dismissed.
  Future<bool?> _askRule(String category, String merchant) {
    final l = AppLocalizations.of(context);
    return showZSheet<bool>(
      context: context,
      title: l.categorizationRuleTitle(category, merchant),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZButton(
            label: l.categorizationRuleAlways,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: ZSpacing.sm),
          ZButton(
            label: l.categorizationRuleOnce,
            variant: ZButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
      ),
    );
  }

  // Note -------------------------------------------------------------------

  Future<void> _editNote(TransactionRecord t) async {
    final l = AppLocalizations.of(context);
    final text = await showZSheet<String>(
      context: context,
      title: l.transactionsDetailFieldNote,
      builder: (ctx) => _NoteForm(initial: t.note ?? ''),
    );
    if (text == null || !mounted) return;
    await _run(() async {
      final repo = await ref.read(transactionRepositoryProvider.future);
      await repo.edit(
        t.id,
        TransactionEdit(note: Maybe(text.trim().isEmpty ? null : text.trim())),
      );
      ref.invalidate(txnDetailProvider(t.id));
      ref.invalidate(txnListProvider);
    });
  }

  // Unlink / delete --------------------------------------------------------

  Future<void> _unlink(TransactionRecord t) async {
    await _run(() async {
      final pairing = await ref.read(transferPairingUseCaseProvider.future);
      await pairing.unlink(t.id);
      ref.invalidate(txnDetailProvider(t.id));
      ref.invalidate(txnListProvider);
    });
  }

  Future<void> _delete(TransactionRecord t) async {
    final l = AppLocalizations.of(context);
    final auto = t.source != TxnSource.manual;
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : 'android';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.transactionsDetailDeleteTitle),
        content: Text(
          auto
              ? l.transactionsDetailDeleteBodyAuto(platform)
              : l.transactionsDetailDeleteBodyManual,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.commonActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.commonActionDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final actions = await ref.read(txnBulkActionsProvider.future);
      // The shared delete path: also dissolves pairs and offset links.
      final r = await actions.delete({t.id});
      ref.invalidate(txnListProvider);
      _leaving = true;
      navigator.maybePop();
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(l.transactionsDetailDeleted),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: l.commonActionUndo,
              onPressed: () async {
                try {
                  await actions.undo(r.batchId);
                } on SafeException {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l.commonErrorSaveFailed)),
                  );
                }
                ref.invalidate(txnListProvider);
              },
            ),
          ),
        );
    } on SafeException {
      _toast(l.commonErrorSaveFailed);
    }
  }

  Future<void> _run(Future<void> Function() body) async {
    try {
      await body();
    } on SafeException {
      if (mounted) _toast(AppLocalizations.of(context).commonErrorSaveFailed);
    }
  }
}

class _NoteForm extends StatefulWidget {
  const _NoteForm({required this.initial});
  final String initial;

  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tooLong = _c.text.characters.length > detailNoteMaxChars;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _c,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: l.transactionsDetailNoteHint,
            errorText: tooLong
                ? l.commonValidationNoteLength(
                    detailNoteMaxChars,
                    detailNoteMaxChars.toString(),
                  )
                : null,
          ),
        ),
        const SizedBox(height: ZSpacing.md),
        ZButton(
          label: l.commonActionSave,
          onPressed: tooLong ? null : () => Navigator.of(context).pop(_c.text),
        ),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(ZRadius.md),
      ),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
      child: Column(
        children: [
          bar(56, 56),
          const SizedBox(height: ZSpacing.lg),
          bar(180, 32),
          const SizedBox(height: ZSpacing.md),
          bar(120, 20),
          const SizedBox(height: ZSpacing.xl),
          bar(double.infinity, 160),
        ],
      ),
    );
  }
}

Color _parseColor(String hex, Color fallback) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

class _Body extends StatelessWidget {
  const _Body({
    required this.detail,
    required this.lookups,
    required this.fmt,
    required this.onCategory,
    required this.onNote,
    required this.onUnlink,
    this.onSplit,
    this.onLinkTransfer,
    this.onMoneyBackFor,
  });

  final TxnDetail detail;
  final TxnLookups lookups;
  final TxnFmt fmt;
  final VoidCallback onCategory;
  final VoidCallback onNote;
  final VoidCallback onUnlink;
  final ValueChanged<String>? onSplit;
  final ValueChanged<String>? onLinkTransfer;
  final ValueChanged<String>? onMoneyBackFor;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final t = detail.record;
    final cat = lookups.category(t.categoryId);
    final acc = lookups.account(t.accountId);
    final merchant = t.merchantNorm ?? t.merchantRaw ?? '';
    final isExpense =
        t.direction == TxnDirection.expense || t.direction == TxnDirection.fee;
    final isIncoming =
        t.direction == TxnDirection.income ||
        t.direction == TxnDirection.transferIn;
    final amountText = fmt.money(signedAmount(t));
    final when = ZDateFormat.date(t.occurredAt, fmt.lang, fmt.digits);
    final time = ZDateFormat.time(t.occurredAt, fmt.lang, fmt.digits);
    final counterpart = detail.counterpart;
    final cpAcc = counterpart == null
        ? null
        : lookups.account(counterpart.accountId);

    Widget field(String label, String value, {VoidCallback? onTap}) => ZListRow(
      title: label,
      trailing: Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: ZType.body.copyWith(color: c.textMuted),
        ),
      ),
      onTap: onTap,
    );

    return ListView(
      padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
      children: [
        if (t.status == TxnStatus.declined)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
            child: ZBanner(
              message: l.transactionsDetailDeclinedBanner,
              tone: ZBannerTone.warning,
            ),
          ),
        if (t.isInternal)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
            child: ZBanner(
              message: counterpart == null || cpAcc == null
                  ? l.transactionsDetailInternalBanner
                  : '${l.transactionsDetailInternalBanner}\n'
                        '${l.transactionsDetailLinkedWith(fmt.money(counterpart.amount), accountName(cpAcc, fmt))}',
              actionLabel: counterpart == null ? null : l.commonActionUnlink,
              onAction: counterpart == null ? null : onUnlink,
            ),
          ),
        Column(
          children: [
            ZCategoryTile(
              color: _parseColor(cat?.color ?? '', c.primary),
              child: Text(cat?.icon ?? '•', style: ZType.title),
            ),
            const SizedBox(height: ZSpacing.md),
            ZMoneyText(
              text: amountText,
              kind: moneyKindOf(t),
              size: ZMoneySize.display,
            ),
            if (t.originalAmount != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                child: Text(
                  l.transactionsDetailOriginal(fmt.money(t.originalAmount!)),
                  style: ZType.bodySmall.copyWith(color: c.textMuted),
                ),
              ),
            if (merchant.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
                child: Text(
                  merchant,
                  textAlign: TextAlign.center,
                  style: ZType.title.copyWith(color: c.text),
                ),
              ),
            const SizedBox(height: ZSpacing.md),
            ZChip(
              label: cat == null
                  ? l.transactionsEditChoose
                  : categoryName(cat, fmt.lang),
              icon: Icons.arrow_drop_down,
              onTap: onCategory,
            ),
          ],
        ),
        const SizedBox(height: ZSpacing.xl),
        ZCard(
          padding: EdgeInsetsDirectional.zero,
          child: Column(
            children: [
              field(
                l.transactionsDetailFieldCard,
                acc == null ? '—' : accountName(acc, fmt),
              ),
              field(
                l.transactionsDetailFieldDate,
                l.commonDateDateTime(when, time),
              ),
              if (detail.balanceAfter != null)
                field(
                  l.transactionsDetailFieldBalance,
                  fmt.money(detail.balanceAfter!),
                ),
              field(l.transactionsDetailFieldSource, sourceLabel(l, t.source)),
              field(
                l.transactionsDetailFieldReference,
                detail.referenceNo == null
                    ? '—'
                    : fmt.digits.render(detail.referenceNo!),
              ),
              field(
                l.transactionsDetailFieldNote,
                (t.note == null || t.note!.isEmpty)
                    ? l.transactionsDetailNoteAdd
                    : t.note!,
                onTap: onNote,
              ),
            ],
          ),
        ),
        if ((isExpense && onSplit != null) ||
            (!t.isInternal && onLinkTransfer != null) ||
            (isIncoming && onMoneyBackFor != null)) ...[
          const SizedBox(height: ZSpacing.lg),
          ZCard(
            padding: EdgeInsetsDirectional.zero,
            child: Column(
              children: [
                if (isExpense && onSplit != null)
                  ZListRow(
                    title: l.transactionsDetailSplit,
                    leading: const Icon(Icons.call_split),
                    showChevron: true,
                    onTap: () => onSplit!(t.id),
                  ),
                if (!t.isInternal && onLinkTransfer != null)
                  ZListRow(
                    title: l.transactionsDetailLinkTransfer,
                    leading: const Icon(Icons.swap_horiz),
                    showChevron: true,
                    onTap: () => onLinkTransfer!(t.id),
                  ),
                if (isIncoming && onMoneyBackFor != null)
                  ZListRow(
                    title: l.transactionsDetailMoneyBackFor,
                    leading: const Icon(Icons.undo),
                    showChevron: true,
                    onTap: () => onMoneyBackFor!(t.id),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: ZSpacing.lg),
        _HowRead(detail: detail, fmt: fmt),
      ],
    );
  }
}

/// "How Zaghlol read this": collapsible raw message and parsed facts.
class _HowRead extends StatelessWidget {
  const _HowRead({required this.detail, required this.fmt});
  final TxnDetail detail;
  final TxnFmt fmt;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final t = detail.record;
    final raw = detail.rawBody;
    final merchant = t.merchantNorm ?? t.merchantRaw;
    final conf = detail.parseConfidence;
    final small = ZType.bodySmall.copyWith(color: c.textMuted);
    return ZCard(
      padding: EdgeInsetsDirectional.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            l.transactionsDetailHowTitle,
            style: ZType.titleSmall.copyWith(color: c.text),
          ),
          childrenPadding: const EdgeInsetsDirectional.fromSTEB(
            ZSpacing.lg,
            0,
            ZSpacing.lg,
            ZSpacing.lg,
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (raw == null)
              Text(l.transactionsDetailHowNone, style: small)
            else
              Semantics(
                label: l.transactionsDetailHowRawA11y,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsetsDirectional.all(ZSpacing.md),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(ZRadius.md),
                  ),
                  child: SelectableText(
                    raw,
                    style: ZType.bodySmall.copyWith(
                      color: c.text,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            if (raw != null) ...[
              const SizedBox(height: ZSpacing.md),
              Text(
                l.transactionsDetailHowAmount(fmt.money(t.amount.abs())),
                style: small,
              ),
              if (merchant != null && merchant.isNotEmpty)
                Text(l.transactionsDetailHowMerchant(merchant), style: small),
              if (conf != null)
                Text(
                  l.transactionsDetailHowConfidence(
                    l.commonProgressPercent(fmt.count((conf * 100).round())),
                  ),
                  style: small,
                ),
              if (detail.templateId != null)
                Text(
                  l.transactionsDetailHowTemplate(detail.templateId!),
                  style: small,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
