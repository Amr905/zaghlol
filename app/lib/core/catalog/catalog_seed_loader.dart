// T-030: loads the bundled, signed catalog seed into the catalog tables on
// first launch, offline (FR-CAT-01/02, NFR-MAINT-01).
//
// Order of work, each step failing closed with a code-only
// [CatalogSeedException] and no database write before the last two:
//   1. if the catalog already has a version, stop (the seed is first-launch
//      only: it never overwrites or downgrades what the sync applied);
//   2. read the .gz and the .sig (size capped), inflate with a hard cap on
//      the output (a gzip bomb stops at 8 MiB);
//   3. verify the ES256 signature over the inflated bytes, against the
//      bundled keys only;
//   4. strict decode (zaghlol_catalog), then
//   5. one transaction: categories, merchants, aliases, keywords, and
//      `catalog_meta` last. Any failure rolls all of it back.
// Nothing here logs, and no error carries seed content.

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart' show rootBundle;
import 'package:zaghlol_catalog/zaghlol_catalog.dart';

import '../db/app_database.dart';
import '../db/daos/catalog_dao.dart';
import '../db/daos/categories_dao.dart';

/// Where the bundled seed comes from. Tests use a fake.
abstract interface class CatalogSeedSource {
  /// The gzip bytes of `catalog_seed.json.gz`.
  Future<Uint8List> readGzip();

  /// The `Zaghlol-Signature` header text of `catalog_seed.json.sig`.
  Future<String> readSignature();
}

/// The seed in the app's asset bundle (`assets/catalog/`).
final class AssetCatalogSeedSource implements CatalogSeedSource {
  const AssetCatalogSeedSource();

  static const String gzipAsset = 'assets/catalog/catalog_seed.json.gz';
  static const String signatureAsset = 'assets/catalog/catalog_seed.json.sig';

  @override
  Future<Uint8List> readGzip() async {
    final data = await rootBundle.load(gzipAsset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  Future<String> readSignature() => rootBundle.loadString(signatureAsset);
}

/// What [CatalogSeedLoader.loadIfNeeded] did.
enum CatalogSeedOutcome {
  /// The seed was verified and applied.
  loaded,

  /// The catalog already had a version; nothing was read or written.
  alreadyPresent,
}

final class CatalogSeedResult {
  const CatalogSeedResult(this.outcome, this.version);

  final CatalogSeedOutcome outcome;

  /// The catalog version now in the database.
  final int version;
}

class CatalogSeedLoader {
  CatalogSeedLoader({
    required this._db,
    required this._source,
    required List<SeedTrustedKey> trustedKeys,
    this._clock = DateTime.now,
  }) : _keys = List.unmodifiable(trustedKeys);

  final AppDatabase _db;
  final CatalogSeedSource _source;
  final List<SeedTrustedKey> _keys;
  final DateTime Function() _clock;

  /// Largest compressed seed accepted.
  static const int maxGzipBytes = maxSeedJsonBytes;

  Future<CatalogSeedResult> loadIfNeeded() async {
    final catalog = CatalogDao(_db);
    final existing = await catalog.meta();
    if (existing != null) {
      return CatalogSeedResult(
        CatalogSeedOutcome.alreadyPresent,
        existing.version,
      );
    }

    final compressed = await _source.readGzip();
    if (compressed.length > maxGzipBytes) {
      throw CatalogSeedException(CatalogSeedException.tooLarge);
    }
    final header = await _source.readSignature();
    final json = _inflate(compressed);
    final kid = verifySeedSignature(json, header, _keys);
    final seed = CatalogSeed.decode(json);

    final categories = CategoriesDao(_db);
    final appliedAt = _clock().toUtc().millisecondsSinceEpoch;
    var applied = false;
    await _db.transaction(() async {
      // Re-check inside the transaction: another loader may have won.
      if (await catalog.meta() != null) return;
      for (final c in seed.categories) {
        await categories.upsertSystem(
          code: c.code,
          nameAr: c.nameAr,
          nameEn: c.nameEn,
          icon: c.icon,
          color: c.color,
          bucket: c.bucket,
          sort: c.sort,
        );
      }
      await catalog.upsertMerchants([
        for (final m in seed.merchants)
          CatalogMerchantsCompanion.insert(
            id: Value(m.id),
            canonical: m.canonical,
            nameAr: Value(m.nameAr),
            categoryCode: m.category,
            version: seed.version,
          ),
      ]);
      await catalog.upsertAliases([
        for (final a in seed.aliases)
          (merchantId: a.merchantId, aliasNorm: a.alias, match: a.match),
      ]);
      await catalog.upsertKeywords([
        for (final k in seed.keywords)
          CatalogKeywordsCompanion.insert(
            keywordNorm: k.keyword,
            lang: k.lang,
            categoryCode: k.category,
            weight: k.weight,
          ),
      ]);
      await catalog.setMeta(
        version: seed.version,
        appliedAt: appliedAt,
        signatureKid: kid,
      );
      applied = true;
    });
    return CatalogSeedResult(
      applied ? CatalogSeedOutcome.loaded : CatalogSeedOutcome.alreadyPresent,
      (await catalog.meta())?.version ?? seed.version,
    );
  }
}

/// Inflates [compressed], stopping at [maxSeedJsonBytes] of output.
Uint8List _inflate(Uint8List compressed) {
  final out = BytesBuilder(copy: false);
  final sink = _CappedSink(out);
  try {
    final input = gzip.decoder.startChunkedConversion(sink);
    input
      ..add(compressed)
      ..close();
  } on CatalogSeedException {
    rethrow;
  } on Object {
    // Truncated or corrupt gzip: say so without the zlib message.
    throw CatalogSeedException(CatalogSeedException.notJson);
  }
  return out.takeBytes();
}

final class _CappedSink extends ByteConversionSinkBase {
  _CappedSink(this._out);

  final BytesBuilder _out;

  @override
  void add(List<int> chunk) {
    if (_out.length + chunk.length > maxSeedJsonBytes) {
      throw CatalogSeedException(CatalogSeedException.tooLarge);
    }
    _out.add(chunk);
  }

  @override
  void close() {}
}
