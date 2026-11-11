/// Pure alias selection for the categorizer (T-075, parsing-engine §5
/// steps 2 to 4). No I/O.
library;

import 'jaro_winkler.dart';
import 'types.dart';

final RegExp _canonicalKey = RegExp(r'^[a-z0-9]+( [a-z0-9]+)*$');

/// Whether [key] is a canonical merchant key (`[a-z0-9]` words, single
/// spaces, at most 64 characters): the form stored in
/// `catalog_aliases.alias_norm` and `merchant_norm`.
bool isMerchantKey(String key) =>
    key.length <= 64 && _canonicalKey.hasMatch(key);

/// The token-boundary prefixes of [key]: `a b c` gives `a`, `a b`, `a b c`.
List<String> boundaryPrefixes(String key) {
  final tokens = key.split(' ');
  return [for (var i = 1; i <= tokens.length; i++) tokens.take(i).join(' ')];
}

/// All contiguous token runs of [key] of 1 to [maxTokens] tokens, distinct.
Set<String> tokenRuns(String key, {int maxTokens = 6}) {
  final tokens = key.split(' ');
  final out = <String>{};
  for (var i = 0; i < tokens.length; i++) {
    for (var n = 1; n <= maxTokens && i + n <= tokens.length; n++) {
      out.add(tokens.sublist(i, i + n).join(' '));
    }
  }
  return out;
}

int _tokens(String s) => ' '.allMatches(s).length + 1;

/// Steps 3 and 4 selection: of [hits] (aliases found for [key]) keeps those
/// that match on whole-token boundaries (`prefix`: the key starts with the
/// alias; `token`: the alias is a token run), and returns the best level:
/// longest alias (characters, then tokens), `prefix` over `token`. All hits
/// tied at the best level are returned (several merchants may share one
/// alias). Empty when nothing matches. Input order never matters.
List<AliasHit> matchAliases(
  String key,
  Iterable<AliasHit> hits, {
  int maxTokens = 6,
}) {
  final prefixes = boundaryPrefixes(key).toSet();
  final runs = tokenRuns(key, maxTokens: maxTokens);
  final ok = <AliasHit>[
    for (final h in hits)
      if ((h.match == AliasMatch.prefix && prefixes.contains(h.aliasNorm)) ||
          (h.match == AliasMatch.token && runs.contains(h.aliasNorm)))
        h,
  ];
  if (ok.isEmpty) return const [];
  int cmp(AliasHit a, AliasHit b) {
    var c = b.aliasNorm.length.compareTo(a.aliasNorm.length);
    if (c != 0) return c;
    c = _tokens(b.aliasNorm).compareTo(_tokens(a.aliasNorm));
    if (c != 0) return c;
    final ap = a.match == AliasMatch.prefix ? 0 : 1;
    final bp = b.match == AliasMatch.prefix ? 0 : 1;
    return ap.compareTo(bp);
  }

  ok.sort(cmp);
  return [
    for (final h in ok)
      if (cmp(ok.first, h) == 0) h,
  ];
}

/// Of the best-level [hits], the single merchant to use, or null when the
/// level is ambiguous (merchants of more than one category: never guess).
/// Several merchants of one category: lowest `canonical` (ASCII order),
/// then id. Merchants missing from [merchants] are ignored.
CatalogMerchant? pickMerchant(
  Iterable<AliasHit> hits,
  Map<int, CatalogMerchant> merchants,
) {
  final found = <int, CatalogMerchant>{
    for (final h in hits)
      if (merchants[h.merchantId] != null)
        h.merchantId: merchants[h.merchantId]!,
  };
  if (found.isEmpty) return null;
  if (found.values.map((m) => m.categoryCode).toSet().length > 1) return null;
  return _firstByCanonical(found.values);
}

