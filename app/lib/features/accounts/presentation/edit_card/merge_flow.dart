// T-085: merge picker and confirm for S-43 (FR-ACC-04). The repository moves
// transactions, recurring items and balances in one database transaction, so
// nothing is lost or counted twice; this file only decides what to ask.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_banner.dart';
import '../../../../core/ui/z_card.dart';
import '../../data/accounts_providers.dart';
import '../../domain/account.dart';
import 'card_form_logic.dart';
import 'edit_card_providers.dart';

/// Picks a target, confirms, merges. Returns the surviving account, or null
/// when the user backed out or the merge failed (a banner snackbar says so).
Future<Account?> runMergeFlow(
  BuildContext context,
  WidgetRef ref, {
  required Account source,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final repo = await ref.read(accountsRepositoryProvider.future);
  final all = await repo.list();
  if (!context.mounted) return null;
  final candidates = [
    for (final a in all)
      if (a.id != source.id && !a.isMerged) a,
  ];
  final target = await Navigator.of(context).push<Account>(
    MaterialPageRoute(
      builder: (_) => MergePicker(source: source, candidates: candidates),
    ),
  );
  if (target == null || !context.mounted) return null;
  final ok = await showMergeConfirm(context, source: source, target: target);
  if (ok != true) return null;
  try {
    final merged = await repo.merge(sourceId: source.id, targetId: target.id);
    messenger.showSnackBar(SnackBar(content: Text(l10n.accountsMergeDone)));
    return merged;
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(l10n.commonErrorSaveFailed)));
    return null;
  }
}

class MergePicker extends StatelessWidget {
  const MergePicker({
    super.key,
    required this.source,
    required this.candidates,
  });

  final Account source;
  final List<Account> candidates;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(l10n.accountsMergePickTitle),
        leading: IconButton(
          tooltip: l10n.commonActionClose,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: candidates.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
                child: Text(
                  l10n.accountsMergeErrorSelf,
                  key: const Key('merge-none'),
                  textAlign: TextAlign.center,
                  style: ZType.body.copyWith(color: c.textMuted),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
              children: [
                for (final a in candidates)
                  ZListRow(
                    key: Key('merge-target-${a.id}'),
                    title: a.label,
                    subtitle: a.last4 == null ? null : '•••• ${a.last4}',
                    showChevron: true,
                    onTap: () => Navigator.of(context).pop(a),
                  ),
              ],
            ),
    );
  }
}

/// Confirm dialog "Move N transactions from A into B?"; a different bank
/// adds a warning the user must accept (S-43 validation).
Future<bool?> showMergeConfirm(
  BuildContext context, {
  required Account source,
  required Account target,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _MergeConfirm(source: source, target: target),
  );
}

class _MergeConfirm extends ConsumerWidget {
  const _MergeConfirm({required this.source, required this.target});

  final Account source;
  final Account target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final count = ref.watch(accountTxnCountProvider(source.id));
    final n = count.value;
    final differ =
        checkMerge(source, target) == MergeCheck.differentInstitution;
    String name(Account a) =>
        a.last4 == null ? a.label : '${a.label} •${digits.render(a.last4!)}';
    return AlertDialog(
      key: const Key('merge-confirm'),
      title: Text(
        n == null
            ? l10n.accountsMergeConfirmTitle(0, name(source), '0', name(target))
            : l10n.accountsMergeConfirmTitle(
                n,
                name(source),
                digits.render('$n'),
                name(target),
              ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.accountsMergeConfirmBody),
          if (differ) ...[
            const SizedBox(height: ZSpacing.md),
            ZBanner(
              key: const Key('merge-different-bank'),
              message: l10n.accountsMergeDifferentBank,
              tone: ZBannerTone.warning,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonActionCancel),
        ),
        TextButton(
          key: const Key('merge-confirm-yes'),
          onPressed: count.isLoading
              ? null
              : () => Navigator.of(context).pop(true),
          child: Text(
            differ
                ? l10n.accountsMergeDifferentBankConfirm
                : l10n.accountsMergeConfirm,
          ),
        ),
      ],
    );
  }
}
