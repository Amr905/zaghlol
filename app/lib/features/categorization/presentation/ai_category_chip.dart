// T-361: the small "Zaghlol's guess" chip (LLM-CATEGORISE, FR-LCAT-20). Shown
// only on a row whose category source is `ai`; it is a label, not a button
// (the row or the details screen carries the actions).

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../transactions/domain/transaction.dart';

/// Whether [t] shows the chip and feedback controls: an AI category the user
/// has not decided on. Deciding turns the row's source into `user_rule`
/// (T-359), so `ai` alone means "unconfirmed". A row without a merchant key
/// can't take feedback.
bool isAiUnconfirmed(TransactionRecord t) =>
    t.categorySource == CategorySource.ai && (t.merchantNorm ?? '').isNotEmpty;

class AiCategoryChip extends StatelessWidget {
  const AiCategoryChip({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Semantics(
      label: l.categorizationAiChipLabelA11y,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.zaghlolBg,
          borderRadius: BorderRadius.circular(ZRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.sm,
            vertical: ZSpacing.xs / 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 14, color: c.zaghlolText),
              const SizedBox(width: ZSpacing.xs),
              Flexible(
                child: Text(
                  l.categorizationAiChipLabel,
                  style: ZType.caption.copyWith(color: c.zaghlolText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
