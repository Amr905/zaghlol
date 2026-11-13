// T-107: the shared chart card (C-13): title, filter context line, body.
// Also the loading skeleton, empty and error variants.

import 'package:flutter/material.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_button.dart';
import '../../../../core/ui/z_card.dart';

class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.contextLine,
    this.summary,
    this.trailing,
  });

  final String title;
  final String? contextLine;

  /// The a11y summary: read as one label for the whole chart body.
  final String? summary;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: ZCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                ?trailing,
              ],
            ),
            if (contextLine != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                child: Text(
                  contextLine!,
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
              ),
            const SizedBox(height: ZSpacing.md),
            if (summary != null)
              Semantics(label: summary, container: true, child: child)
            else
              child,
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
        Text(label, style: ZType.caption.copyWith(color: c.text)),
      ],
    );
  }
}
