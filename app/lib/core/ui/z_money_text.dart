import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/money_format.dart';
import '../theme/z_tokens.dart';

/// Money direction, driving colour (05-theme-2026 section 3): spending is ink,
/// money in is green, transfers are muted. The sign is part of [text], so
/// colour is never the only cue.
enum ZMoneyKind { expense, income, neutral }

enum ZMoneySize { hero, display, title, body, caption }

/// Placeholder glyph for a figure that is not known yet.
const String kNoValueDash = '\u2014';

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
    this.unit,
  });

  final String text;
  final ZMoneyKind kind;
  final ZMoneySize size;
  final String? semanticsLabel;

  /// Hide-amounts mode (D-67): the digits of [text] show as [kAmountMask].
  /// Text that the shared formatter already masked is recognised without
  /// this flag, so it is only needed when the caller formatted it elsewhere.
  final bool masked;

  /// Currency label rendered after the number, smaller and muted (mockups
  /// 03 / 20). [text] is then the number only.
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final color = switch (kind) {
      ZMoneyKind.expense => size == ZMoneySize.hero ? c.heroNumber : c.text,
      ZMoneyKind.income => c.incomeText,
      ZMoneyKind.neutral => c.textMuted,
    };
    final base = switch (size) {
      ZMoneySize.hero => ZType.display.copyWith(fontSize: 56, height: 1.1),
      ZMoneySize.display => ZType.display,
      ZMoneySize.title => ZType.title,
      ZMoneySize.body => ZType.body,
      ZMoneySize.caption => ZType.caption,
    };
    // FU-045: a masked amount never falls back to the real figure. Text the
    // shared formatter masked already carries the mask; `masked` covers the rest.
    final hidden = masked || text.contains(kAmountMask);
    final shown = masked ? maskAmountText(text) : text;
    final isolated = '\u2068$shown\u2069';
    final style = base.copyWith(
      color: color,
      fontWeight: size == ZMoneySize.caption
          ? FontWeight.w500
          : (size == ZMoneySize.hero ? FontWeight.w700 : FontWeight.w600),
    );
    final unitText = unit;
    final Widget textWidget = unitText == null
        ? Text(isolated, style: style, maxLines: 1)
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(text: isolated),
                TextSpan(
                  text: ' $unitText',
                  style: ZType.label.copyWith(
                    color: kind == ZMoneyKind.income ? color : c.textMuted,
                    fontSize: size == ZMoneySize.hero ? 22 : 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            style: style,
            maxLines: 1,
          );
    final hiddenLabel = hidden
        ? (Localizations.of<AppLocalizations>(
                context,
                AppLocalizations,
              )?.commonAmountHidden ??
              kAmountMask)
        : null;
    return Semantics(
      label:
          hiddenLabel ??
          semanticsLabel ??
          (unitText == null ? shown : '$shown $unitText'),
      excludeSemantics: true,
      child: size == ZMoneySize.display || size == ZMoneySize.hero
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: textWidget,
            )
          : (unitText == null ? Text(isolated, style: style) : textWidget),
    );
  }
}
