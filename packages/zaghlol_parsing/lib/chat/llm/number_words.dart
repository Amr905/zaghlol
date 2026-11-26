/// Number words a plan amount may come from instead of a digit string
/// (ask-llm.md 2.2 "Amount"; the shared vectors' `numberWords`, minimum
/// list). Matched after `foldKey`, as whole words. T-331.
library;

import '../../normalize/text_normalizer.dart';

/// Word (already folded) to canonical decimal string.
final Map<String, String> planNumberWords = {
  for (final e in const {
    'ألف': '1000',
    'الف': '1000',
    'ميت': '100',
    'مية': '100',
    'مئة': '100',
    'مليون': '1000000',
    'thousand': '1000',
    'hundred': '100',
    'million': '1000000',
  }.entries)
    foldKey(e.key): e.value,
};

final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// True when [word] occurs in [folded] with no letter or digit next to it.
bool containsWholeWord(String folded, String word) {
  if (word.isEmpty) return false;
  var from = 0;
  while (from <= folded.length - word.length) {
    final at = folded.indexOf(word, from);
    if (at < 0) return false;
    final end = at + word.length;
    final before = at == 0 || !_letterOrDigit.hasMatch(folded[at - 1]);
    final after = end == folded.length || !_letterOrDigit.hasMatch(folded[end]);
    if (before && after) return true;
    from = at + 1;
  }
  return false;
}

/// Canonical values of the number words found in [foldedSent].
Set<String> numberWordValues(String foldedSent) => {
  for (final e in planNumberWords.entries)
    if (containsWholeWord(foldedSent, e.key)) e.value,
};

/// Canonical form of a non-negative decimal string: no thousands commas, no
/// leading zeros in the integer part, no trailing zeros in the fraction.
/// `500`, `500.00` and `0500` are all `500`.
String canonicalDecimal(String s) {
  final t = s.replaceAll(',', '');
  final dot = t.indexOf('.');
  var whole = dot < 0 ? t : t.substring(0, dot);
  var frac = dot < 0 ? '' : t.substring(dot + 1);
  whole = whole.replaceFirst(RegExp(r'^0+'), '');
  if (whole.isEmpty) whole = '0';
  frac = frac.replaceFirst(RegExp(r'0+$'), '');
  return frac.isEmpty ? whole : '$whole.$frac';
}
