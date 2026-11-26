// T-361: the Right / Wrong controls beside the AI chip (FR-LCAT-21…25).
//  * Right  -> confirm, snackbar with a 5 s Undo.
//  * Wrong  -> category picker (system + user categories); a cancelled picker
//    changes nothing; a pick -> correct, snackbar with a 5 s Undo.
// The service is reached through [aiFeedbackActionsProvider] (a thin adapter
// over `llmCatFeedbackProvider`) so tests can fake it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_sheet.dart';
import '../../transactions/presentation/detail/txn_detail_providers.dart';
import '../../transactions/presentation/list/txn_list_providers.dart';
import '../../transactions/presentation/list/txn_row.dart' show categoryName;
import '../application/llm_cat_feedback.dart';
import '../data/llm_cat_providers.dart';
import 'ai_category_chip.dart';
import 'category_visuals.dart';

/// What a feedback action leaves for Undo.
final class AiFeedbackResult {
  const AiFeedbackResult({required this.categoryId, required this.token});
  final String categoryId;
  final Object token;
}

abstract interface class AiFeedbackActions {
  Future<AiFeedbackResult> confirm(String merchantNorm);
  Future<AiFeedbackResult> correct(String merchantNorm, String categoryId);
  Future<void> undo(Object token);
}

final class _ServiceActions implements AiFeedbackActions {
  _ServiceActions(this._s);
  final LlmCatFeedback _s;

  @override
  Future<AiFeedbackResult> confirm(String m) async {
    final r = await _s.confirm(m);
    return AiFeedbackResult(categoryId: r.categoryId, token: r);
  }

  @override
  Future<AiFeedbackResult> correct(String m, String c) async {
    final r = await _s.correct(m, c);
    return AiFeedbackResult(categoryId: r.categoryId, token: r);
  }

  @override
  Future<void> undo(Object token) async =>
      _s.undo(token as LlmCatFeedbackReceipt);
}

final aiFeedbackActionsProvider = FutureProvider<AiFeedbackActions>((
  ref,
) async {
  return _ServiceActions(await ref.watch(llmCatFeedbackProvider.future));
});

/// Chip + ✓/✗ in one block (details, queue item). [categoryId] is the AI's
/// current category, left out of the picker.
class AiSuggestionBar extends ConsumerWidget {
  const AiSuggestionBar({
    super.key,
    required this.merchantNorm,
    required this.merchantLabel,
    required this.categoryId,
    required this.lookups,
    required this.lang,
    this.transactionId,
  });

  final String merchantNorm;
  final String merchantLabel;
  final String? categoryId;
  final TxnLookups lookups;
  final String lang;
  final String? transactionId;

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref, {
    required bool right,
  }) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context);
    final txnId = transactionId;
    String? picked;
    if (!right) {
      picked = await showZSheet<String>(
        context: context,
        title: l.categorizationAiPickerTitle,
        fullHeight: true,
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                ZSpacing.lg,
                0,
                ZSpacing.lg,
                ZSpacing.sm,
              ),
              child: Text(
                l.categorizationAiPickerHint(merchantLabel),
                style: ZType.bodySmall.copyWith(
                  color: ZColors.of(ctx).textMuted,
                ),
              ),
            ),
            for (final c in lookups.categories)
              if (c.id != categoryId)
                ListTile(
                  minTileHeight: 48,
                  title: Text(categoryName(c, lang)),
                  leading: categoryGlyph(
                    id: c.id,
                    iconKey: c.icon,
                    style: ZType.title,
                  ),
                  onTap: () => Navigator.of(ctx).pop(c.id),
                ),
          ],
        ),
      );
      if (picked == null) return; // cancel changes nothing
    }
    final actions = await container.read(aiFeedbackActionsProvider.future);
    final AiFeedbackResult r;
    try {
      r = right
          ? await actions.confirm(merchantNorm)
          : await actions.correct(merchantNorm, picked!);
    } catch (_) {
      return;
    }
    if (txnId != null) container.invalidate(txnDetailProvider(txnId));
    container.invalidate(txnListProvider);
    final cat = lookups.category(r.categoryId);
    final catName = cat == null ? '' : categoryName(cat, lang);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            right
                ? l.categorizationAiChipRightDone(merchantLabel, catName)
                : l.categorizationAiChipWrongDone(merchantLabel, catName),
          ),
          action: SnackBarAction(
            label: l.categorizationAiUndoAction,
            onPressed: () async {
              try {
                await actions.undo(r.token);
              } catch (_) {
                return;
              }
              if (txnId != null) {
                container.invalidate(txnDetailProvider(txnId));
              }
              container.invalidate(txnListProvider);
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AiCategoryChip(),
        Wrap(
          spacing: ZSpacing.sm,
          runSpacing: ZSpacing.sm,
          children: [
            _FeedbackButton(
              key: const ValueKey('ai-right'),
              icon: Icons.check,
              label: l.categorizationAiChipRightLabel,
              a11y: l.categorizationAiChipRightA11y,
              onTap: () => _decide(context, ref, right: true),
            ),
            _FeedbackButton(
              key: const ValueKey('ai-wrong'),
              icon: Icons.close,
              label: l.categorizationAiChipWrongLabel,
              a11y: l.categorizationAiChipWrongA11y,
              onTap: () => _decide(context, ref, right: false),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeedbackButton extends StatelessWidget {
  const _FeedbackButton({
    super.key,
    required this.icon,
    required this.label,
    required this.a11y,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String a11y;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Semantics(
      button: true,
      label: a11y,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZRadius.pill),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: c.primary),
                const SizedBox(width: ZSpacing.xs),
                Text(label, style: ZType.label.copyWith(color: c.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
