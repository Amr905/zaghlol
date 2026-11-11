/// Value types and ports of the categorizer (T-075, parsing-engine §5).
/// Pure Dart: no Flutter, no Drift, no I/O. The application layer
/// implements the ports (`app/lib/features/categorization/data/`).
///
/// Nothing here carries merchant text in a message: [CategoryDecision]
/// holds ids and enums only, so it is safe to log.
library;

/// Counterparty kinds as stored (the `transactions.counterparty_kind`
/// values; named apart from the parser's `CounterpartyKind`).
enum PartyKind {
  merchant,
  ipa,
  phone,
  person,
  bank,
  ownAccount;

  /// Person-to-person kinds (BR-CAT-03): no catalog, no keywords. `person`
  /// is added to the spec's ipa/phone (conservative; PO-2, provisional).
  bool get isP2p => this == ipa || this == phone || this == person;

  /// Parses the stored code; unknown codes give null.
  static PartyKind? tryParse(String? code) => switch (code) {
    'merchant' => merchant,
    'ipa' => ipa,
    'phone' => phone,
    'person' => person,
    'bank' => bank,
    'own_account' => ownAccount,
    _ => null,
  };
}

/// Who decided the category. [code] is the stored `category_source`.
/// `user` is never produced here, and `is_user_verified` is never set.
enum CategorySource {
  none('none'),
  userRule('user_rule'),
  catalog('catalog'),
  heuristic('heuristic');

  const CategorySource(this.code);
  final String code;
}

/// The step that decided. For the accuracy report only: never stored, and
/// never logged together with text.
enum CategorizeTier {
  rule,
  p2p,
  internal,
  exact,
  prefix,
  token,
  fuzzy,
  keyword,
  none,
}

/// What the categorizer needs from one transaction.
final class CategorizeInput {
  const CategorizeInput({
    this.merchantNorm = '',
    this.merchantText = '',
    this.counterpartyKind,
    this.counterpartyValue,
  });

  /// `merchant_norm`: a canonical key, or empty for "no merchant".
  final String merchantNorm;

  /// `foldKey(cleanMerchant(merchant_raw).cleaned)`: Arabic kept (the key is
  /// transliterated), used for keywords only.
  final String merchantText;

  final PartyKind? counterpartyKind;
  final String? counterpartyValue;

  /// Memo key for one run (ASCII unit separators; never printed).
  String get memoKey =>
      '$merchantNorm\u001f$merchantText\u001f${counterpartyKind?.name}\u001f${counterpartyValue ?? ''}';

  @override
  String toString() => 'CategorizeInput(<redacted>)';
}

/// The result. [categoryId] is a live category id or null (needs
/// classification). [catalogMerchantId] is kept even when [categoryId] is
/// null (merchant found, category unusable).
final class CategoryDecision {
  const CategoryDecision({
    required this.source,
    required this.tier,
    this.categoryId,
    this.catalogMerchantId,
    this.ruleId,
  });

  final String? categoryId;
  final int? catalogMerchantId;
  final CategorySource source;
  final String? ruleId;
  final CategorizeTier tier;

  /// No category: the transaction needs classification.
  bool get needsClassification => categoryId == null;

  @override
  bool operator ==(Object other) =>
      other is CategoryDecision &&
      other.categoryId == categoryId &&
      other.catalogMerchantId == catalogMerchantId &&
      other.source == source &&
      other.ruleId == ruleId &&
      other.tier == tier;

  @override
  int get hashCode =>
      Object.hash(categoryId, catalogMerchantId, source, ruleId, tier);

  @override
  String toString() =>
      'CategoryDecision(${source.code}, ${tier.name}, category: $categoryId, '
      'merchant: $catalogMerchantId, rule: $ruleId)';
}

/// `catalog_aliases.match`.
enum AliasMatch {
  exact,
  prefix,
  token;

  static AliasMatch? tryParse(String code) => switch (code) {
    'exact' => exact,
    'prefix' => prefix,
    'token' => token,
    _ => null,
  };
}

/// One `catalog_aliases` row.
final class AliasHit {
  const AliasHit({
    required this.id,
    required this.aliasNorm,
    required this.merchantId,
    required this.match,
  });

