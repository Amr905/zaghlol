// T-018 AC2: `catalog_alias_fts` returns trigram candidates (design note §2,
// §5), plus the other CatalogDao primitives, on an encrypted database, in
// both executors. The FTS index follows every alias write (upsert, match
// change, alias_norm change, delete, merchant cascade) and passes FTS5's
// integrity-check. Catalog data synthetic.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/catalog_dao.dart';
import 'package:zaghlol/core/db/db_errors.dart';

import 'financial_fixtures.dart';

const String sentinel = 'T018SENTINEL';

CatalogMerchantsCompanion merchant(int id, String canonical) =>
    CatalogMerchantsCompanion.insert(
      id: Value(id),
      canonical: canonical,
      categoryCode: 'groceries',
      version: 1,
    );

Future<void> expectIndexIntact(AppDatabase db) => db.customStatement(
  // rank 1: also compares the index with the content table.
  'INSERT INTO catalog_alias_fts (catalog_alias_fts, rank) '
  "VALUES ('integrity-check', 1)",
);

void main() {
  for (final background in [true, false]) {
    group(background ? 'background' : 'foreground', () {
      late EncryptedDb edb;
      late CatalogDao dao;

      setUp(() async {
        edb = await EncryptedDb.open(background: background);
        dao = CatalogDao(edb.db);
        for (final (id, name, aliases) in [
          (1, 'Carrefour', ['carrefour', 'carrefour maadi']),
          (2, 'El Ezaby', ['ezaby', 'ezaby pharmacy']),
          (3, 'Koshary El Tahrir', ['koshary el tahrir']),
          (4, 'B.TECH', ['btech']),
          (5, 'Near East Bakery', ['near east bakery']),
        ]) {
          await dao.upsertMerchant(merchant(id, name));
          for (final a in aliases) {
            await dao.upsertAlias(merchantId: id, aliasNorm: a, match: 'exact');
          }
        }
      });

      tearDown(() => edb.close());

      Future<List<String>> candidates(String key, {int limit = 10}) async => [
        for (final a in await dao.aliasCandidates(key, limit: limit))
          a.aliasNorm,
      ];

      test(
        'T-030 bulk upserts update in place and keep the FTS in sync',
        () async {
          await dao.upsertMerchants([
            merchant(1, 'Carrefour Renamed'),
            merchant(9, 'Newcomer'),
          ]);
          await dao.upsertAliases([
            (merchantId: 1, aliasNorm: 'carrefour', match: 'exact'),
            (merchantId: 9, aliasNorm: 'newcomer', match: 'prefix'),
          ]);
          await dao.upsertKeywords([
            CatalogKeywordsCompanion.insert(
              keywordNorm: 'فاكهه',
              lang: 'ar',
              categoryCode: 'groceries',
              weight: 60,
            ),
          ]);
          await dao.upsertKeywords([
            CatalogKeywordsCompanion.insert(
              keywordNorm: 'فاكهه',
              lang: 'ar',
              categoryCode: 'groceries',
              weight: 70,
            ),
          ]);
          expect((await dao.merchantById(1))!.canonical, 'Carrefour Renamed');
          // The original aliases of merchant 1 stayed (update, not replace).
          expect(await dao.aliasesEqualTo('carrefour maadi'), hasLength(1));
          final same = await dao.aliasesEqualTo('carrefour');
          expect(same.single.match, 'exact');
          expect(await candidates('newcomr'), ['newcomer']);
          expect((await dao.keywordsOf('ar')).single.weight, 70);
          await expectIndexIntact(edb.db);
        },
      );

      test('a misspelt key finds its alias (shared trigrams)', () async {
        expect(await candidates('ezabi'), ['ezaby', 'ezaby pharmacy']);
        expect((await candidates('carrefur')).toSet(), {
          'carrefour',
          'carrefour maadi',
        });
        expect(await candidates('btek'), ['btech']);
      });

      test('a substring finds the alias; the best match ranks first', () async {
        expect(await candidates('tahrir'), ['koshary el tahrir']);
        expect((await candidates('carrefour maadi')).first, 'carrefour maadi');
        expect((await candidates('ezaby pharmacy')).first, 'ezaby pharmacy');
      });

      test('no shared trigram: no candidates; keys under three characters '
          'have no trigram', () async {
        expect(await candidates('zzzq'), isEmpty);
        expect(await candidates('ez'), isEmpty);
        expect(await candidates('b'), isEmpty);
      });

      test('FTS5 words in a key are matched literally', () async {
        // "near", "or", "and" are FTS5 operators outside quotes.
        expect(await candidates('near east'), ['near east bakery']);
        expect(await candidates('or and not'), isEmpty);
      });

      test('a non-canonical key is refused before any query, without '
          'echoing it', () async {
        for (final bad in [
          'Carrefour',
          ' carrefour',
          'a  b',
          '"carrefour"',
          'كارفور',
          '$sentinel x',
          'x' * 65,
          '',
        ]) {
          Object? caught;
          try {
            await dao.aliasCandidates(bad);
          } on Object catch (e) {
            caught = e;
          }
          expect(caught, isA<ArgumentError>(), reason: bad);
          expect(caught.toString().contains(sentinel), isFalse);
        }
      });

      test('limit: default 10, capped at 50, ≤ 0 is empty', () async {
        for (var i = 0; i < 60; i++) {
          await dao.upsertMerchant(merchant(100 + i, 'Synthetic $i'));
          await dao.upsertAlias(
            merchantId: 100 + i,
            aliasNorm: 'lotsa shop $i',
            match: 'token',
          );
        }
        expect(await dao.aliasCandidates('lotsa shop'), hasLength(10));
        expect(
          await dao.aliasCandidates('lotsa shop', limit: 500),
          hasLength(maxAliasCandidates),
        );
        expect(await dao.aliasCandidates('lotsa shop', limit: 0), isEmpty);
        await expectIndexIntact(edb.db);
      });

      test('the index follows upsert, match change, alias change, delete and '
          'the merchant cascade', () async {
        // Upsert of an existing alias updates its match: one row, one entry.
        await dao.upsertAlias(
          merchantId: 4,
          aliasNorm: 'btech',
          match: 'prefix',
        );
        final rows = await dao.aliasesEqualTo('btech');
        expect(
          [for (final r in rows) (r.merchantId, r.match)],
          [(4, 'prefix')],
        );
        expect(await candidates('btech'), ['btech']);
        await expectIndexIntact(edb.db);

        // alias_norm change (not a DAO path; the trigger still covers it).
        await edb.db.customStatement(
          "UPDATE catalog_aliases SET alias_norm = 'btech store' "
          "WHERE alias_norm = 'btech'",
        );
        expect(await candidates('btech'), ['btech store']);
        expect(await dao.aliasesEqualTo('btech'), isEmpty);
        await expectIndexIntact(edb.db);

        expect(
          await dao.deleteAlias(merchantId: 4, aliasNorm: 'btech store'),
          1,
        );
        expect(await candidates('btech'), isEmpty);
        await expectIndexIntact(edb.db);

        expect(await dao.deleteMerchant(2), 1);
        expect(await candidates('ezaby'), isEmpty);
        expect(await dao.merchantById(2), isNull);
        await expectIndexIntact(edb.db);

        await dao.rebuildAliasIndex();
        expect(await candidates('carrefour'), hasLength(2));
        await expectIndexIntact(edb.db);
      });

      test(
        'an alias upsert keeps the row id (an UPDATE, not a REPLACE)',
        () async {
          Future<int> idOf() async =>
              (await edb.db
                      .customSelect(
                        "SELECT id FROM catalog_aliases WHERE alias_norm = 'btech'",
                      )
                      .getSingle())
                  .read<int>('id');
          final before = await idOf();
          await dao.upsertAlias(
            merchantId: 4,
            aliasNorm: 'btech',
            match: 'token',
          );
          expect(await idOf(), before);
        },
      );

      test('merchant upsert updates in place and keeps the aliases', () async {
        await dao.upsertMerchant(
          merchant(
            1,
            'Carrefour Renamed',
          ).copyWith(nameAr: const Value('كارفور'), version: const Value(2)),
        );
        final m = await dao.merchantById(1);
        expect(
          (m!.canonical, m.nameAr, m.version),
          ('Carrefour Renamed', 'كارفور', 2),
        );
        expect(await dao.aliasesEqualTo('carrefour'), hasLength(1));
      });

      test('exact lookup: by key, every merchant; non-canonical finds '
          'nothing', () async {
        await dao.upsertAlias(
          merchantId: 3,
          aliasNorm: 'carrefour',
          match: 'exact',
        );
        expect(
          [for (final r in await dao.aliasesEqualTo('carrefour')) r.merchantId],
          [1, 3],
        );
        expect(await dao.aliasesEqualTo('Carrefour'), isEmpty);
      });

      test('keywords: upsert by (keyword, lang), list, delete', () async {
        Future<void> kw(String k, String lang, String cat, int w) =>
            dao.upsertKeyword(
              CatalogKeywordsCompanion.insert(
                keywordNorm: k,
                lang: lang,
                categoryCode: cat,
                weight: w,
              ),
            );
        await kw('صيدليه', 'ar', 'health', 60);
        await kw('pharmacy', 'en', 'health', 60);
        await kw('صيدليه', 'ar', 'health', 70);
        final ar = await dao.keywordsOf('ar');
        expect(
          [for (final k in ar) (k.keywordNorm, k.weight)],
          [('صيدليه', 70)],
        );
        expect(await dao.deleteKeyword(keywordNorm: 'pharmacy', lang: 'en'), 1);
        expect(await dao.keywordsOf('en'), isEmpty);
      });

      test('meta: none, then the applied version', () async {
        expect(await dao.meta(), isNull);
        await dao.setMeta(version: 41, appliedAt: t0, signatureKid: 'sync-1');
        await dao.setMeta(
          version: 42,
          appliedAt: t0 + 1,
          signatureKid: 'sync-2',
        );
        final m = await dao.meta();
        expect((m!.version, m.signatureKid), (42, 'sync-2'));
      });

      test('a refused catalog write carries no catalog text', () async {
        Object? caught;
        try {
          await dao.upsertAlias(
            merchantId: 1,
            aliasNorm: '$sentinel shop',
            match: 'exact',
          );
        } on Object catch (e) {
          caught = e;
        }
        expect(caught, isA<DbWriteException>());
        expect(
          (caught! as DbWriteException).code,
          DbWriteException.constraintCheck,
        );
        expect(caught.toString().contains(sentinel), isFalse);
      });

      test('apply in one transaction: a bad op rolls back the earlier ones '
          '(FR-SYNC-03)', () async {
        Object? caught;
        try {
          await edb.db.transaction(() async {
            await dao.upsertMerchant(merchant(9, 'Synthetic Nine'));
            await dao.upsertAlias(
              merchantId: 9,
              aliasNorm: 'nine',
              match: 'exact',
            );
            await dao.upsertAlias(
              merchantId: 9,
              aliasNorm: 'Nine',
              match: 'exact',
            );
          });
        } on Object catch (e) {
          caught = e;
        }
        expect(caught, isA<DbWriteException>());
        expect(await dao.merchantById(9), isNull);
        expect(await candidates('nine'), isEmpty);
        await expectIndexIntact(edb.db);
      });
    });
  }
}
