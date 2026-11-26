/// Client scrub (T-328, FR-LLM-03): phones, e-mails, InstaPay addresses and
/// digit runs of 8 or more become neutral tokens before anything else runs.
/// Pure, total, never throws, never logs.
library;

import '../../normalize/text_normalizer.dart';
import 'loose_text.dart';
import 'mask_models.dart';

final RegExp _address = RegExp(
  r'[\p{L}\p{N}._%+\-]+@[\p{L}\p{N}\-]+(?:\.[\p{L}\p{N}\-]+)*',
  unicode: true,
);

// A first group of any length, then groups of 3+ digits joined by one space
// or dash: "0100 123 4567", "4111-1111-1111-1111", "+20 100 123 4567".
final RegExp _digitRun = RegExp(r'\+?[0-9]+(?:[ \-][0-9]{3,})*');
final RegExp _egPhone = RegExp(r'^(?:0020|20)?0?1[0125][0-9]{8}$');
final RegExp _landline = RegExp(r'^0[2-9][0-9]{7,8}$');

const _tokens = {
  ScrubKind.phone: '⟦PHONE⟧',
  ScrubKind.email: '⟦EMAIL⟧',
  ScrubKind.ipa: '⟦IPA⟧',
  ScrubKind.number: '⟦NUMBER⟧',
};

/// The four scrub tokens (the masker leaves them alone).
const Set<String> scrubTokenTexts = {'⟦PHONE⟧', '⟦EMAIL⟧', '⟦IPA⟧', '⟦NUMBER⟧'};

abstract final class ClientScrub {
  /// Replaces sensitive literals in [text]. Typed `⟦` / `⟧` characters are
  /// dropped first so a user cannot forge a token. Amounts, percentages and
  /// periods typed by the user stay (FR-LLM-03); a bare run of 4 to 7 digits
  /// stays.
  static ScrubResult apply(String text) {
    try {
      return _apply(text.replaceAll(RegExp('[⟦⟧]'), ''));
    } on Object {
      // Fail closed: nothing readable leaves.
      return const ScrubResult('⟦NUMBER⟧', [
        ScrubToken(ScrubKind.number, '⟦NUMBER⟧'),
      ]);
    }
  }

  static ScrubResult _apply(String text) {
    final folded = foldKeyIndexed(text);
    final f = folded.text;
    final spans = <_Span>[];

    for (final m in _address.allMatches(f)) {
      final domain = f.substring(m.group(0)!.indexOf('@') + 1 + m.start, m.end);
      spans.add(
        _Span(
          m.start,
          m.end,
          domain.contains('.') ? ScrubKind.email : ScrubKind.ipa,
        ),
      );
    }
    for (final m in _digitRun.allMatches(f)) {
      final raw = m.group(0)!;
      final digits = raw.replaceAll(RegExp('[^0-9]'), '');
      if (digits.length < 8) {
        continue;
      }
      if (spans.any((s) => s.start < m.end && m.start < s.end)) {
        continue;
      }
      final plus = raw.startsWith('+');
      final phone =
          plus || _egPhone.hasMatch(digits) || _landline.hasMatch(digits);
      spans.add(
        _Span(m.start, m.end, phone ? ScrubKind.phone : ScrubKind.number),
      );
    }
    spans.sort((a, b) => a.start.compareTo(b.start));
    // Addresses were added first, so overlap removal keeps them.
    final kept = <_Span>[];
    for (final s in spans) {
      if (kept.isEmpty || s.start >= kept.last.end) {
        kept.add(s);
      }
    }
    final out = applyReplacements(text, folded, [
      for (final s in kept) SpanReplacement(s.start, s.end, _tokens[s.kind]!),
    ]);
    return ScrubResult(out, [
      for (final s in kept) ScrubToken(s.kind, _tokens[s.kind]!),
    ]);
  }
}

final class _Span {
  _Span(this.start, this.end, this.kind);

  final int start;
  final int end;
  final ScrubKind kind;
}
