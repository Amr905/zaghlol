/// The categorizer (T-075, FR-CAT-03/04/06, BR-CAT-01/03; parsing-engine
/// §5 "Categorizer design").
///
/// Order, first hit stops: user rule (counterparty, then `merchant_norm`),
/// person-to-person stop, catalog exact, prefix/token, fuzzy (a rule on the
/// found merchant beats its catalog category), keywords, needs
/// classification. Deterministic: no clock, no randomness, every choice ends
/// in a total order. Failures of a port (database errors) propagate: a
/// failed lookup is never read as "no match".
library;

import 'alias_matcher.dart';
import 'keyword_scorer.dart';
import 'types.dart';

/// Categorizes with [ports]. One-shot form of [Categorizer].
Future<CategoryDecision> categorize(
  CategorizeInput input,
  CategorizerPorts ports, {
  CategorizerConfig config = const CategorizerConfig(),
}) => Categorizer(ports, config: config).categorize(input);

/// A categorizer for one run. It loads the keywords once and, with
/// [memoize], remembers each distinct input's decision, so a backfill over
/// many transactions categorizes each distinct merchant once. Create one per
/// run: the catalog, rules and keywords may change between runs.
final class Categorizer {
  Categorizer(
    this._ports, {
    this.config = const CategorizerConfig(),
    this.memoize = false,
  });

  final CategorizerPorts _ports;
  final CategorizerConfig config;
  final bool memoize;

  Future<List<KeywordEntry>>? _keywords;
  final Map<String, CategoryDecision> _memo = {};

  /// Decides the category of [input]. Never guesses on ambiguity.
  Future<CategoryDecision> categorize(CategorizeInput input) async {
    if (!memoize) return _decide(input);
    final k = input.memoKey;
    final hit = _memo[k];
    if (hit != null) return hit;
    return _memo[k] = await _decide(input);
  }

  static const CategoryDecision _none = CategoryDecision(
    source: CategorySource.none,
    tier: CategorizeTier.none,
  );

  Future<CategoryDecision> _decide(CategorizeInput input) async {
    final key = isMerchantKey(input.merchantNorm) ? input.merchantNorm : '';
    final cp = input.counterpartyValue;
    final counterparty = (cp == null || cp.isEmpty) ? null : cp;
    final kind = input.counterpartyKind;

    // Rules, call A: counterparty beats merchant_norm (A-68).
    if (counterparty != null || key.isNotEmpty) {
      final hit = await _ports.rules.match(
        counterparty: counterparty,
        merchantNorm: key.isEmpty ? null : key,
      );
      if (hit != null && await _ports.categories.isLive(hit.categoryId)) {
        return CategoryDecision(
          categoryId: hit.categoryId,
          source: CategorySource.userRule,
          ruleId: hit.ruleId,
          tier: CategorizeTier.rule,
        );
      }
      // A rule on an archived or missing category is ignored (fail closed).
    }

    if (kind == PartyKind.ownAccount) {
      return const CategoryDecision(
        source: CategorySource.none,
        tier: CategorizeTier.internal,
      );
    }
    if (kind != null && kind.isP2p) {
      return const CategoryDecision(
        source: CategorySource.none,
        tier: CategorizeTier.p2p,
      );
    }

    if (key.isNotEmpty) {
      final found = await _catalogMerchant(key);
      if (found != null) return _fromMerchant(found.$1, found.$2);
    }
    return _keywordTier(input.merchantText);
  }

  /// Steps 3 to 5: the merchant and the tier that found it.
  Future<(CatalogMerchant, CategorizeTier)?> _catalogMerchant(
    String key,
  ) async {
    // Exact: any match kind.
    final exact = await _ports.catalog.aliasesEqualTo(key);
    if (exact.isNotEmpty) {
      final m = await _single(exact);
      if (m != null) return (m, CategorizeTier.exact);
    }

    // Prefix / token.
    final prefixes = boundaryPrefixes(key).toSet();
    final runs = tokenRuns(key, maxTokens: config.maxTokenRun);
    final hits = await _ports.catalog.aliasesByKeys(
      {...prefixes, ...runs},
      const {AliasMatch.prefix, AliasMatch.token},
    );
    final best = matchAliases(key, hits, maxTokens: config.maxTokenRun);
    if (best.isNotEmpty) {
      final m = await _single(best);
      if (m != null) {
        return (
          m,
          best.first.match == AliasMatch.prefix
              ? CategorizeTier.prefix
              : CategorizeTier.token,
        );
      }
    }

    // Fuzzy.
    if (key.replaceAll(' ', '').length >= config.fuzzyMinKeyLength) {
      final cands = await _ports.catalog.aliasCandidates(
        key,
        limit: config.fuzzyCandidates,
      );
      if (cands.isNotEmpty) {
        final merchants = await _merchants(cands);
        final pick = pickFuzzy(key, cands, merchants, config);
        final m = pick.merchant;
        if (m != null) return (m, CategorizeTier.fuzzy);
      }
    }
    return null;
  }

  Future<Map<int, CatalogMerchant>> _merchants(Iterable<AliasHit> hits) async =>
      {
        for (final m in await _ports.catalog.merchantsByIds({
          for (final h in hits) h.merchantId,
        }))
          m.id: m,
      };

  Future<CatalogMerchant?> _single(List<AliasHit> hits) async =>
      pickMerchant(hits, await _merchants(hits));

  /// A rule on the merchant beats its category (call B); else the merchant's
  /// category, when live.
  Future<CategoryDecision> _fromMerchant(
    CatalogMerchant m,
    CategorizeTier tier,
  ) async {
    final rule = await _ports.rules.match(catalogMerchantId: m.id);
    if (rule != null && await _ports.categories.isLive(rule.categoryId)) {
      return CategoryDecision(
        categoryId: rule.categoryId,
        catalogMerchantId: m.id,
        source: CategorySource.userRule,
        ruleId: rule.ruleId,
        tier: CategorizeTier.rule,
      );
    }
    final id = await _ports.categories.liveIdBySystemCode(m.categoryCode);
    if (id == null) {
      // Merchant known, category archived or unknown: keep the merchant.
      return CategoryDecision(
        catalogMerchantId: m.id,
        source: CategorySource.none,
        tier: tier,
      );
    }
    return CategoryDecision(
      categoryId: id,
      catalogMerchantId: m.id,
      source: CategorySource.catalog,
      tier: tier,
    );
  }

  Future<CategoryDecision> _keywordTier(String merchantText) async {
    if (merchantText.trim().isEmpty) return _none;
    final keywords = await (_keywords ??= _ports.keywords.all());
    final code = decideKeywords(
      scoreKeywords(merchantText, keywords),
      minScore: config.keywordMinScore,
      margin: config.keywordMargin,
    );
    if (code == null) return _none;
    final id = await _ports.categories.liveIdBySystemCode(code);
    if (id == null) return _none;
    return CategoryDecision(
      categoryId: id,
      source: CategorySource.heuristic,
      tier: CategorizeTier.keyword,
    );
  }
}
