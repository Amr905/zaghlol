// T-107: the shared chart card (C-13): title, filter context line, body.
// Also the loading skeleton, empty and error variants.

import 'package:flutter/material.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_button.dart';
import '../../../../core/ui/z_card.dart';
import '../../../../core/ui/amount_semantics.dart';

class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.contextLine,
    this.summary,
    this.trailing,
    this.meta,
    this.footnote,
    this.bare = false,
  });

  final String title;
  final Widget child;

  /// Filter context ("all cards . EGP . this cycle"): shown under the title
  /// on the bare (S-21) layout only; the S-20 list carries it in its header.
  final String? contextLine;

  /// The a11y summary: read as one label for the whole chart body.
  final String? summary;

  /// The "Explain" entry, at the end of the footer row.
  final Widget? trailing;

  /// Small caption at the end of the title row (e.g. "6 months").
  final String? meta;

  /// One-line takeaway at the start of the footer row.
  final String? footnote;

  /// S-21: no card, large title, the chart sits on the page.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final body = summary != null
        ? Semantics(
            label: a11yAmounts(AppLocalizations.of(context), summary!),
            container: true,
            child: child,
          )
        : child;
    final footer = (footnote != null || trailing != null)
        ? Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.md),
            child: Row(
              children: [
                if (footnote != null)
                  Expanded(
                    child: Text(
                      footnote!,
                      semanticsLabel: a11yAmounts(
                        AppLocalizations.of(context),
                        footnote!,
                      ),
                      style: ZType.body.copyWith(color: c.text),
                    ),
                  )
                else
                  const Spacer(),
                ?trailing,
              ],
            ),
          )
        : null;
    if (bare) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: ZType.display.copyWith(color: c.text)),
            ),
            if (contextLine != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                child: Text(
                  contextLine!,
                  style: ZType.body.copyWith(color: c.textMuted),
                ),
              ),
            const SizedBox(height: ZSpacing.lg),
            body,
            ?footer,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: ZCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: ZType.title.copyWith(color: c.text),
                    ),
                  ),
                ),
                if (meta != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: ZSpacing.sm,
                      top: ZSpacing.xs,
                    ),
                    child: Text(
                      meta!,
                      style: ZType.caption.copyWith(color: c.textMuted),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: ZSpacing.md),
            body,
            ?footer,
          ],
        ),
      ),
    );
  }
}

/// Chart-shaped placeholder while a query runs.
class ChartSkeleton extends StatelessWidget {
  const ChartSkeleton({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Semantics(
      label: l.insightsChartsLoadingA11y,
      container: true,
      child: ChartCard(
        title: title,
        child: ExcludeSemantics(
          child: SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final h in const [0.5, 0.8, 0.6, 0.9, 0.4, 0.7])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: ZSpacing.xs,
                      ),
                      child: FractionallySizedBox(
                        heightFactor: h,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.surfaceAlt,
                            borderRadius: BorderRadius.circular(ZRadius.sm),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChartMessage extends StatelessWidget {
  const ChartMessage({super.key, required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: ZType.body.copyWith(color: c.textMuted)),
        if (action != null) ...[const SizedBox(height: ZSpacing.sm), action!],
      ],
    );
  }
}

class ChartError extends StatelessWidget {
  const ChartError({super.key, required this.title, required this.onRetry});
  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ChartCard(
      title: title,
      child: ChartMessage(
        text: l.insightsChartsCardError,
        action: ZButton(
          label: l.commonActionTryAgain,
          variant: ZButtonVariant.text,
          onPressed: onRetry,
        ),
      ),
    );
  }
}

class LegendItem extends StatelessWidget {
  const LegendItem({super.key, required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(ZRadius.sm / 2),
          ),
        ),
        const SizedBox(width: ZSpacing.xs),
        Flexible(
          child: Text(label, style: ZType.caption.copyWith(color: c.text)),
        ),
      ],
    );
  }
}

/// "Explain" entry at the foot of a chart card: lightbulb + primary label.
class ExplainLink extends StatelessWidget {
  const ExplainLink({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Semantics(
      button: true,
      label: l.insightsChartsExplain,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZRadius.pill),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lightbulb_outline, size: 20, color: c.primary),
                const SizedBox(width: ZSpacing.xs),
                Text(
                  l.insightsChartsExplain,
                  style: ZType.titleSmall.copyWith(color: c.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
