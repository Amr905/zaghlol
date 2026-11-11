// T-046: `raw_messages.body_hash` version 1 (design note §3,
// database-schema §2.2). `hashNorm` is FROZEN: it is a copy, not a call into
// the parser normalizers, so a parser change can never make an inbox
// re-scan miss old rows. Changing it needs a migration that re-hashes
// raw_messages. Golden vectors: test/features/ingestion/domain/
// body_hash_test.dart. Pure Dart; nothing here logs.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show GuardChannel, guardSourceKey, foldKey;

/// The domain-separation tag of version 1.
const String bodyHashTagV1 = 'zg.raw.v1';

/// The sender key hashed with the body: `guardSourceKey` (trimmed package
/// for notifications, `foldKey` of the source otherwise). Channels the Guard
/// does not know (`paste`, `ocr`, `pdf`, `csv`) use `foldKey` like SMS.
String senderKeyOf(String channel, String source) {
  final guardChannel = GuardChannel.fromWire(channel);
  return guardChannel == null
      ? foldKey(source)
      : guardSourceKey(guardChannel, source);
}

/// The frozen body normalization: Arabic-Indic (U+0660..0669) and Extended
/// Arabic-Indic (U+06F0..06F9) digits to ASCII; `٫` → `.`, `٬` → `,`;
/// invisible marks removed (U+200B..200F, U+202A..202E, U+2066..2069,
/// U+061C, U+2060, U+00AD, U+FEFF); every whitespace run (U+0020,
/// U+0009..000D, U+0085, U+00A0, U+2009, U+202F, U+2028, U+2029) becomes one
/// space; trimmed. No case or letter folding.
String hashNorm(String body) {
  final out = StringBuffer();
  var pendingSpace = false;
  for (final r in body.runes) {
    if (_invisible(r)) continue;
    if (_space(r)) {
      pendingSpace = true;
      continue;
    }
    if (pendingSpace && out.isNotEmpty) out.writeCharCode(0x20);
    pendingSpace = false;
    if (r >= 0x0660 && r <= 0x0669) {
      out.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      out.writeCharCode(0x30 + r - 0x06F0);
    } else if (r == 0x066B) {
      out.writeCharCode(0x2E);
    } else if (r == 0x066C) {
      out.writeCharCode(0x2C);
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}

bool _invisible(int r) =>
    (r >= 0x200B && r <= 0x200F) ||
    (r >= 0x202A && r <= 0x202E) ||
    (r >= 0x2066 && r <= 0x2069) ||
    r == 0x061C ||
    r == 0x2060 ||
    r == 0x00AD ||
    r == 0xFEFF;

bool _space(int r) =>
    r == 0x20 ||
    (r >= 0x09 && r <= 0x0D) ||
    r == 0x85 ||
    r == 0xA0 ||
    r == 0x2009 ||
    r == 0x202F ||
    r == 0x2028 ||
    r == 0x2029;

/// Lowercase hex `SHA-256("zg.raw.v1" ‖ 0x00 ‖ senderKey ‖ 0x00 ‖
/// hashNorm(body))`. The receive time is not hashed: re-delivery and inbox
/// copies of one message must collide (BR-ING-02 rule 1).
String bodyHashV1({required String senderKey, required String body}) {
  final bytes = <int>[
    ...utf8.encode(bodyHashTagV1),
    0,
    ...utf8.encode(senderKey),
    0,
    ...utf8.encode(hashNorm(body)),
  ];
  return sha256.convert(bytes).toString();
}
