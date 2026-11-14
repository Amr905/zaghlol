// T-143: applies catalog ops (backend-api §4.2 "Client apply" steps 2-3).
//
// The caller opens the transaction; this class only writes inside it, so a
// failure anywhere rolls the whole sync back (FR-SYNC-03). Ops are validated
// here because the generated DTOs do not enforce the per-op required members
// (FU-115): an upsert without them is a contract violation, so the whole
// apply fails. Unknown op types or kinds are skipped (additive changes within
// v1). System categories are never deleted: transactions point at them.
// A full snapshot first clears aliases and keywords and prunes merchants the
// snapshot no longer lists. Nothing here logs or echoes catalog text.

import 'package:drift/drift.dart' show Value;
import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

import '../../../core/backend/generated/api_models.g.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/daos/catalog_dao.dart';
import '../../../core/db/daos/categories_dao.dart';

/// The key id recorded in `catalog_meta` for catalog data that arrived in a
/// signature-verified sync answer or snapshot.
const String syncCatalogKid = 'sync';

/// Most ops one apply takes (a full snapshot is the largest).
const int maxCatalogOps = 200000;

final class CatalogApplyException extends SafeException {
  CatalogApplyException(super.code);

  static const String invalidOp = 'CATALOG_OP_INVALID';
  static const String tooMany = 'CATALOG_OPS_TOO_MANY';
}

const Set<String> _matchKinds = {'exact', 'prefix', 'token'};

class CatalogApplier {
  CatalogApplier(this._db);

  final AppDatabase _db;

  /// Applies [ops] and records [toVersion]. Must run inside the caller's
  /// transaction. [full] replaces the catalog content.
  Future<void> apply({
    required List<CatalogOp> ops,
    required int toVersion,
    required bool full,
    required int appliedAtMs,
  }) async {
    if (ops.length > maxCatalogOps) {
      throw CatalogApplyException(CatalogApplyException.tooMany);
    }
    final dao = CatalogDao(_db);
    final cats = CategoriesDao(_db);
    if (full) {
      await _db.customStatement('DELETE FROM catalog_aliases');
      await _db.customStatement('DELETE FROM catalog_keywords');
      final keep = <int>{
        for (final o in ops)
          if (o is MerchantOp && o.op == OpKind.upsert) o.id,
      };
      final rows = await _db.select(_db.catalogMerchants).get();
      for (final r in rows) {
        if (!keep.contains(r.id)) await dao.deleteMerchant(r.id);
      }
    }
    for (final o in ops) {
      switch (o) {
        case CategoryOp():
          if (o.op != OpKind.upsert) continue;
          await cats.upsertSystem(
            code: o.code,
            nameAr: _need(o.nameAr),
            nameEn: _need(o.nameEn),
            icon: _need(o.icon),
            color: _need(o.color),
            bucket: _need(o.bucket),
            sort: _need(o.sort),
          );
        case MerchantOp():
          if (o.op == OpKind.upsert) {
            await dao.upsertMerchant(
              CatalogMerchantsCompanion.insert(
                id: Value(o.id),
                canonical: _need(o.canonical),
                nameAr: Value(o.nameAr),
                categoryCode: _need(o.category),
                version: toVersion,
              ),
            );
          } else if (o.op == OpKind.delete) {
            await dao.deleteMerchant(o.id);
          }
        case AliasOp():
          if (o.op == OpKind.upsert) {
            final m = _need(o.match);
            if (!_matchKinds.contains(m)) {
              throw CatalogApplyException(CatalogApplyException.invalidOp);
            }
            await dao.upsertAlias(
              merchantId: o.merchantId,
              aliasNorm: o.alias,
              match: m,
            );
          } else if (o.op == OpKind.delete) {
            await dao.deleteAlias(merchantId: o.merchantId, aliasNorm: o.alias);
          }
        case KeywordOp():
          if (o.op == OpKind.upsert) {
            await dao.upsertKeyword(
              CatalogKeywordsCompanion.insert(
                keywordNorm: o.keyword,
                lang: o.lang,
                categoryCode: _need(o.category),
                weight: _need(o.weight),
              ),
            );
          } else if (o.op == OpKind.delete) {
            await dao.deleteKeyword(keywordNorm: o.keyword, lang: o.lang);
          }
        case CatalogOpUnknown():
          continue;
      }
    }
    await dao.setMeta(
      version: toVersion,
      appliedAt: appliedAtMs,
      signatureKid: syncCatalogKid,
    );
  }

  static T _need<T>(T? v) =>
      v ?? (throw CatalogApplyException(CatalogApplyException.invalidOp));
}