CatalogMerchant _firstByCanonical(Iterable<CatalogMerchant> ms) {
  final list = ms.toList()
    ..sort((a, b) {
      final c = a.canonical.compareTo(b.canonical);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  return list.first;
}

/// Digit characters of [s], in order.
String digitsOf(String s) =>
    String.fromCharCodes(s.codeUnits.where((u) => u >= 0x30 && u <= 0x39));

/// Fuzzy score of [alias] against [key]: the larger of Jaro-Winkler on both
/// and on both with spaces removed. Both are canonical keys already.
int fuzzyScore(
  String alias,
  String key, [
  int Function(String, String)? scorer,
]) {
  final f = scorer ?? jaroWinklerScore;
  final a = f(alias, key);
  final b = f(alias.replaceAll(' ', ''), key.replaceAll(' ', ''));
  return a > b ? a : b;
}

/// Outcome of [pickFuzzy].
final class FuzzyPick {
  const FuzzyPick(this.merchant, this.score, {this.ambiguous = false});

  /// The merchant, or null when nothing qualified or the step is ambiguous.
  final CatalogMerchant? merchant;
  final int score;
  final bool ambiguous;
}

/// Step 4 selection over FTS [candidates] for [key]. A candidate counts when
/// its digit characters equal the key's and its score reaches the threshold
/// (`config.contributedThreshold` for aliases in `contributedAliasIds`).
/// Best score per merchant; merchants ordered by (score, Jaro, canonical,
/// id), so input order never matters. Ambiguous (null merchant) when a
/// runner-up of another category scores within the margin of the winner.
FuzzyPick pickFuzzy(
  String key,
  Iterable<AliasHit> candidates,
  Map<int, CatalogMerchant> merchants,
  CategorizerConfig config,
) {
  if (key.replaceAll(' ', '').length < config.fuzzyMinKeyLength) {
    return const FuzzyPick(null, 0);
  }
  final keyDigits = digitsOf(key);
  final best = <int, ({int score, int jaro})>{};
  final accepted = <int>{};
  for (final c in candidates) {
    if (merchants[c.merchantId] == null) continue;
    if (digitsOf(c.aliasNorm) != keyDigits) continue;
    final score = fuzzyScore(c.aliasNorm, key, config.scorer);
    final jaroOf = jaroScore(c.aliasNorm, key);
    final cur = best[c.merchantId];
    if (cur == null ||
        score > cur.score ||
        (score == cur.score && jaroOf > cur.jaro)) {
      best[c.merchantId] = (score: score, jaro: jaroOf);
    }
    // The threshold is per candidate alias (contributed aliases differ).
    final threshold = config.contributedAliasIds.contains(c.id)
        ? config.contributedThreshold
        : config.fuzzyThreshold;
    if (score >= threshold) {
      accepted.add(c.merchantId);
    }
  }
  if (accepted.isEmpty) return const FuzzyPick(null, 0);
  final ordered = best.entries.toList()
    ..sort((a, b) {
      var c = b.value.score.compareTo(a.value.score);
      if (c != 0) return c;
      c = b.value.jaro.compareTo(a.value.jaro);
      if (c != 0) return c;
      final ma = merchants[a.key]!;
      final mb = merchants[b.key]!;
      c = ma.canonical.compareTo(mb.canonical);
      return c != 0 ? c : ma.id.compareTo(mb.id);
    });
  // The winner is the best-ordered merchant that was accepted.
  final winnerEntry = ordered.firstWhere((e) => accepted.contains(e.key));
  final winner = merchants[winnerEntry.key]!;
  for (final e in ordered) {
    if (e.key == winnerEntry.key) continue;
    final other = merchants[e.key]!;
    if (other.categoryCode == winner.categoryCode) continue;
    if (winnerEntry.value.score - e.value.score < config.fuzzyAmbiguityMargin) {
      return FuzzyPick(null, winnerEntry.value.score, ambiguous: true);
    }
  }
  return FuzzyPick(winner, winnerEntry.value.score);
}
