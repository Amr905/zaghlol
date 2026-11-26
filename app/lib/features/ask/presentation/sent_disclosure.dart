// T-345: the masked question exactly as it leaves the phone (FR-LLM-09,
// D-92; ask-llm-ux §2). Names are non-interactive chips that say only the
// kind and a number; the map from number to name is never passed in here.
// The same [SentTextView] is the consent sheet's preview and the answer's
// "What I sent" block.

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';

/// A kind of name that was replaced by a numbered placeholder chip.
enum SentChipKind {
  account('account'),
  card('card'),
  bank('bank'),
  merchant('merchant'),
  other('other');

  const SentChipKind(this.state);

  /// The ICU select value in the chat_sent_chip strings.
  final String state;
}

/// A kind of value the scrubber removed.
enum SentHiddenKind {
  phone('phone'),
  email('email'),
  instapay('instapay'),
  number('number'),
  other('other');

  const SentHiddenKind(this.state);
  final String state;
}

/// One piece of the sent question.
sealed class SentSegment {
  const SentSegment();
}

final class SentPlain extends SentSegment {
  const SentPlain(this.text);
  final String text;
}

/// «Card 1»: [n] is the placeholder number only, never what it stands for.
final class SentPlaceholder extends SentSegment {
  const SentPlaceholder(this.kind, this.n);
  final SentChipKind kind;
  final int n;
}

/// A scrub token (phone, e-mail ...): shown as a hidden chip.
final class SentHidden extends SentSegment {
  const SentHidden(this.kind);
  final SentHiddenKind kind;
}

bool _isRtlChar(int c) =>
    (c >= 0x0590 && c <= 0x08FF) ||
    (c >= 0xFB1D && c <= 0xFDFF) ||
    (c >= 0xFE70 && c <= 0xFEFF);

bool _isLtrChar(int c) =>
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0xC0 && c <= 0x24F);

/// The direction of the first strong character of the plain text, or null
/// when there is none (the ambient direction applies).
TextDirection? firstStrongDirection(List<SentSegment> segments) {
  for (final s in segments) {
    if (s is! SentPlain) continue;
    for (final c in s.text.runes) {
      if (_isRtlChar(c)) return TextDirection.rtl;
      if (_isLtrChar(c)) return TextDirection.ltr;
    }
  }
  return null;
}

final String _fsi = String.fromCharCode(0x2068);
final String _pdi = String.fromCharCode(0x2069);

String _chipLabel(AppLocalizations t, SentSegment s) => switch (s) {
  SentPlaceholder(:final kind, :final n) => t.chatSentChip(n, kind.state),
  SentHidden(:final kind) => t.chatSentHidden(kind.state),
  SentPlain(:final text) => text,
};

/// The screen-reader text: the question with each chip read in full.
String sentSemanticsText(AppLocalizations t, List<SentSegment> segments) {
  final text = [
    for (final s in segments)
      switch (s) {
        SentPlain(:final text) => text,
        SentPlaceholder(:final kind, :final n) => t.chatSentChipA11y(
          n,
          kind.state,
        ),
        SentHidden(:final kind) => t.chatSentHidden(kind.state),
      },
  ].join();
  return t.chatSentTextA11y(text);
}

/// The masked question as one text block with chips. One semantics node;
/// the block takes the direction of its first strong character.
class SentTextView extends StatelessWidget {
  const SentTextView({super.key, required this.segments});

  final List<SentSegment> segments;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final dir = firstStrongDirection(segments) ?? Directionality.of(context);
    final style = ZType.body.copyWith(color: c.text);
    return Semantics(
      container: true,
      label: sentSemanticsText(t, segments),
      child: ExcludeSemantics(
        child: Directionality(
          textDirection: dir,
          child: SizedBox(
            width: double.infinity,
            child: Text.rich(
              TextSpan(
                children: [
                  for (final s in segments)
                    switch (s) {
                      SentPlain(:final text) => TextSpan(text: text),
                      _ => WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: _SentChip(
                          label: '$_fsi${_chipLabel(t, s)}$_pdi',
                          hidden: s is SentHidden,
                        ),
                      ),
                    },
                ],
              ),
              style: style,
            ),
          ),
        ),
      ),
    );
  }
}

class _SentChip extends StatelessWidget {
  const _SentChip({required this.label, required this.hidden});

  final String label;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Container(
      margin: const EdgeInsetsDirectional.symmetric(horizontal: ZSpacing.xs),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: ZSpacing.sm,
        vertical: ZSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: hidden ? c.surfaceAlt : c.primaryContainer,
        borderRadius: BorderRadius.circular(ZRadius.sm),
        border: hidden ? Border.all(color: c.outline) : null,
      ),
      child: Text(
        label,
        style: ZType.label.copyWith(
          color: hidden ? c.textMuted : c.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// The collapsible "What I sent" block under an answer (collapsed by
/// default, D-92).
class SentDisclosure extends StatefulWidget {
  const SentDisclosure({
    super.key,
    required this.segments,
    required this.providerName,
    this.initiallyExpanded = false,
  });

  final List<SentSegment> segments;
  final String providerName;
  final bool initiallyExpanded;

  @override
  State<SentDisclosure> createState() => _SentDisclosureState();
}

class _SentDisclosureState extends State<SentDisclosure> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final hasChips = widget.segments.any((s) => s is! SentPlain);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            key: const ValueKey('sent-disclosure-toggle'),
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.chatSentToggle,
                        style: ZType.label.copyWith(color: c.primary),
                      ),
                    ),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: c.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_open) ...[
          Text(
            t.chatSentTitle,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.sm),
          SentTextView(segments: widget.segments),
          if (hasChips) ...[
            const SizedBox(height: ZSpacing.sm),
            Text(
              t.chatSentChipsNote,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
          ],
          const SizedBox(height: ZSpacing.sm),
          Text(
            t.chatSentAlsoSent(widget.providerName),
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.md),
        ],
      ],
    );
  }
}
