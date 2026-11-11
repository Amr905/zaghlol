// T-046 (CR-1, CR-2, CR-6): T-075's Categorizer over in-memory ports that
// count calls and can throw a defect for one merchant. Synthetic data only.

import 'package:zaghlol/features/ingestion/domain/ingest_ports.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

/// Counts categorizer use and throws a `StateError` (a defect, not a
/// database error) for merchant keys containing [poison].
final class SpyCategorizerPorts {
  SpyCategorizerPorts({this.poison});

  final String? poison;

  /// Rule lookups (the first port the categorizer calls for a message with
  /// a merchant or counterparty).
  int ruleCalls = 0;

  /// Categorizers made (one per batch).
  int made = 0;

  CategorizerFactory get factory => () async {
    made++;
    return Categorizer(
      CategorizerPorts(
        rules: _Rules(this),
        catalog: const _NoCatalog(),
        keywords: const _NoKeywords(),
        categories: const _NoCategories(),
      ),
    );
  };
}

final class _Rules implements RulePort {
  _Rules(this._spy);
  final SpyCategorizerPorts _spy;

  @override
  Future<RuleHit?> match({
    String? counterparty,
    String? merchantNorm,
    int? catalogMerchantId,
  }) async {
    _spy.ruleCalls++;
    final p = _spy.poison;
    if (p != null && (merchantNorm?.contains(p) ?? false)) {
      throw StateError('poison');
    }
    return null;
  }
}

final class _NoCatalog implements CatalogPort {
  const _NoCatalog();
  @override
  Future<List<AliasHit>> aliasesEqualTo(String key) async => const [];
  @override
  Future<List<AliasHit>> aliasesByKeys(
    Set<String> keys,
    Set<AliasMatch> kinds,
  ) async => const [];
  @override
  Future<List<AliasHit>> aliasCandidates(String key, {int limit = 10}) async =>
      const [];
  @override
  Future<List<CatalogMerchant>> merchantsByIds(Set<int> ids) async => const [];
}

final class _NoKeywords implements KeywordPort {
  const _NoKeywords();
  @override
  Future<List<KeywordEntry>> all() async => const [];
}

final class _NoCategories implements CategoryPort {
  const _NoCategories();
  @override
  Future<String?> liveIdBySystemCode(String code) async => null;
  @override
  Future<bool> isLive(String id) async => false;
}
