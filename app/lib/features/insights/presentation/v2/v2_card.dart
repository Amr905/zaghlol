// T-209 (CHARTS-V2): the card frame shared by the v2 tabs: a title with an
// optional subtitle and an optional text action at the end, then the body.
// T-210 and T-211 reuse it.

import 'package:flutter/material.dart';

import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_card.dart';

class V2Card extends StatelessWidget {
  const V2Card({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// The text action at the end of the title row ("See all categories").
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: ZCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: ZType.title.copyWith(color: c.text),
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            top: ZSpacing.xs,
                          ),
                          child: Text(
                            subtitle!,
                            style: ZType.caption.copyWith(color: c.textMuted),
                          ),
                        ),
                    ],
                  ),
                ),
                if (actionLabel != null)
                  Flexible(
                    child: Semantics(
                      button: true,
                      label: actionLabel,
                      excludeSemantics: true,
                      child: InkWell(
                        key: actionKey,
                        onTap: onAction,
                        borderRadius: BorderRadius.circular(ZRadius.sm),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: ZSpacing.minTarget,
                          ),
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start: ZSpacing.sm,
                            ),
                            child: Center(
                              child: Text(
                                actionLabel!,
                                textAlign: TextAlign.end,
                                style: ZType.label.copyWith(
                                  color: c.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: ZSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}
