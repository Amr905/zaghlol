// T-030: the first-launch seed loader on an encrypted database (host
// sqlite3mc). Covers the acceptance criteria: 14 system categories in AR/EN,
// load time, tampered seed rejected (no write), plus idempotence, the
// never-overwrite rule, rollback and the gzip cap. Catalog text is the
// bundled brand list; nothing here is user data.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/catalog/catalog_seed_loader.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/catalog_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/db_errors.dart';
import 'package:zaghlol_catalog/zaghlol_catalog.dart';

import '../db/financial_fixtures.dart';

class _FileSource implements CatalogSeedSource {
  _FileSource({this.gz, this.sig});

  final Uint8List? gz;
  final String? sig;
  int reads = 0;

  @override
  Future<Uint8List> readGzip() async {
    reads++;
    return gz ?? File('assets/catalog/catalog_seed.json.gz').readAsBytesSync();
  }

  @override
  Future<String> readSignature() async =>
      sig ?? File('assets/catalog/catalog_seed.json.sig').readAsStringSync();
}

/// The dev key (tools/catalog_build/dev): lets a test sign its own seeds.
final SeedSigner _devSigner = SeedSigner(
  kid: 's0000a',
  d: Uint8List.fromList(
    base64Url.decode(
      base64Url.normalize('nZbg9AqqNwREn0tWmsTKd5DdIcXTXbXTFlakZwfjIkY'),
    ),
  ),
);

Uint8List _bundledJson() => Uint8List.fromList(
  gzip.decode(File('assets/catalog/catalog_seed.json.gz').readAsBytesSync()),
);

_FileSource _signed(Uint8List json) => _FileSource(
  gz: Uint8List.fromList(gzip.encode(json)),
  sig: _devSigner.sign(json),
);

Future<String?> _codeOf(Future<Object?> Function() f) async {
  try {
    await f();
    return null;
  } on CatalogSeedException catch (e) {
    return e.code;
  }
}

Future<int> _count(AppDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT count(*) AS n FROM $table')
      .getSingle();
  return row.read<int>('n');
}

Future<void> _expectEmptyCatalog(AppDatabase db) async {
  for (final t in [
    'categories',
    'catalog_merchants',
    'catalog_aliases',
    'catalog_keywords',
    'catalog_meta',
  ]) {
    expect(await _count(db, t), 0, reason: t);
  }
}

