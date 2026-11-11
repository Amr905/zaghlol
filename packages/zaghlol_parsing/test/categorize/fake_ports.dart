// In-memory ports for the categorizer tests (T-075). Synthetic catalog data
// only. `shuffleSeed` reorders every list a port returns, to prove the
// decision never depends on input order.

import 'dart:math';

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

final class FakeRules implements RulePort {
  FakeRules();

  /// (kind, value) -> RuleHit; kinds: counterparty, merchant_norm,
  /// catalog_merchant.
  final Map<(String, String), RuleHit> rules = {};
  final List<String> calls = [];

  void add(String kind, String value, String category, {String? id}) {
    rules[(kind, value)] = RuleHit(
      ruleId: id ?? 'r-$kind-$value',
      categoryId: category,
    );
  }

  @override
  Future<RuleHit?> match({
    String? counterparty,
    String? merchantNorm,
    int? catalogMerchantId,
  }) async {
    calls.add(
      catalogMerchantId != null
          ? 'B'
          : 'A${counterparty != null ? ':cp' : ''}'
                '${merchantNorm != null ? ':norm' : ''}',
    );
    return (counterparty == null
            ? null
            : rules[('counterparty', counterparty)]) ??
        (merchantNorm == null
            ? null
            : rules[('merchant_norm', merchantNorm)]) ??
        (catalogMerchantId == null
            ? null
            : rules[('catalog_merchant', '$catalogMerchantId')]);
  }
}

final class FakeCatalog implements CatalogPort {
  FakeCatalog({this.shuffleSeed});

  final int? shuffleSeed;
  final List<CatalogMerchant> merchants = [];
  final List<AliasHit> aliases = [];
  int queries = 0;
  int _nextAlias = 1;

  void merchant(int id, String canonical, String category) => merchants.add(
    CatalogMerchant(id: id, canonical: canonical, categoryCode: category),
  );

  void alias(
    int merchantId,
    String alias, [
    AliasMatch match = AliasMatch.prefix,
  ]) => aliases.add(
    AliasHit(
      id: _nextAlias++,
      aliasNorm: alias,
      merchantId: merchantId,
      match: match,
    ),
  );

  List<T> _order<T>(List<T> l) {
    if (shuffleSeed != null) l.shuffle(Random(shuffleSeed));
    return l;
  }

  @override
  Future<List<AliasHit>> aliasesEqualTo(String key) async {
    queries++;
    return _order([
      for (final a in aliases)
        if (a.aliasNorm == key) a,
    ]);
  }

  @override
  Future<List<AliasHit>> aliasesByKeys(
    Set<String> keys,
    Set<AliasMatch> kinds,
  ) async {
    queries++;
    return _order([
      for (final a in aliases)
        if (keys.contains(a.aliasNorm) && kinds.contains(a.match)) a,
    ]);
  }

  @override
  Future<List<AliasHit>> aliasCandidates(String key, {int limit = 10}) async {
    queries++;
    final grams = {
      for (var i = 0; i + 3 <= key.length; i++) key.substring(i, i + 3),
    };
    final hit = [
      for (final a in aliases)
        if (grams.any(a.aliasNorm.contains)) a,
    ];
    return _order(hit.take(limit).toList());
  }

  @override
  Future<List<CatalogMerchant>> merchantsByIds(Set<int> ids) async {
    queries++;
    return _order([
      for (final m in merchants)
        if (ids.contains(m.id)) m,
    ]);
  }
}

final class FakeKeywords implements KeywordPort {
  FakeKeywords(this.entries, {this.shuffleSeed});
  final List<KeywordEntry> entries;
  final int? shuffleSeed;
  int loads = 0;

  @override
  Future<List<KeywordEntry>> all() async {
    loads++;
    final l = [...entries];
    if (shuffleSeed != null) l.shuffle(Random(shuffleSeed));
    return l;
  }
}

final class FakeCategories implements CategoryPort {
  FakeCategories(Iterable<String> codes, {Set<String> archived = const {}})
    : _live = {
        for (final c in codes)
          if (!archived.contains(c)) 'sys:$c',
      },
      _codes = codes.toSet();

  final Set<String> _live;
  final Set<String> _codes;

  @override
  Future<String?> liveIdBySystemCode(String code) async =>
      _codes.contains(code) && _live.contains('sys:$code') ? 'sys:$code' : null;

  @override
  Future<bool> isLive(String id) async => _live.contains(id);
}

KeywordEntry kw(String k, String cat, int w) =>
    KeywordEntry(keywordNorm: k, categoryCode: cat, weight: w);

/// A small synthetic catalog used by most tests.
({
  FakeRules rules,
  FakeCatalog catalog,
  FakeKeywords keywords,
  FakeCategories cats,
  CategorizerPorts ports,
})
buildWorld({int? shuffleSeed, Set<String> archived = const {}}) {
  final catalog = FakeCatalog(shuffleSeed: shuffleSeed)
    ..merchant(1, 'Carrefour', 'groceries')
    ..alias(1, 'carrefour')
    ..alias(1, 'carrefour market')
    ..merchant(2, 'El Ezaby Pharmacy', 'health')
    ..alias(2, 'ezaby')
    ..alias(2, 'ezaby pharmacy')
    ..alias(2, 'sydlyat alazby')
    ..alias(2, '19011')
    ..merchant(3, 'Talabat', 'dining')
    ..alias(3, 'talabat')
    ..merchant(4, 'Talabat Mart', 'groceries')
    ..alias(4, 'talabat mart')
    ..merchant(5, 'Metro Market', 'groceries')
    ..alias(5, 'metra')
    ..merchant(6, 'Uber', 'transport')
    ..alias(6, 'uber', AliasMatch.token)
    ..merchant(7, 'Netflix', 'subscriptions')
    ..alias(7, 'netflix', AliasMatch.exact);
  final rules = FakeRules();
  final keywords = FakeKeywords([
    kw('pharmacy', 'health', 60),
    kw('supermarket', 'groceries', 60),
    kw('restaurant', 'dining', 60),
    kw('cafe', 'dining', 40),
    kw('coffee', 'dining', 40),
    kw('صيدلية', 'health', 70),
    kw('gym', 'fitness', 60),
    kw('gym', 'health', 30),
  ], shuffleSeed: shuffleSeed);
  final cats = FakeCategories([
    'groceries',
    'health',
    'dining',
    'transport',
    'subscriptions',
    'fitness',
  ], archived: archived);
  return (
    rules: rules,
    catalog: catalog,
    keywords: keywords,
    cats: cats,
    ports: CategorizerPorts(
      rules: rules,
      catalog: catalog,
      keywords: keywords,
      categories: cats,
    ),
  );
}

CategorizeInput inp(String raw, {PartyKind? kind, String? value}) {
  final c = cleanMerchant(raw);
  return CategorizeInput(
    merchantNorm: c.key,
    merchantText: foldKey(c.cleaned),
    counterpartyKind: kind,
    counterpartyValue: value,
  );
}
