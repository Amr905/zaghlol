// T-195 (D-71): on the detail of a received salary that replaced a salary the
// user had added by hand: says so and offers to bring the user's own entry
// back (both then count; for when they were two payments). Shows nothing for
// any other transaction.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_banner.dart';
import '../application/salary_matching.dart';
import '../application/salary_providers.dart';

class SalaryMergedBanner extends ConsumerWidget {
  const SalaryMergedBanner({super.key, required this.txnId});

  final String txnId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(salaryStateProvider).value;
    if (state?.entryOf(txnId)?.mergedTxnId == null) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: ZBanner(
        key: const ValueKey('salary-merged-banner'),
        message: l.salaryMergedTitle,
        actionLabel: l.salaryMergedUndo,
        onAction: () async {
          final messenger = ScaffoldMessenger.of(context);
          String message;
          try {
            final matching = await ref.read(salaryMatchingProvider.future);
            await matching.undoMerge(txnId);
            message = l.salaryMergedUndone;
          } on SalaryException {
            message = l.salaryMergedGone;
          }
          messenger
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(message)));
        },
      ),
    );
  }
}
