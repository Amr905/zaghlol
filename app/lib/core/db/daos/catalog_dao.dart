// T-018: the merchant catalog (database-schema §2.4; design note §2, §5).
// Primitives for the catalog apply (backend-api §4.2: ops applied in order
// inside one transaction, which the caller opens) and the lookups of the
// categorizer (parsing-engine §5, steps 2–4). `catalog_alias_fts` is kept in
// sync by triggers (financial_b.drift); this DAO only reads it. Writes go
// through guardWrite, reads that take a key through guardRead. Nothing here
// logs.

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

/// The canonical `merchant_norm` form (parsing-engine §5, T-034): `[a-z0-9]`
/// words separated by single spaces, at most 64 characters. The same rule
/// the `catalog_aliases.alias_norm` CHECK enforces.
final RegExp _merchantKey = RegExp(r'^[a-z0-9]+( [a-z0-9]+)*$');

/// Longest merchant key (parsing-engine §5).
const int merchantKeyMaxLength = 64;

/// Whether [key] is a canonical merchant key.
bool isCanonicalMerchantKey(String key) =>
    key.length <= merchantKeyMaxLength && _merchantKey.hasMatch(key);

/// Default and largest number of fuzzy candidates.
const int defaultAliasCandidates = 10;
const int maxAliasCandidates = 50;

class CatalogDao {
  CatalogDao(this._db);

  final AppDatabase _db;

  /// Inserts or updates merchant `row.id` (an UPDATE on conflict, so its
  /// aliases stay).
  Future<void> upsertMerchant(CatalogMerchantsCompanion row) => guardWrite(
    () => _db.into(_db.catalogMerchants).insertOnConflictUpdate(row),
  );

  /// Deletes merchant [id]; its aliases go with it (FK cascade, which the
  /// FTS triggers follow). Returns the rows deleted (0 or 1).
  Future<int> deleteMerchant(int id) => guardWrite(
    () =>
        (_db.delete(_db.catalogMerchants)..where((m) => m.id.equals(id))).go(),
  );

  Future<CatalogMerchantRow?> merchantById(int id) => (_db.select(
    _db.catalogMerchants,
  )..where((m) => m.id.equals(id))).getSingleOrNull();

  /// Inserts alias ([aliasNorm], [merchantId]) or updates its [match]. An
  /// `ON CONFLICT DO UPDATE`, never `INSERT OR REPLACE`: REPLACE's implicit
  /// delete fires no trigger and would leave the FTS index stale.
  Future<void> upsertAlias({
    required int merchantId,
    required String aliasNorm,
    required String match,
  }) => guardWrite(
    () => _db
        .into(_db.catalogAliases)
        .insert(
          CatalogAliasesCompanion.insert(
            merchantId: merchantId,
            aliasNorm: aliasNorm,
            match: match,
          ),
          onConflict: DoUpdate(
            (_) => CatalogAliasesCompanion(match: Value(match)),
            target: [
              _db.catalogAliases.aliasNorm,
              _db.catalogAliases.merchantId,
            ],
          ),
        ),
  );

  /// Deletes one alias. Returns the rows deleted (0 or 1).
  Future<int> deleteAlias({
    required int merchantId,
    required String aliasNorm,
  }) => guardWrite(
    () =>
        (_db.delete(_db.catalogAliases)..where(
              (a) =>
                  a.merchantId.equals(merchantId) &
                  a.aliasNorm.equals(aliasNorm),
            ))
            .go(),
  );

  /// Inserts or updates keyword (`keyword_norm`, `lang`).
  Future<void> upsertKeyword(CatalogKeywordsCompanion row) => guardWrite(
    () => _db.into(_db.catalogKeywords).insertOnConflictUpdate(row),
  );

  Future<int> deleteKeyword({
    required String keywordNorm,
    required String lang,
  }) => guardWrite(
    () =>
        (_db.delete(_db.catalogKeywords)..where(
              (k) => k.keywordNorm.equals(keywordNorm) & k.lang.equals(lang),
            ))
            .go(),
  );

