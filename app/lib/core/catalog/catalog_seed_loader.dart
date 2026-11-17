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

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart' show rootBundle;
import 'package:zaghlol_catalog/zaghlol_catalog.dart';

import '../../ingestion/ingestion_pause_gate.dart';
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

  /// The catalog already had a version; nothing was written.
  alreadyPresent,

  /// FU-256: the catalog was there, the bundled seed had changed since it was
  /// last applied, and the rows the catalog lacked were added.
  upgraded,
}

/// `db_meta` key holding the sha-256 (hex) of the bundled seed's gzip bytes
/// last applied or found already applied.
const String catalogSeedHashKey = 'catalog_seed_hash_v1';

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
    this._allowDevKeys = false,
    this._clock = DateTime.now,
    this._gate,
  }) : _keys = List.unmodifiable(trustedKeys);

  final AppDatabase _db;
  final CatalogSeedSource _source;
  final List<SeedTrustedKey> _keys;
  final bool _allowDevKeys;
  final DateTime Function() _clock;

  /// The restore pause gate; the upgrade's write runs behind it (refused
  /// while a restore runs: the next start retries).
  final IngestionPauseGate? _gate;

  /// Largest compressed seed accepted.
  static const int maxGzipBytes = maxSeedJsonBytes;

  /// CAT-cash / CAT-INSTAPAY: an install seeded before these two system
  /// categories existed gets them here (the seed itself is first-launch
  /// only). Idempotent; an existing row (even archived) is left alone.
  Future<void> _ensureEventCategories() async {
    final categories = CategoriesDao(_db);
    for (final c in const [
      (
        code: 'cash',
        ar: 'كاش',
        en: 'Cash',
        icon: 'payments',
        color: '#B45309',
        sort: 15,
      ),
      (
        code: 'instapay',
        ar: 'إنستاباي',
        en: 'InstaPay',
        icon: 'bolt',
        color: '#0F7A55',
        sort: 16,
      ),
    ]) {
      if (await categories.bySystemCode(c.code) != null) continue;
      await categories.upsertSystem(
        code: c.code,
        nameAr: c.ar,
        nameEn: c.en,
        icon: c.icon,
        color: c.color,
        bucket: 'wants',
        sort: c.sort,
      );
    }
  }

  Future<String?> _appliedHash() async {
    final row = await (_db.select(
      _db.dbMeta,
    )..where((t) => t.key.equals(catalogSeedHashKey))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _markHash(String hash) => _db
      .into(_db.dbMeta)
      .insert(
        DbMetaCompanion.insert(key: catalogSeedHashKey, value: hash),
        mode: InsertMode.insertOrReplace,
      );

  /// FU-256: an install whose catalog predates the bundled seed's current
  /// content gets the rows it lacks. Insert-only (`INSERT OR IGNORE`): rows
  /// the sync wrote or changed, archived categories and user rules (their own
  /// tables) are never touched, and nothing is deleted. Skipped when the sync
  /// has moved the catalog past the seed's version (the server's catalog is
  /// the truth then, and a seed row the sync deleted must not return). The
  /// hash is recorded last, in the same transaction. Fails closed: any
  /// problem (signature, decode, gate paused) leaves the catalog as it was
  /// and the hash unset, so the next start retries.
  Future<bool> _upgrade(int currentVersion) async {
    try {
      final compressed = await _source.readGzip();
      if (compressed.length > maxGzipBytes) return false;
      final hash = sha256.convert(compressed).toString();
      if (await _appliedHash() == hash) return false;
      final header = await _source.readSignature();
      final json = _inflate(compressed);
      verifySeedSignature(json, header, _keys, allowDevKeys: _allowDevKeys);
      final seed = CatalogSeed.decode(json);
      final catalog = CatalogDao(_db);
      final categories = CategoriesDao(_db);
      Future<void> write() => _db.transaction(() async {
        // Past the seed: the sync owns the catalog now. Record the hash so
        // this is not re-read every start.
        if (currentVersion <= seed.version) {
          for (final c in seed.categories) {
            await categories.insertSystemIfMissing(
              code: c.code,
              nameAr: c.nameAr,
              nameEn: c.nameEn,
              icon: c.icon,
              color: c.color,
              bucket: c.bucket,
              sort: c.sort,
            );
          }
          await catalog.insertMissingCatalog(
            merchants: [
              for (final m in seed.merchants)
                CatalogMerchantsCompanion.insert(
                  id: Value(m.id),
                  canonical: m.canonical,
                  nameAr: Value(m.nameAr),
                  categoryCode: m.category,
                  version: seed.version,
                ),
            ],
            aliases: [
              for (final a in seed.aliases)
                (merchantId: a.merchantId, aliasNorm: a.alias, match: a.match),
            ],
            keywords: [
              for (final k in seed.keywords)
                CatalogKeywordsCompanion.insert(
                  keywordNorm: k.keyword,
                  lang: k.lang,
                  categoryCode: k.category,
                  weight: k.weight,
                ),
            ],
          );
        }
        await _markHash(hash);
      });
      await (_gate == null ? write() : _gate.guard(write));
      return currentVersion <= seed.version;
    } on Object {
      return false;
    }
  }

  Future<CatalogSeedResult> loadIfNeeded() async {
    final catalog = CatalogDao(_db);
    final existing = await catalog.meta();
    if (existing != null) {
      await _ensureEventCategories();
      final upgraded = await _upgrade(existing.version);
      return CatalogSeedResult(
        upgraded
            ? CatalogSeedOutcome.upgraded
            : CatalogSeedOutcome.alreadyPresent,
        existing.version,
      );
    }

    final compressed = await _source.readGzip();
    if (compressed.length > maxGzipBytes) {
      throw CatalogSeedException(CatalogSeedException.tooLarge);
    }
    final header = await _source.readSignature();
    final json = _inflate(compressed);
    final kid = verifySeedSignature(
      json,
      header,
      _keys,
      allowDevKeys: _allowDevKeys,
    );
    final seed = CatalogSeed.decode(json);
    final hash = sha256.convert(compressed).toString();

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
      await _markHash(hash);
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
