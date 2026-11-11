// T-075: re-categorizing existing rows never overwrites a user's work
// ("Never overwrite" in the design note), including under a real
// interleaving of two connections (FU-095). Synthetic data only.

import 'dart:math';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/catalog_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/merchant_rules_dao.dart'
    show MerchantRulesDao;
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/features/categorization/data/categorizer_ports.dart';
import 'package:zaghlol/features/categorization/data/recategorizer.dart';
import 'package:zaghlol/features/categorization/data/rules_repository.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/db_open_harness.dart' show keyOf;
import '../../../core/db/financial_fixtures.dart';
import '../../../support/db_interleave.dart';

const String sentinel = 'T075SENTINEL';

const CategoryDecision catalogFood = CategoryDecision(
  categoryId: 'sys:food',
  catalogMerchantId: 7,
  source: CategorySource.catalog,
  tier: CategorizeTier.exact,
);

void main() {
  late EncryptedDb edb;
  late AppDatabase other;
  late Recategorizer re;
  late Recategorizer reB;
  late TransactionsDao txns;

  Future<void> put(
    String id, {
    String? norm,
    String? raw,
    String source = 'none',
    String? category,
    int? catalogId,
    bool verified = false,
    bool internal = false,
    bool deleted = false,
  }) => txns.insert(
    txn(id, merchantNorm: norm).copyWith(
      merchantRaw: Value(raw ?? norm),
      catalogMerchantId: Value(catalogId),
      categorySource: Value(source),
      categoryId: Value(category),
      isUserVerified: Value(verified ? 1 : 0),
      isInternal: Value(internal ? 1 : 0),
      deletedAt: Value(deleted ? t0 : null),
    ),
  );

  Future<(String?, String, int?)> state(String id) async {
    final r = await txns.byId(id);
    return (r!.categoryId, r.categorySource, r.catalogMerchantId);
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    edb = await EncryptedDb.open();
    other = AppDatabase(
      openEncryptedExecutor(edb.world.mainFile, keyOf(61), inBackground: true),
      validateSchema: false,
    );
    re = Recategorizer(edb.db);
    reB = Recategorizer(other);
    txns = TransactionsDao(edb.db);
    await AccountsDao(edb.db).insert(account('acc1'));
    final cats = CategoriesDao(edb.db);
    for (final (code, sort) in [('food', 1), ('bills', 2)]) {
      await cats.upsertSystem(
        code: code,
        nameAr: 'ا',
        nameEn: code,
        icon: 'i',
        color: '#0F7A55',
        bucket: 'needs',
        sort: sort,
      );
    }
  });
  tearDown(() async {
    await other.close();
    await edb.close();
  });

  Future<int> apply(
    String id,
    CategoryDecision d, {
    String? oldCat,
    int? oldMerchant,
    Recategorizer? r,
  }) => (r ?? re).apply(
    id: id,
    oldCategoryId: oldCat,
    oldCatalogMerchantId: oldMerchant,
    decision: d,
    at: t0 + 1,
  );

  group('apply: never overwrite', () {
    test('writes a none row; user, user_rule, verified, internal, deleted '
        'rows survive', () async {
      await put('n', norm: 'a');
      await put('u', norm: 'a', source: 'user', category: 'sys:bills');
      await put('ur', norm: 'a', source: 'user_rule', category: 'sys:bills');
      await put('v', norm: 'a', verified: true);
      await put('i', norm: 'a', internal: true);
      await put('d', norm: 'a', deleted: true);
      for (final id in ['n', 'u', 'ur', 'v', 'i', 'd']) {
        await apply(
          id,
          catalogFood,
          oldCat: id == 'n' || id == 'v' || id == 'i' || id == 'd'
              ? null
              : 'sys:bills',
        );
      }
      expect(await state('n'), ('sys:food', 'catalog', 7));
      expect(await state('u'), ('sys:bills', 'user', null));
      expect(await state('ur'), ('sys:bills', 'user_rule', null));
      expect((await state('v')).$2, 'none');
      expect((await state('i')).$2, 'none');
      expect((await state('d')).$2, 'none');
    });

    test('a none decision changes nothing (no downgrade)', () async {
      await put(
        'c',
        norm: 'a',
        source: 'catalog',
        category: 'sys:food',
        catalogId: 7,
      );
      const none = CategoryDecision(
        source: CategorySource.none,
        tier: CategorizeTier.none,
      );
      expect(await apply('c', none, oldCat: 'sys:food', oldMerchant: 7), 0);
      expect(await state('c'), ('sys:food', 'catalog', 7));
    });

    test('a heuristic never replaces a catalog category', () async {
      await put(
        'c',
        norm: 'a',
        source: 'catalog',
        category: 'sys:food',
        catalogId: 7,
      );
      const h = CategoryDecision(
        categoryId: 'sys:bills',
        source: CategorySource.heuristic,
        tier: CategorizeTier.keyword,
      );
      expect(await apply('c', h, oldCat: 'sys:food', oldMerchant: 7), 0);
      expect((await state('c')).$1, 'sys:food');
    });

    test('an unchanged result writes nothing; updated_at stays', () async {
      await put(
        'c',
        norm: 'a',
        source: 'catalog',
        category: 'sys:food',
        catalogId: 7,
      );
      final before = (await txns.byId('c'))!.updatedAt;
      expect(
        await apply('c', catalogFood, oldCat: 'sys:food', oldMerchant: 7),
        0,
      );
      expect((await txns.byId('c'))!.updatedAt, before);
    });

    test(
      'a decision without a merchant keeps the row\'s catalog merchant',
      () async {
        await put(
          'c',
          norm: 'a',
          source: 'catalog',
          category: 'sys:food',
          catalogId: 7,
        );
        const rule = CategoryDecision(
          categoryId: 'sys:bills',
          source: CategorySource.userRule,
          ruleId: 'r',
          tier: CategorizeTier.rule,
        );
        expect(await apply('c', rule, oldCat: 'sys:food', oldMerchant: 7), 1);
        expect(await state('c'), ('sys:bills', 'user_rule', 7));
      },
    );

    test('an archived target category is skipped; a missing one too', () async {
      await put('n', norm: 'a');
      await edb.db.customStatement(
        "UPDATE categories SET is_archived = 1 WHERE id = 'sys:food'",
      );
      expect(await apply('n', catalogFood), 0);
      const ghost = CategoryDecision(
        categoryId: 'sys:ghost',
        source: CategorySource.catalog,
        tier: CategorizeTier.exact,
      );
      expect(await apply('n', ghost), 0);
      expect((await state('n')).$2, 'none');
    });

    test(
      'stale old values: the row changed since the read, nothing written',
      () async {
        await put('n', norm: 'a', category: 'sys:bills');
        expect(await apply('n', catalogFood, oldCat: null), 0);
      },
    );

    test('every guard is in the ONE statement', () {
      final sql = Recategorizer.sqlFor(3);
      for (final g in [
        'deleted_at IS NULL',
        'is_internal = 0',
        'is_user_verified = 0',
        'category_source IN',
        'category_id IS ?6',
        'catalog_merchant_id IS ?7',
        'is_archived = 0',
      ]) {
        expect(sql, contains(g));
      }
      expect(RegExp(r'\bUPDATE\b').allMatches(sql).length, 1);
      expect(sql, isNot(contains('INSERT')));
      expect(
        Recategorizer.replaceable(CategorySource.catalog),
        isNot(contains('user')),
      );
      expect(
        Recategorizer.replaceable(CategorySource.catalog),
        isNot(contains('user_rule')),
      );
    });
  });

  group('interleaving (FU-095)', () {
    test('user edit committed between the read and the write wins', () async {
      await put('t1', norm: 'a');
      // This run read t1 as (null, none); then the user edits it on B.
      final changed = await interleaved<int>(
        blocker: other,
        blockerWrites: () async {
          await TransactionsDao(other).updateById(
            't1',
            const TransactionsCompanion(
              categoryId: Value('sys:bills'),
              categorySource: Value('user'),
              isUserVerified: Value(1),
            ),
          );
        },
        action: () => apply('t1', catalogFood),
      );
      expect(changed, 0);
      expect(await state('t1'), ('sys:bills', 'user', null));
    });

    test('user edit that leaves category_source alone but changes the '
        'category is caught by the old-value check', () async {
      await put('t1', norm: 'a');
      final changed = await interleaved<int>(
        blocker: other,
        blockerWrites: () async {
          await TransactionsDao(other).updateById(
            't1',
            const TransactionsCompanion(categoryId: Value('sys:bills')),
          );
        },
        action: () => apply('t1', catalogFood),
      );
      expect(changed, 0);
      expect((await state('t1')).$1, 'sys:bills');
    });

    test('a row soft-deleted in between is not touched', () async {
      await put('t1', norm: 'a');
      final changed = await interleaved<int>(
        blocker: other,
        blockerWrites: () async {
          await TransactionsDao(
            other,
          ).updateById('t1', const TransactionsCompanion(deletedAt: Value(t0)));
        },
        action: () => apply('t1', catalogFood),
      );
      expect(changed, 0);
      expect((await state('t1')).$2, 'none');
    });

    test('an unrelated concurrent write does not block the update', () async {
      await put('t1', norm: 'a');
      await put('t2', norm: 'b');
      final changed = await interleaved<int>(
        blocker: other,
        blockerWrites: () async {
          await TransactionsDao(other)
              .updateById('t2', const TransactionsCompanion(note: Value('x')));
        },
        action: () => apply('t1', catalogFood),
      );
      expect(changed, 1);
      expect((await state('t1')).$2, 'catalog');
    });

    test('stress: two connections, 40 rows, user edits vs recategorize, '
        'no user edit is lost', () async {
      const n = 40;
      for (var i = 0; i < n; i++) {
        await put('t$i', norm: 'a');
      }
      final rnd = Random(75);
      final edited = <String>{
        for (var i = 0; i < n; i++)
          if (rnd.nextBool()) 't$i',
      };
      await Future.wait([
        for (var i = 0; i < n; i++)
          (i.isEven ? re : reB).apply(
            id: 't$i',
            oldCategoryId: null,
            oldCatalogMerchantId: null,
            decision: catalogFood,
            at: t0 + 1,
          ),
        for (final id in edited)
          TransactionsDao(other).updateById(
            id,
            const TransactionsCompanion(
              categoryId: Value('sys:bills'),
              categorySource: Value('user'),
              isUserVerified: Value(1),
            ),
          ),
      ]);
      for (var i = 0; i < n; i++) {
        final s = await state('t$i');
        if (edited.contains('t$i')) {
          // Either order is legal for the pipeline write, but a user edit
          // that came second overwrites it, and one that came first wins:
          // the user's value is final in both.
          expect(s.$1, 'sys:bills', reason: 't$i');
          expect(s.$2, 'user', reason: 't$i');
        } else {
          expect(s, ('sys:food', 'catalog', 7), reason: 't$i');
        }
      }
    });
  });

  group('run (backfill over real ports)', () {
    test('chunks, memoizes and leaves user rows alone', () async {
      final catalog = CatalogDao(edb.db);
      await catalog.upsertMerchant(
        CatalogMerchantsCompanion.insert(
          id: const Value(7),
          canonical: 'Carrefour',
          categoryCode: 'food',
          version: 1,
        ),
      );
      await catalog.upsertAlias(
        merchantId: 7,
        aliasNorm: 'carrefour',
        match: 'prefix',
      );
      for (var i = 0; i < 450; i++) {
        await put(
          't${i.toString().padLeft(4, '0')}',
          norm: 'carrefour',
          raw: 'CARREFOUR MAADI EG 04$i',
        );
      }
      await put(
        'user',
        norm: 'carrefour',
        source: 'user',
        category: 'sys:bills',
      );
      await put('zzz', norm: 'unknownshop', raw: 'UNKNOWN SHOP');
      final ports = driftCategorizerPorts(
        edb.db,
        DriftRulesRepository(MerchantRulesDao(edb.db), CategoriesDao(edb.db)),
      );
      final report = await re.run(
        Categorizer(ports, memoize: true),
        at: t0 + 9,
      );
      expect(report.scanned, 451); // 450 + zzz; the user row is not scanned
      expect(report.changed, 450);
      expect(await state('t0449'), ('sys:food', 'catalog', 7));
      expect(await state('user'), ('sys:bills', 'user', null));
      expect((await state('zzz')).$2, 'none');
      // Idempotent.
      final again = await re.run(
        Categorizer(ports, memoize: true),
        at: t0 + 10,
      );
      expect(again.changed, 0);
    });

    test('a failing port propagates a code-only error, not text', () async {
      await put('t1', norm: 'carrefour', raw: sentinel);
      final ports = driftCategorizerPorts(
        edb.db,
        DriftRulesRepository(MerchantRulesDao(edb.db), CategoriesDao(edb.db)),
      );
      await edb.db.customStatement('DROP TABLE catalog_aliases');
      try {
        await re.run(Categorizer(ports), at: t0);
        fail('expected a failure');
      } on DbReadException catch (e) {
        expect(e.toString(), isNot(contains(sentinel)));
      }
    });
  });
}
