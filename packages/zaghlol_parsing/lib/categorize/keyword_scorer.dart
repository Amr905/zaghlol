/// Keyword heuristics (T-075, parsing-engine §5 step 5). Pure.
library;

import '../normalize/text_normalizer.dart';
import 'types.dart';

final RegExp _splitter = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

List<String> _tokenize(String folded) => [
  for (final t in folded.split(_splitter))
    if (t.isNotEmpty) t,
];

/// A token without a leading `ال`, when something is left.
String _withoutArticle(String t) =>
    t.length > 2 && t.startsWith('ال') ? t.substring(2) : t;

/// Per category code, the sum of the weights of the distinct keywords found
/// in [merchantText]. Whole tokens only (no substring matching), a leading
/// `ال` on a text token ignored, multi-word keywords match a contiguous run
/// of tokens. Latin and Arabic keywords both count; a keyword listed in two
/// languages counts once. Text and keywords are folded with [foldKey].
Map<String, int> scoreKeywords(
  String merchantText,
  Iterable<KeywordEntry> keywords,
) {
  final text = _tokenize(foldKey(merchantText));
  if (text.isEmpty) return const {};
  final bare = [for (final t in text) _withoutArticle(t)];
  final seen = <String>{};
  final scores = <String, int>{};
  for (final k in keywords) {
    final kt = _tokenize(foldKey(k.keywordNorm));
    if (kt.isEmpty || !_contains(text, bare, kt)) continue;
    // Distinct per (category, keyword): one keyword never counts twice.
    if (!seen.add('${k.categoryCode}\u001f${kt.join(' ')}')) continue;
    scores[k.categoryCode] = (scores[k.categoryCode] ?? 0) + k.weight;
  }
  return scores;
}

bool _contains(List<String> text, List<String> bare, List<String> kw) {
  for (var i = 0; i + kw.length <= text.length; i++) {
    var all = true;
    for (var j = 0; j < kw.length; j++) {
      if (text[i + j] != kw[j] && bare[i + j] != kw[j]) {
        all = false;
        break;
      }
    }
    if (all) return true;
  }
  return false;
}

/// The winning category code: top score at least [minScore] and ahead of
/// the runner-up (0 when none) by at least [margin]; else null.
String? decideKeywords(
  Map<String, int> scores, {
  int minScore = 60,
  int margin = 20,
}) {
  if (scores.isEmpty) return null;
  final entries = scores.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  final top = entries.first;
  final second = entries.length > 1 ? entries[1].value : 0;
  if (top.value < minScore || top.value - second < margin) return null;
  return top.key;
}