void main() {
  late EncryptedDb edb;
  late AppDatabase db;

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
  });
  tearDown(() => edb.close());

  CatalogSeedLoader loader(
    CatalogSeedSource source, {
    List<SeedTrustedKey>? keys,
    bool allowDevKeys = true,
  }) => CatalogSeedLoader(
    db: db,
    source: source,
    trustedKeys: keys ?? bundledSeedKeys(),
    allowDevKeys: allowDevKeys,
    clock: () => DateTime.utc(2026, 11, 11, 8),
  );

  group('first launch', () {
    test('loads the bundled seed: 14 system categories in AR and EN', () async {
      final result = await loader(_FileSource()).loadIfNeeded();
      expect(result.outcome, CatalogSeedOutcome.loaded);
      expect(result.version, 1);

      final rows = await CategoriesDao(db).active();
      expect(rows.length, 14);
      expect([for (final r in rows) r.sort], [for (var i = 1; i <= 14; i++) i]);
      expect(
        rows.every((r) => !r.isCustom.isOdd && r.systemCode != null),
        isTrue,
      );
      expect(rows.first.id, 'sys:groceries');
      expect(rows.first.nameAr, 'خزين البيت والسوبرماركت');
      expect(rows.first.nameEn, 'Groceries & Supermarkets');
      expect(rows.last.id, 'sys:income');
      expect(rows.last.nameAr, 'مرتب ودخل وكاش باك');
      expect(rows.last.nameEn, 'Income, Salary & Refunds');
      expect(rows.last.bucket, 'income');
      expect(
        {for (final r in rows) r.bucket},
        {
          'needs', 'wants', 'obligations', 'savings', 'income', 'giving', //
        },
      );
    });

    test('records version, time and signing key', () async {
      await loader(_FileSource()).loadIfNeeded();
      final meta = await CatalogDao(db).meta();
      expect(meta!.version, 1);
      expect(meta.signatureKid, 's0000a');
      expect(
        meta.appliedAt,
        DateTime.utc(2026, 11, 11, 8).millisecondsSinceEpoch,
      );
    });

    test(
      'merchants, aliases and keywords are usable by the categorizer',
      () async {
        await loader(_FileSource()).loadIfNeeded();
        final dao = CatalogDao(db);
        final ezaby = await dao.aliasesEqualTo('ezaby');
        expect(ezaby, hasLength(1));
        final merchant = await dao.merchantById(ezaby.single.merchantId);
        expect(merchant!.canonical, 'El Ezaby Pharmacy');
        expect(merchant.categoryCode, 'health');
        expect(merchant.version, 1);
        // The attached-article spelling is a separate alias (FU-066).
        expect(await dao.aliasesEqualTo('elabd'), hasLength(1));
        // Trigram candidates work on the loaded aliases.
        final near = await dao.aliasCandidates('carefour');
        expect(near, isNotEmpty);
        expect(await dao.keywordsOf('ar'), isNotEmpty);
        expect(await dao.keywordsOf('en'), isNotEmpty);
        await edb.db.customStatement(
          "INSERT INTO catalog_alias_fts (catalog_alias_fts, rank) VALUES ('integrity-check', 1)",
        );
      },
    );

    test('loading takes well under a second', () async {
      final sw = Stopwatch()..start();
      await loader(_FileSource()).loadIfNeeded();
      sw.stop();
      // ignore: avoid_print
      print('seed load (verify + apply, host): ${sw.elapsedMilliseconds} ms');
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('a 600-merchant, 3000-alias seed also loads under a second', () async {
      final ops = <SeedOp>[
        const SeedCategory(
          code: 'groceries',
          nameAr: 'بقالة',
          nameEn: 'Groceries',
          icon: 'cart',
          color: '#174C4F',
          bucket: 'needs',
          sort: 1,
        ),
        for (var i = 1; i <= 600; i++)
          SeedMerchant(
            id: i,
            canonical: 'Merchant $i',
            nameAr: 'تاجر $i',
            category: 'groceries',
          ),
        for (var i = 1; i <= 600; i++)
          for (var j = 0; j < 5; j++)
            SeedAlias(merchantId: i, alias: 'm$i v$j', match: 'prefix'),
      ];
      final json = CatalogSeed.validated(version: 1, ops: ops).encode();
      final sw = Stopwatch()..start();
      await loader(_signed(json)).loadIfNeeded();
      sw.stop();
      // ignore: avoid_print
      print(
        '600 merchants / 3000 aliases (host): ${sw.elapsedMilliseconds} ms',
      );
      expect(await _count(db, 'catalog_aliases'), 3000);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('later launches', () {
    test('a second load reads nothing and changes nothing', () async {
      await loader(_FileSource()).loadIfNeeded();
      final source = _FileSource();
      final again = await loader(source).loadIfNeeded();
      expect(again.outcome, CatalogSeedOutcome.alreadyPresent);
      expect(source.reads, 0);
      expect(await _count(db, 'catalog_merchants'), greaterThan(100));
    });

    test('a catalog the sync already advanced is never overwritten', () async {
      final dao = CatalogDao(db);
      await dao.setMeta(version: 5, appliedAt: t0, signatureKid: 's0001a');
      final result = await loader(_FileSource()).loadIfNeeded();
      expect(result.outcome, CatalogSeedOutcome.alreadyPresent);
      expect(result.version, 5);
      expect(await _count(db, 'catalog_merchants'), 0);
      expect((await dao.meta())!.signatureKid, 's0001a');
    });

    test('two loaders at once leave one consistent catalog', () async {
      final results = await Future.wait([
        loader(_FileSource()).loadIfNeeded(),
        loader(_FileSource()).loadIfNeeded(),
      ]);
      expect(
        results.where((r) => r.outcome == CatalogSeedOutcome.loaded).length,
        greaterThanOrEqualTo(1),
      );
      expect(await _count(db, 'categories'), 14);
      final merchants = await _count(db, 'catalog_merchants');
      expect(merchants, greaterThan(100));
      await db.customStatement(
        "INSERT INTO catalog_alias_fts (catalog_alias_fts, rank) VALUES ('integrity-check', 1)",
      );
    });
  });

  group('tampered or foreign seed is rejected before any write', () {
    test('one flipped byte in the JSON', () async {
      final json = _bundledJson();
      final sig = File('assets/catalog/catalog_seed.json.sig')
          .readAsStringSync();
      json[json.length ~/ 2] ^= 0x01;
      final source = _FileSource(
        gz: Uint8List.fromList(gzip.encode(json)),
        sig: sig,
      );
      expect(
        await _codeOf(() => loader(source).loadIfNeeded()),
        CatalogSeedException.badSignature,
      );
      await _expectEmptyCatalog(db);
    });

    test(
      'a valid-looking edit: a merchant moved to another category',
      () async {
        final text = utf8
            .decode(_bundledJson())
            .replaceFirst('"category":"groceries"', '"category":"income"');
        final source = _FileSource(
          gz: Uint8List.fromList(gzip.encode(utf8.encode(text))),
        );
        expect(
          await _codeOf(() => loader(source).loadIfNeeded()),
          CatalogSeedException.badSignature,
        );
        await _expectEmptyCatalog(db);
      },
    );

    test('a release-mode loader rejects the dev-signed seed', () async {
      expect(
        await _codeOf(
          () => loader(_FileSource(), allowDevKeys: false).loadIfNeeded(),
        ),
        CatalogSeedException.badSignature,
      );
      await _expectEmptyCatalog(db);
    });

    test('a changed, missing or foreign signature', () async {
      for (final sig in [
        '',
        'kid=s0000a; alg=ES256; sig=${'A' * 86}',
        File('assets/catalog/catalog_seed.json.sig')
            .readAsStringSync()
            .replaceFirst('s0000a', 's0002b'),
      ]) {
        expect(
          await _codeOf(() => loader(_FileSource(sig: sig)).loadIfNeeded()),
          CatalogSeedException.badSignature,
        );
      }
      await _expectEmptyCatalog(db);
    });

    test('an empty trusted-key set trusts nothing', () async {
      expect(
        await _codeOf(() => loader(_FileSource(), keys: []).loadIfNeeded()),
        CatalogSeedException.badSignature,
      );
      await _expectEmptyCatalog(db);
    });

    test(
      'correctly signed but not a valid seed (dangling reference)',
      () async {
        final json = Uint8List.fromList(
          utf8.encode(
            '{"version":1,"ops":[{"t":"merchant","op":"upsert","id":1,'
            '"canonical":"X","nameAr":"س","category":"groceries"}]}',
          ),
        );
        expect(
          await _codeOf(() => loader(_signed(json)).loadIfNeeded()),
          CatalogSeedException.danglingRef,
        );
        await _expectEmptyCatalog(db);
      },
    );

    test('corrupt gzip', () async {
      final source = _FileSource(gz: Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(
        await _codeOf(() => loader(source).loadIfNeeded()),
        CatalogSeedException.notJson,
      );
      final truncated = gzip.encode(_bundledJson());
      final cut = _FileSource(
        gz: Uint8List.fromList(truncated.sublist(0, truncated.length ~/ 2)),
      );
      // A cut stream may inflate to a prefix: then the signature fails.
      expect(
        await _codeOf(() => loader(cut).loadIfNeeded()),
        anyOf(CatalogSeedException.notJson, CatalogSeedException.badSignature),
      );
      await _expectEmptyCatalog(db);
    });

    test('a gzip bomb stops at the cap', () async {
      final bomb = Uint8List.fromList(
        gzip.encode(Uint8List(maxSeedJsonBytes + 1024)),
      );
      expect(bomb.length, lessThan(maxSeedJsonBytes));
      expect(
        await _codeOf(() => loader(_FileSource(gz: bomb)).loadIfNeeded()),
        CatalogSeedException.tooLarge,
      );
      await _expectEmptyCatalog(db);
    });
  });

  test('a failure while applying rolls everything back', () async {
    // A custom category already holds system code `income`, so the 14th
    // category upsert hits UNIQUE(system_code) after 13 rows were written:
    // all of them must go, and meta must stay empty.
    await db.customStatement(
      'INSERT INTO categories (id, system_code, name_ar, name_en, icon, '
      'color, bucket, is_custom, is_archived, sort) VALUES '
      "('01HZZZZZZZZZZZZZZZZZZZZZZZ', 'income', 'x', 'x', 'i', '#000000', "
      "'needs', 1, 0, 99)",
    );
    Object? error;
    try {
      await loader(_FileSource()).loadIfNeeded();
    } on Object catch (e) {
      error = e;
    }
    expect(error, isA<DbWriteException>());
    expect(error.toString(), isNot(contains('income')));
    expect(await _count(db, 'catalog_meta'), 0);
    expect(await _count(db, 'catalog_merchants'), 0);
    expect(await _count(db, 'catalog_aliases'), 0);
    expect(await _count(db, 'categories'), 1);
  });
}
