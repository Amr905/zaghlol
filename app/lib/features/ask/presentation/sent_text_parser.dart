// T-346: turns the masked question (`MaskResult.sentText`) into the segments
// the consent preview and "What I sent" draw (T-345). Placeholders become
// numbered chips; scrub tokens become hidden chips. Nothing here knows what a
// placeholder stands for (FR-LLM-19).

import 'sent_disclosure.dart';

final RegExp _token = RegExp(r'⟦([A-Z]+)(?:_(\d{1,2}))?⟧');

SentChipKind _chipKind(String name) => switch (name) {
  'ACCOUNT' => SentChipKind.account,
  'CARD' => SentChipKind.card,
  'BANK' => SentChipKind.bank,
  'MERCHANT' => SentChipKind.merchant,
  _ => SentChipKind.other,
};

SentHiddenKind _hiddenKind(String name) => switch (name) {
  'PHONE' => SentHiddenKind.phone,
  'EMAIL' => SentHiddenKind.email,
  'IPA' => SentHiddenKind.instapay,
  'NUMBER' => SentHiddenKind.number,
  _ => SentHiddenKind.other,
};

/// Splits [sentText] into plain text, placeholder chips and hidden chips.
List<SentSegment> parseSentText(String sentText) {
  final out = <SentSegment>[];
  var at = 0;
  for (final m in _token.allMatches(sentText)) {
    if (m.start > at) out.add(SentPlain(sentText.substring(at, m.start)));
    final n = m.group(2);
    out.add(
      n == null
          ? SentHidden(_hiddenKind(m.group(1)!))
          : SentPlaceholder(_chipKind(m.group(1)!), int.parse(n)),
    );
    at = m.end;
  }
  if (at < sentText.length) out.add(SentPlain(sentText.substring(at)));
  return out;
}
