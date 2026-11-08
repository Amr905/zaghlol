import 'package:flutter/material.dart';

import '../theme/z_tokens.dart';

/// Money direction, driving colour (05-theme-2026 section 3): spending is ink,
/// money in is green, transfers are muted. The sign is part of [text], so
/// colour is never the only cue.
enum ZMoneyKind { expense, income, neutral }

enum ZMoneySize { display, title, body, caption }

/// C-04 Money text. Takes an already formatted string (the shared money
/// formatter in core produces sign, digits and currency); never a number.
/// The text is isolated for bidi so `-450 EGP` never reorders in RTL.
class ZMoneyText extends StatelessWidget {
  const ZMoneyText({
    super.key,
    required this.text,
    this.kind = ZMoneyKind.expense,
    this.size = ZMoneySize.body,
    this.semanticsLabel,
    this.masked = false,
    this.maskedText,
  });

  final String text;
  final ZMoneyKind kind;
  final ZMoneySize size;
  final String? semanticsLabel;

  /// Hide-amounts mode: renders [maskedText] instead of [text].
  final bool masked;
  final String? maskedText;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final color = switch (kind) {
      ZMoneyKind.expense => c.text,
      ZMoneyKind.income => c.incomeText,
      ZMoneyKind.neutral => c.textMuted,
    };
    final base = switch (size) {
      ZMoneySize.display => ZType.display,
      ZMoneySize.title => ZType.title,
      ZMoneySize.body => ZType.body,
      ZMoneySize.caption => ZType.caption,
    };
    final shown = masked ? (maskedText ?? text) : text;
    final isolated = '⁨$shown⁩';
    final style = base.copyWith(
      color: color,
      fontWeight: size == ZMoneySize.caption ? FontWeight.w500 : FontWeight.w600,
    );
    return Semantics(
      label: semanticsLabel ?? shown,
      excludeSemantics: true,
      child: size == ZMoneySize.display
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(isolated, style: style, maxLines: 1),
            )
          : Text(isolated, style: style),
    );
  }
}
