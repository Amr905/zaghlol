// T-075: the Drift-backed ports of the categorizer (`zaghlol_parsing`,
// `categorize/types.dart`). Thin adapters: they add no logic and no schema.
// Read failures stay code-only `DbReadException`s and propagate: a failed
// lookup is never read as "no match". Nothing here logs.

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/catalog_dao.dart';
import '../../../core/db/daos/categories_dao.dart';
import '../domain/merchant_rule.dart' show RulesRepository;

export '../domain/categorize_input.dart' show categorizeInputFor;

/// [CatalogPort] over [CatalogDao].
final class DriftCatalogPort implements CatalogPort {
  DriftCatalogPort(this._dao);

  final CatalogDao _dao;

  AliasHit? _hit(CatalogAliasRow r) {
    final m = AliasMatch.tryParse(r.match);
    if (m == null) return null; // the CHECK makes this unreachable
    return AliasHit(
      id: r.id,
      aliasNorm: r.aliasNorm,
      merchantId: r.merchantId,
      match: m,
    );
  }

  List<AliasHit> _hits(List<CatalogAliasRow> rows) => [
    for (final r in rows) ?_hit(r),
  ];

  @override
  Future<List<AliasHit>> aliasesEqualTo(String key) async =>
      _hits(await _dao.aliasesEqualTo(key));

  @override
  Future<List<AliasHit>> aliasesByKeys(
    Set<String> keys,
    Set<AliasMatch> kinds,
  ) async =>
      _hits(await _dao.aliasesByKeys(keys, {for (final k in kinds) k.name}));

  @override
  Future<List<AliasHit>> aliasCandidates(String key, {int limit = 10}) async =>
      _hits(await _dao.aliasCandidates(key, limit: limit));

  @override
  Future<List<CatalogMerchant>> merchantsByIds(Set<int> ids) async => [
    for (final m in await _dao.merchantsByIds(ids))
      CatalogMerchant(
        id: m.id,
        canonical: m.canonical,
        categoryCode: m.categoryCode,
      ),
  ];
}

/// [KeywordPort] over [CatalogDao].
final class DriftKeywordPort implements KeywordPort {
  DriftKeywordPort(this._dao);

  final CatalogDao _dao;

  @override
  Future<List<KeywordEntry>> all() async => [
    for (final k in await _dao.allKeywords())
      KeywordEntry(
        keywordNorm: k.keywordNorm,
        categoryCode: k.categoryCode,
        weight: k.weight,
      ),
  ];
}

/// [CategoryPort] over [CategoriesDao].
final class DriftCategoryPort implements CategoryPort {
  DriftCategoryPort(this._dao);

  final CategoriesDao _dao;

  @override
  Future<String?> liveIdBySystemCode(String code) async {
    final c = await _dao.bySystemCode(code);
    return (c == null || c.isArchived != 0) ? null : c.id;
  }

  @override
  Future<bool> isLive(String id) async {
    final c = await _dao.byId(id);
    return c != null && c.isArchived == 0;
  }
}

/// [RulePort] over [RulesRepository] (T-074).
final class RepositoryRulePort implements RulePort {
  RepositoryRulePort(this._rules);

  final RulesRepository _rules;

  @override
  Future<RuleHit?> match({
    String? counterparty,
    String? merchantNorm,
    int? catalogMerchantId,
  }) async {
    final m = await _rules.match(
      counterparty: counterparty,
      merchantNorm: merchantNorm,
      catalogMerchantId: catalogMerchantId,
    );
    return m == null
        ? null
        : RuleHit(ruleId: m.ruleId, categoryId: m.categoryId);
  }
}

/// The four ports over one database.
CategorizerPorts driftCategorizerPorts(AppDatabase db, RulesRepository rules) =>
    CategorizerPorts(
      rules: RepositoryRulePort(rules),
      catalog: DriftCatalogPort(CatalogDao(db)),
      keywords: DriftKeywordPort(CatalogDao(db)),
      categories: DriftCategoryPort(CategoriesDao(db)),
    );
