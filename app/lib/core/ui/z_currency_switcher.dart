// T-116: shared currency switcher (FR-CUR-03, EC-55) and the labelled "≈" row.
// Neither widget adds amounts: the caller passes finished strings.

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/z_tokens.dart';
import 'z_chip.dart';
import 'z_money_text.dart';

/// Chips to pick one currency. Renders nothing with fewer than two codes
/// (EC-55: a single-currency user sees no switcher).
class ZCurrencySwitcher extends StatelessWidget {
  const ZCurrencySwitcher({
    super.key,
    required this.codes,
    required this.selected,
    required this.onSelected,
  });

  final List<String> codes;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (codes.length < 2) return const SizedBox.shrink();
    return Wrap(
      spacing: ZSpacing.sm,
      runSpacing: ZSpacing.sm,
      children: [
        for (final code in codes)
          ZChip(
            label: code,
            selected: code == selected,
            onTap: () => onSelected(code),
          ),
      ],
    );
  }
}

/// The labelled "≈" figure with its rate date, a stale badge and, when
/// [excludedCodes] is non-empty, the "not included" note (FU-134).
class ZApproxRow extends StatelessWidget {
  const ZApproxRow({
    super.key,
    required this.figureText,
    required this.rateDateText,
    required this.excludedCodes,
    this.stale = false,
  });

  /// Formatted target-currency amount, or null when nothing was included.
  final String? figureText;

  /// Formatted rate date, or null when no rate was needed.
  final String? rateDateText;
  final List<String> excludedCodes;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (figureText != null)
          Semantics(
            label: l10n.commonCurrencyApproxA11y,
            child: ZMoneyText(
              text: l10n.commonCurrencyApproxChip(figureText!),
              size: ZMoneySize.body,
              kind: ZMoneyKind.neutral,
            ),
          ),
        if (figureText != null && rateDateText != null)
          Text(
            l10n.commonCurrencyApproxCaption(rateDateText!),
            key: const Key('approx-rate-date'),
            style: ZType.caption.copyWith(color: c.textMuted),
          ),
        if (stale)
          Text(
            l10n.commonBadgeStale,
            key: const Key('approx-stale'),
            style: ZType.caption.copyWith(color: c.textMuted),
          ),
        // TODO(l10n): accountsOverviewApproxNotIncluded is missing (T-083
        // task file); the codes alone are shown until it lands.
        if (excludedCodes.isNotEmpty)
          Padding(
            key: const Key('approx-not-included'),
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: c.textMuted),
                const SizedBox(width: ZSpacing.xs),
                Flexible(
                  child: Text(
                    excludedCodes.join(' · '),
                    style: ZType.caption.copyWith(color: c.textMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
