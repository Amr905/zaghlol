// PO 2026-11-16 (BANK-ACRONYM): a bank / account name that falls back to the
// bank's English acronym (NBE, CIB, QNB...) when the full name does not fit
// on one line. The full name stays in the tooltip and the semantics label.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand/institution_brand.dart';
import '../l10n/card_number.dart';

class BankNameText extends ConsumerWidget {
  const BankNameText({
    required this.name,
    required this.style,
    this.institutionCode,
    this.last4,
    this.acronym,
    this.textAlign,
    this.compose,
    this.maxLines = 1,
    this.textKey,
    super.key,
  });

  /// The full name as stored or shown today.
  final String name;
  final String? institutionCode;

  /// Appended as "•••• 1234" (Western digits, LTR) to the name or acronym.
  final String? last4;

  /// Overrides the registry lookup (tests, previews).
  final String? acronym;
  final TextStyle style;
  final TextAlign? textAlign;

  /// Wraps the name in a longer line (e.g. "bank · source · time"), so the
  /// fit test covers the whole line the slot shows.
  final String Function(String name)? compose;
  final int maxLines;

  /// Key of the inner [Text] (tests).
  final Key? textKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final short =
        acronym ??
        (institutionCode == null
            ? null
            : ref
                  .watch(institutionBrandsProvider)
                  .value?[institutionCode]
                  ?.acronym);
    String line(String n) {
      final named = formatAccountWithCard(n, last4);
      return compose == null ? named : compose!(named);
    }

    final full = line(name);
    if (short == null) {
      return Text(
        full,
        key: textKey,
        style: style,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: full, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: maxLines,
        )..layout(maxWidth: box.maxWidth);
        final fits = !painter.didExceedMaxLines;
        painter.dispose();
        final shown = fits ? full : line(short);
        final text = Text(
          shown,
          key: textKey,
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        );
        if (fits) return text;
        final plain = compose == null
            ? formatAccountWithCard(name, last4)
            : full;
        return Tooltip(
          message: plain,
          child: Semantics(label: plain, excludeSemantics: true, child: text),
        );
      },
    );
  }
}
