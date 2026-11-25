import '../normalize/text_normalizer.dart';
import 'generic_keywords.dart';

/// Max length of a signature.
const int maxShapeSignatureLength = 80;

Set<String>? _cues;

Set<String> _cueWords() {
  return _cues ??= () {
    final out = <String>{};
    void addAll(Iterable<String> entries) {
      for (final e in entries) {
        for (final w in e.split(RegExp(r'\s+'))) {
          // Short words (and anything with a digit) are never cues: they
          // are the likeliest to collide with a name.
          if (w.length >= 3 && !RegExp(r'[0-9]').hasMatch(w)) out.add(w);
        }
      }
    }

    addAll(expenseKeywords);
    addAll(incomeKeywords);
    addAll(declineKeywords);
    addAll(promoKeywords);
    addAll(completedTransactionCues);
    addAll(balanceKeywords);
    addAll(amountCueKeywords);
    addAll(noticeFutureKeywords);
    addAll(noticeStatementKeywords);
    addAll(currencyWords.keys.map(foldKey));
    return Set.unmodifiable(out);
  }();
}

final RegExp _token = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final RegExp _arabic = RegExp(r'[؀-ۿ]');
final RegExp _hasDigit = RegExp(r'\p{N}', unicode: true);

/// T-248 (FU-305): a Latin token in Title Case or ALL CAPS may be a name or
/// merchant that equals a cue word, so it is not kept as a cue. Cue words in
/// lower case and Arabic words are kept.
bool _looksLikeName(String token) {
  if (_arabic.hasMatch(token)) return false;
  final c = token[0];
  return c != c.toLowerCase();
}

/// A text-free shape of [body] for diagnostics: digit-bearing tokens become
/// `9`, Latin words `A`, Arabic words `ع`; only dictionary cue words survive.
/// Pure and deterministic; no digit or letter of the message other than a
/// cue word is kept.
String shapeSignature(String body) {
  final cues = _cueWords();
  final parts = <String>[];
  // FU-313: drop tashkeel/tatweel first so a marked word is one token.
  for (final m in _token.allMatches(foldForMatching(body))) {
    final orig = m.group(0)!;
    final t = foldKey(orig);
    final String piece;
    if (_hasDigit.hasMatch(t)) {
      piece = '9';
    } else if (cues.contains(t) && !_looksLikeName(orig)) {
      piece = t;
    } else {
      piece = _arabic.hasMatch(t) ? 'ع' : 'A';
    }
    if (parts.isNotEmpty && parts.last == piece && piece.length == 1) continue;
    parts.add(piece);
  }
  final s = parts.join(' ');
  if (s.length <= maxShapeSignatureLength) return s;
  return s.substring(0, maxShapeSignatureLength).trimRight();
}
