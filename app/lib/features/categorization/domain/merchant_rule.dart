// T-074: user merchant rules as domain values (pure Dart; no Flutter, no
// Drift). A rule maps a merchant or counterparty to a category and beats the
// catalog (BR-CAT-01, FR-CAT-05/08). Rules are never uploaded. Nothing here
// is ever logged.

import 'package:zaghlol_domain/zaghlol_domain.dart';

/// What a rule matches on. [code] is the stored `match_kind`.
enum RuleMatchKind {
  catalogMerchant('catalog_merchant'),
  merchantNorm('merchant_norm'),
  counterparty('counterparty');

  const RuleMatchKind(this.code);
  final String code;

  static RuleMatchKind? tryFromCode(String code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// A saved rule.
final class MerchantRule {
  const MerchantRule({
    required this.id,
    required this.kind,
    required this.value,
    required this.categoryId,
    required this.createdAt,
    this.lastAppliedAt,
  });

  final String id;
  final RuleMatchKind kind;

  /// Catalog merchant id (decimal text), `merchant_norm` key or counterparty
  /// value, by [kind].
  final String value;
  final String categoryId;
  final DateTime createdAt;
  final DateTime? lastAppliedAt;
}

/// The rule that decides a transaction's category.
final class RuleMatch {
  const RuleMatch({required this.ruleId, required this.categoryId});

  final String ruleId;
  final String categoryId;
}

/// Failures of the rules repository. Codes only: no rule value, merchant or
/// counterparty text is ever carried.
final class RulesException extends SafeException {
  RulesException(super.code);

  static const String invalid = 'RULE_INVALID';
  static const String notFound = 'RULE_NOT_FOUND';
  static const String categoryUnavailable = 'RULE_CATEGORY_UNAVAILABLE';
  static const String corruptRow = 'RULE_CORRUPT_ROW';
}

/// The user's merchant rules (FR-CAT-05/08).
abstract interface class RulesRepository {
  /// All rules, oldest first.
  Future<List<MerchantRule>> list();

  /// Creates the rule for ([kind], [value]) or, when one exists, points it at
  /// [categoryId]. Applies to future transactions only; past ones change only
  /// through [applyToPast]. Throws [RulesException] (`RULE_INVALID`,
  /// `RULE_CATEGORY_UNAVAILABLE` for an unknown or archived category).
  Future<MerchantRule> save({
    required RuleMatchKind kind,
    required String value,
    required String categoryId,
  });

  /// Points rule [id] at [categoryId] (`RULE_NOT_FOUND` when absent).
  Future<MerchantRule> changeCategory(String id, String categoryId);

  /// Deletes rule [id]. Transactions it already categorized keep their
  /// category. Returns whether a rule was removed.
  Future<bool> delete(String id);

  /// How many past transactions [applyToPast] would change for rule [id]
  /// (A-13: shown before the user confirms).
  Future<int> countPastMatches(String id);

  /// Ids of up to [limit] past transactions [applyToPast] would change,
  /// newest first (the list the user picks from).
  Future<List<String>> pastMatchIds(String id, {int limit = 200});

  /// Recategorizes exactly the transactions in [transactionIds] that still
  /// qualify (live, not internal, not user-verified, categorized by the
  /// pipeline, matching the rule, not already in its category), and nothing
  /// else. With [transactionIds] null, every qualifying match. Returns the
  /// number changed. User edits are never overwritten.
  Future<int> applyToPast(String id, {Set<String>? transactionIds});

  /// The rule that wins for a transaction with these keys, if any. Any rule
  /// beats the catalog; among rules the order is counterparty, then
  /// `merchant_norm`, then catalog merchant.
  Future<RuleMatch?> match({
    String? counterparty,
    String? merchantNorm,
    int? catalogMerchantId,
  });
}