  final int id;
  final String aliasNorm;
  final int merchantId;
  final AliasMatch match;
}

/// The parts of a `catalog_merchants` row the categorizer needs.
final class CatalogMerchant {
  const CatalogMerchant({
    required this.id,
    required this.canonical,
    required this.categoryCode,
  });

  final int id;
  final String canonical;
  final String categoryCode;
}

/// One `catalog_keywords` row (stored folded).
final class KeywordEntry {
  const KeywordEntry({
    required this.keywordNorm,
    required this.categoryCode,
    required this.weight,
  });

  final String keywordNorm;
  final String categoryCode;
  final int weight;
}

/// A user rule that matched. [categoryId] may name an archived or missing
/// category; the categorizer checks it with [CategoryPort.isLive].
final class RuleHit {
  const RuleHit({required this.ruleId, required this.categoryId});

  final String ruleId;
  final String categoryId;
}

/// User rules (T-074). Precedence inside one call: counterparty, then
/// `merchant_norm`, then catalog merchant (A-68).
abstract interface class RulePort {
  Future<RuleHit?> match({
    String? counterparty,
    String? merchantNorm,
    int? catalogMerchantId,
  });
}

/// Catalog lookups (T-018). Every key passed in is a canonical merchant key.
abstract interface class CatalogPort {
  /// Aliases whose `alias_norm` equals [key], any match kind.
  Future<List<AliasHit>> aliasesEqualTo(String key);

  /// Aliases whose `alias_norm` is in [keys] and whose kind is in [kinds]:
  /// one `IN (...)` query on the primary index, never `LIKE`.
  Future<List<AliasHit>> aliasesByKeys(Set<String> keys, Set<AliasMatch> kinds);

  /// FTS5 trigram candidates for [key], best rank first, at most [limit].
  Future<List<AliasHit>> aliasCandidates(String key, {int limit});

  /// The merchants [ids] (unknown ids are absent from the result).
  Future<List<CatalogMerchant>> merchantsByIds(Set<int> ids);
}

/// All catalog keywords, both languages; loaded once per run.
abstract interface class KeywordPort {
  Future<List<KeywordEntry>> all();
}

/// Category lookups.
abstract interface class CategoryPort {
  /// The id of the live (not archived) system category [code], else null.
  Future<String?> liveIdBySystemCode(String code);

  /// Whether category [id] exists and is not archived.
  Future<bool> isLive(String id);
}

/// The four ports.
final class CategorizerPorts {
  const CategorizerPorts({
    required this.rules,
    required this.catalog,
    required this.keywords,
    required this.categories,
  });

  final RulePort rules;
  final CatalogPort catalog;
  final KeywordPort keywords;
  final CategoryPort categories;
}

/// Tunable decision points (the note's defaults).
final class CategorizerConfig {
  const CategorizerConfig({
    this.fuzzyThreshold = 920000,
    this.contributedThreshold = 880000,
    this.contributedAliasIds = const {},
    this.fuzzyMinKeyLength = 6,
    this.fuzzyAmbiguityMargin = 20000,
    this.fuzzyCandidates = 10,
    this.keywordMinScore = 60,
    this.keywordMargin = 20,
    this.maxTokenRun = 6,
    this.scorer,
  });

  /// Fuzzy acceptance for ordinary aliases, in millionths (0.92 is
  /// 920000; see `jaro_winkler.dart`).
  final int fuzzyThreshold;

  /// Fuzzy acceptance for contributed aliases. PROVISIONAL (PO-1): the
  /// catalog cannot say which aliases are contributed, so
  /// [contributedAliasIds] is empty and this value is unused.
  final int contributedThreshold;
  final Set<int> contributedAliasIds;

  /// Fuzzy needs this many characters, spaces removed. PROVISIONAL (PO-3).
  final int fuzzyMinKeyLength;

  /// A runner-up of another category within this score makes the fuzzy step
  /// ambiguous. PROVISIONAL (PO-3).
  final int fuzzyAmbiguityMargin;
  final int fuzzyCandidates;
  final int keywordMinScore;
  final int keywordMargin;

  /// Longest token run looked up in the token step.
  final int maxTokenRun;

  /// Replaces [jaroWinklerScore] (tests only).
  final int Function(String a, String b)? scorer;
}
