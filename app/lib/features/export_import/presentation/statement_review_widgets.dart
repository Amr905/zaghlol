// T-269 / US-P08: the pieces of the statement review step (rows, year
// prompt, account picker). Presentation only: every figure arrives already
// formatted by the caller through the shared money / date formatters.

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';

/// What a row needs from the user, for its inline choices.
enum StatementRowNeed { none, direction, balance }

/// One statement row, ready to draw.
final class StatementRowView {
  const StatementRowView({
    required this.number,
    required this.date,
    required this.description,
    required this.amount,
    required this.isExpense,
    required this.directionKnown,
    required this.need,
    required this.skipped,
    required this.duplicate,
  });

  final int number;
  final String date;
  final String description;

  /// Formatted with the shared formatter (signed for money out).
  final String amount;

  /// Direction after the user's choice; meaningless while [directionKnown] is
  /// false.
  final bool isExpense;
  final bool directionKnown;
  final StatementRowNeed need;
  final bool skipped;

  /// Matches an existing transaction and will be skipped.
  final bool duplicate;
}

/// Callbacks of a row: pick a direction, keep as read, skip, undo, add a
/// duplicate anyway, open the menu.
final class StatementRowActions {
  const StatementRowActions({
    required this.onKeep,
    required this.onOut,
    required this.onIn,
    required this.onSkip,
    required this.onUndo,
    required this.onAddAnyway,
    required this.onMenu,
  });
  final VoidCallback onKeep;
  final VoidCallback onOut;
  final VoidCallback onIn;
  final VoidCallback onSkip;
  final VoidCallback onUndo;
  final VoidCallback onAddAnyway;
  final VoidCallback onMenu;
}

class StatementRowTile extends StatelessWidget {
  const StatementRowTile({super.key, required this.row, required this.actions});

  final StatementRowView row;
  final StatementRowActions actions;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final unknown = !row.directionKnown;
    final direction = unknown
        ? ''
        : (row.isExpense ? l.stmtImportChoiceOut : l.stmtImportChoiceIn);
    final muted = row.skipped || row.duplicate;
    final textColor = muted ? c.textMuted : c.text;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
      child: ZCard(
        padding: const EdgeInsetsDirectional.all(ZSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    container: true,
                    label: l.stmtImportRowSemantics(
                      row.date,
                      row.description,
                      row.amount,
                      direction,
                    ),
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.description.isEmpty
                                ? row.date
                                : row.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: ZType.titleSmall.copyWith(color: textColor),
                          ),
                          Text(
                            row.date,
                            style: ZType.bodySmall.copyWith(color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: ZSpacing.sm),
                ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ZMoneyText(
                        text: row.amount,
                        kind: unknown
                            ? ZMoneyKind.neutral
                            : (row.isExpense
                                  ? ZMoneyKind.expense
                                  : ZMoneyKind.income),
                      ),
                      if (!unknown)
                        Text(
                          direction,
                          style: ZType.caption.copyWith(color: c.textMuted),
                        ),
                    ],
                  ),
                ),
                if (row.need == StatementRowNeed.none)
                  IconButton(
                    tooltip: l.stmtImportRowEdit,
                    constraints: const BoxConstraints(
                      minWidth: ZSpacing.minTarget,
                      minHeight: ZSpacing.minTarget,
                    ),
                    onPressed: actions.onMenu,
                    icon: Icon(Icons.more_vert, color: c.textMuted),
                  ),
              ],
            ),
            if (row.need != StatementRowNeed.none) ...[
              const SizedBox(height: ZSpacing.sm),
              Text(
                row.need == StatementRowNeed.direction
                    ? l.stmtImportReasonDirection
                    : l.stmtImportReasonBalance,
                style: ZType.bodySmall.copyWith(color: c.warningText),
              ),
              const SizedBox(height: ZSpacing.sm),
              Wrap(
                spacing: ZSpacing.sm,
                runSpacing: ZSpacing.sm,
                children: [
                  if (row.need == StatementRowNeed.balance)
                    ZButton(
                      label: l.stmtImportChoiceKeep,
                      size: ZButtonSize.small,
                      variant: ZButtonVariant.secondary,
                      onPressed: actions.onKeep,
                    ),
                  if (row.need == StatementRowNeed.direction || !row.isExpense)
                    ZButton(
                      label: l.stmtImportChoiceOut,
                      size: ZButtonSize.small,
                      variant: ZButtonVariant.secondary,
                      onPressed: actions.onOut,
                    ),
                  if (row.need == StatementRowNeed.direction || row.isExpense)
                    ZButton(
                      label: l.stmtImportChoiceIn,
                      size: ZButtonSize.small,
                      variant: ZButtonVariant.secondary,
                      onPressed: actions.onIn,
                    ),
                  ZButton(
                    label: l.stmtImportChoiceSkip,
                    size: ZButtonSize.small,
                    variant: ZButtonVariant.text,
                    onPressed: actions.onSkip,
                  ),
                ],
              ),
            ],
            if (row.skipped) ...[
              const SizedBox(height: ZSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.stmtImportRowSkipped,
                      style: ZType.label.copyWith(color: c.textMuted),
                    ),
                  ),
                  ZButton(
                    label: l.stmtImportRowUndo,
                    size: ZButtonSize.small,
                    variant: ZButtonVariant.text,
                    onPressed: actions.onUndo,
                  ),
                ],
              ),
            ] else if (row.duplicate) ...[
              const SizedBox(height: ZSpacing.xs),
              Text(
                l.stmtImportDupNote,
                style: ZType.bodySmall.copyWith(color: c.textMuted),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ZButton(
                  label: l.stmtImportDupAddAnyway,
                  size: ZButtonSize.small,
                  variant: ZButtonVariant.text,
                  onPressed: actions.onAddAnyway,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A section title ("Needs your answer (3)").
class StatementSectionHeader extends StatelessWidget {
  const StatementSectionHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(
      top: ZSpacing.md,
      bottom: ZSpacing.sm,
    ),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: ZType.titleSmall.copyWith(color: ZColors.of(context).text),
      ),
    ),
  );
}

/// "Which year is this statement from?" with the years offered as chips.
/// Nothing is selected until the user taps one.
class StatementYearPrompt extends StatelessWidget {
  const StatementYearPrompt({
    super.key,
    required this.years,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<int> years;
  final int? selected;

  /// Renders a year with the user's digit mode.
  final String Function(int year) label;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return ZCard(
      color: c.warningBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l.stmtImportYearTitle,
              style: ZType.titleSmall.copyWith(color: c.warningText),
            ),
          ),
          const SizedBox(height: ZSpacing.xs),
          Text(
            l.stmtImportYearBody,
            style: ZType.bodySmall.copyWith(color: c.warningText),
          ),
          const SizedBox(height: ZSpacing.md),
          Wrap(
            spacing: ZSpacing.sm,
            runSpacing: ZSpacing.sm,
            children: [
              for (final y in years)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: ZSpacing.minTarget,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: ZChip(
                      key: ValueKey('year_$y'),
                      label: label(y),
                      selected: selected == y,
                      onTap: () => onSelected(y),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