  /// Every keyword of [lang] (the heuristic step loads them once).
  Future<List<CatalogKeywordRow>> keywordsOf(String lang) =>
      (_db.select(_db.catalogKeywords)
            ..where((k) => k.lang.equals(lang))
            ..orderBy([(k) => OrderingTerm.asc(k.keywordNorm)]))
          .get();

  /// The applied catalog version, or null before the first apply.
  Future<CatalogMetaRow?> meta() => (_db.select(
    _db.catalogMeta,
  )..where((m) => m.id.equals(1))).getSingleOrNull();

  /// Records the applied catalog version (step 3 of the client apply).
  Future<void> setMeta({
    required int version,
    required int appliedAt,
    required String signatureKid,
  }) => guardWrite(
    () => _db
        .into(_db.catalogMeta)
        .insertOnConflictUpdate(
          CatalogMetaCompanion.insert(
            id: const Value(1),
            version: version,
            appliedAt: appliedAt,
            signatureKid: signatureKid,
          ),
        ),
  );

  /// Aliases whose `alias_norm` equals [key] (lookup step 2), by merchant
  /// id. A non-canonical [key] can't be stored, so it finds nothing.
  Future<List<CatalogAliasRow>> aliasesEqualTo(String key) {
    if (!isCanonicalMerchantKey(key)) return Future.value(const []);
    return guardRead(
      () =>
          (_db.select(_db.catalogAliases)
                ..where((a) => a.aliasNorm.equals(key))
                ..orderBy([(a) => OrderingTerm.asc(a.merchantId)]))
              .get(),
    );
  }

  /// Fuzzy candidates for [key] (lookup step 4): aliases sharing trigrams
  /// with it in `catalog_alias_fts`, best `bm25` rank first, at most [limit]
  /// (capped at [maxAliasCandidates]). The caller scores them (Jaro-Winkler).
  ///
  /// [key] must be a canonical merchant key, else [ArgumentError] (whose
  /// message does not hold the key) and nothing is queried. Keys shorter
  /// than three characters have no trigram and return no candidates. The
  /// query is the OR of the key's distinct trigrams, each a quoted FTS5
  /// string (only `[a-z0-9 ]`, so nothing in it is FTS5 syntax), bound as a
  /// parameter. A database failure is a code-only [DbReadException].
  Future<List<CatalogAliasRow>> aliasCandidates(
    String key, {
    int limit = defaultAliasCandidates,
  }) async {
    if (!isCanonicalMerchantKey(key)) {
      throw ArgumentError('not a canonical merchant key', 'key');
    }
    if (limit <= 0 || key.length < 3) return const [];
    final grams = <String>{
      for (var i = 0; i + 3 <= key.length; i++) key.substring(i, i + 3),
    };
    final query = grams.map((g) => '"$g"').join(' OR ');
    final rows = await guardRead(
      () => _db
          .customSelect(
            'SELECT a.* FROM catalog_alias_fts f '
            'JOIN catalog_aliases a ON a.id = f.rowid '
            'WHERE catalog_alias_fts MATCH ?1 '
            'ORDER BY f.rank, a.id '
            'LIMIT ?2',
            variables: [
              Variable.withString(query),
              Variable.withInt(
                limit > maxAliasCandidates ? maxAliasCandidates : limit,
              ),
            ],
            readsFrom: {_db.catalogAliases, _db.catalogAliasFts},
          )
          .get(),
    );
    return [for (final r in rows) _db.catalogAliases.map(r.data)];
  }

  /// Rebuilds `catalog_alias_fts` from `catalog_aliases` (recovery only).
  Future<void> rebuildAliasIndex() => guardWrite(
    () => _db.customStatement(
      "INSERT INTO catalog_alias_fts (catalog_alias_fts) VALUES ('rebuild')",
    ),
  );
}
