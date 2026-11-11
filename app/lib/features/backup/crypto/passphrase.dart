// T-148: the passphrase input P (design note §4). UTF-8 of: the typed string
// → Arabic-Indic (U+0660..U+0669) and Extended Arabic-Indic (U+06F0..U+06F9)
// digits to ASCII → every Unicode space separator (Zs) to U+0020 → NFC. No
// trimming, no case folding.
//
// Digit folding is PROVISIONAL — PO to confirm (design note §11 question 3):
// `٣٤٥` and `345` open the same backup. The single decision point is
// [foldPassphraseDigits].
//
// NFC comes from the platform (TextNormalizationHostApi) because Dart has no
// normalizer. A string with no code point at or above U+0300 is already NFC
// (it holds no combining mark and every precomposed character below U+0300 is
// NFC-stable), so it never needs the channel.

import 'dart:convert';
import 'dart:typed_data';

import 'backup_crypto_exception.dart';

/// PROVISIONAL — PO to confirm (design note §11 question 3). When true,
/// Arabic-Indic and Extended Arabic-Indic digits are folded to ASCII before
/// the KDF. Changing it after release would lock users out of their backups.
const bool foldPassphraseDigits = true;

/// Minimum passphrase length in Unicode code points after normalization
/// (security-model §5).
const int minPassphraseLength = 8;

/// Unicode canonical composition (NFC). Implemented natively; tests use a
/// fake.
abstract interface class TextNormalizer {
  /// Returns the NFC form of [input]. Throws on failure; never logs [input].
  Future<String> nfc(String input);
}

/// The Unicode `Zs` (space separator) code points.
const Set<int> _spaceSeparators = {
  0x0020, 0x00A0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, //
  0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x202F, 0x205F, 0x3000,
};

/// Folds digits (when [foldPassphraseDigits]) and space separators. Pure;
/// exposed for tests.
String foldPassphrase(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    if (foldPassphraseDigits && rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + rune - 0x0660);
    } else if (foldPassphraseDigits && rune >= 0x06F0 && rune <= 0x06F9) {
      out.writeCharCode(0x30 + rune - 0x06F0);
    } else if (_spaceSeparators.contains(rune)) {
      out.writeCharCode(0x20);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// Turns a typed passphrase into P.
final class PassphraseEncoder {
  PassphraseEncoder(this._normalizer);

  final TextNormalizer _normalizer;

  /// The normalized string (before UTF-8). Throws BackupCryptoException(io)
  /// when the normalizer fails: an un-normalized fallback would derive a
  /// different key on the other platform.
  Future<String> normalize(String passphrase) async {
    final folded = foldPassphrase(passphrase);
    if (!folded.runes.any((r) => r >= 0x0300)) return folded;
    try {
      return await _normalizer.nfc(folded);
    } on Object {
      throw BackupCryptoException(BackupCryptoErrorCode.io);
    }
  }

  /// P = UTF-8(normalize(passphrase)). The caller zeroes the result.
  Future<Uint8List> encode(String passphrase) async =>
      Uint8List.fromList(utf8.encode(await normalize(passphrase)));

  /// P for a new passphrase: also enforces the minimum length.
  Future<Uint8List> encodeNew(String passphrase) async {
    final normalized = await normalize(passphrase);
    if (normalized.runes.length < minPassphraseLength) {
      throw BackupCryptoException(BackupCryptoErrorCode.passphraseTooShort);
    }
    return Uint8List.fromList(utf8.encode(normalized));
  }
}
