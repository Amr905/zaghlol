// T-077: bulk edit and Undo on an encrypted database. Acceptance criteria
// are named in the test titles. All data synthetic.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/merchant_rules_dao.dart';
import 'package:zaghlol/core/db/daos/misc_daos.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/transactions/application/bulk_edit.dart';

import '../../../core/db/financial_fixtures.dart';

const String foodId = 'sys:food';
const String billsId = 'sys:bills';

Future<String?> codeOf(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on BulkEditException catch (e) {
    return e.code;
  }
}

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late BulkEditUseCase uc;
  var clockMs = t0 + 1000;
  var nextId = 0;

  Future<Map<String, Map<String, Object?>>> snapshot() async => {
    for (final r in await db.select(db.transactions).get()) r.id: r.toJson(),
  };

  Future<Map<String, int>> totals() async {
    final rows = await db
        .customSelect(
          "SELECT coalesce(category_id, 'none') AS c, sum(amount_minor) AS s "
          'FROM transactions WHERE deleted_at IS NULL '
          'AND is_internal = 0 GROUP BY 1',
        )
        .get();
    return {for (final r in rows) r.read<String>('c'): r.read<int>('s')};
  }

  Future<void> seed(
    int n, {
    String? merchantNorm,
    int? catalogId,
    String currency = 'KWD',
  }) async {
    final dao = TransactionsDao(db);
    for (var i = 0; i < n; i++) {
      await dao.insert(
        txn(
          't$i',
          amountMinor: 1250 + i,
          currency: currency,
          merchantNorm: merchantNorm,
        ).copyWith(catalogMerchantId: Value(catalogId)),
      );
    }
  }

  setUp(() async {
    clockMs = t0 + 1000;
    nextId = 0;
    edb = await EncryptedDb.open();
    db = edb.db;
    uc = BulkEditUseCase(
      db,
      clock: () => DateTime.fromMillisecondsSinceEpoch(clockMs, isUtc: true),
      newId: () => 'id${nextId++}',
    );
    final accounts = AccountsDao(db);
    await accounts.insert(account('acc1'));
    await accounts.insert(account('acc2', institution: 'WAL', last4: '5678'));
    final cats = CategoriesDao(db);
    await cats.upsertSystem(
      code: 'food',
      nameAr: 'أكل',
      nameEn: 'Food',
      icon: 'i',
      color: '#0F7A55',
      bucket: 'needs',
      sort: 1,
    );
    await cats.upsertSystem(
      code: 'bills',
      nameAr: 'فواتير',
      nameEn: 'Bills',
      icon: 'i',
      color: '#4D695C',
      bucket: 'obligations',
      sort: 2,
    );
  });

  tearDown(() => edb.close());

  group('AC1 10 selected: all updated, every total changes', () {
    test('AC1 category change updates 10 rows and moves every total, '
        'amounts untouched', () async {
      await seed(10);
      final before = await snapshot();
      expect(await totals(), {'none': 12545});
      final res = await uc.apply({
        for (var i = 0; i < 10; i++) 't$i',
      }, const SetCategory(foodId));
      expect(res.changed, 10);
      expect(await totals(), {foodId: 12545});
      final after = await snapshot();
      for (final id in before.keys) {
        expect(after[id]!['category_id'], foodId);
        expect(after[id]!['category_source'], 'user');
        expect(after[id]!['is_user_verified'], 1);
        expect(after[id]!['amount_minor'], before[id]!['amount_minor']);
        expect(after[id]!['currency'], 'KWD');
      }
    });

    test('AC1 account change updates 10 rows', () async {
      await seed(10);
      await uc.apply({
        for (var i = 0; i < 10; i++) 't$i',
      }, const SetAccount('acc2'));
      final rows = await db.select(db.transactions).get();
      expect(rows.every((r) => r.accountId == 'acc2'), isTrue);
    });

    test('AC1 delete removes 10 rows from every total', () async {
      await seed(10);
      await uc.apply({
        for (var i = 0; i < 10; i++) 't$i',
      }, const DeleteTransactions());
      expect(await totals(), isEmpty);
      expect((await snapshot()).length, 10); // soft: rows remain
    });
  });

  group('AC2 one Undo restores all 10', () {
    test(
      'AC2 category undo restores every row exactly (all columns)',
      () async {
        await seed(10);
        final before = await snapshot();
        final res = await uc.apply({
          for (var i = 0; i < 10; i++) 't$i',
        }, const SetCategory(foodId));
        clockMs += 5000;
        final u = await uc.undo(res.batchId);
        expect(u.restored, 10);
        expect(u.skipped, 0);
        expect(await snapshot(), before);
        expect(await UndoBatchesDao(db).byId(res.batchId), isNull);
      },
    );

    test('AC2 account undo restores exactly', () async {
      await seed(10);
      final before = await snapshot();
      final res = await uc.apply({
        for (var i = 0; i < 10; i++) 't$i',
      }, const SetAccount('acc2'));
      await uc.undo(res.batchId);
      expect(await snapshot(), before);
    });

    test('AC2 delete undo restores exactly', () async {
      await seed(10);
      final before = await snapshot();
      final res = await uc.apply({
        for (var i = 0; i < 10; i++) 't$i',
      }, const DeleteTransactions());
      await uc.undo(res.batchId);
      expect(await snapshot(), before);
    });

    test(
      'AC2 undo keeps previously user-set categories, not a blanket reset',
      () async {
        await seed(3);
        final dao = TransactionsDao(db);
        await dao.updateById(
          't0',
          const TransactionsCompanion(
            categoryId: Value(billsId),
            categorySource: Value('user'),
            isUserVerified: Value(1),
          ),
        );
        final before = await snapshot();
        final res = await uc.apply({
          't0',
          't1',
          't2',
        }, const SetCategory(foodId));
        await uc.undo(res.batchId);
        expect(await snapshot(), before);
      },
    );
  });

  group('all or none', () {
    test(
      'a missing id fails the whole call: nothing changes, no batch',
      () async {
        await seed(3);
        final before = await snapshot();
        expect(
          await codeOf(
            uc.apply({'t0', 'nope', 't2'}, const SetCategory(foodId)),
          ),
          BulkEditException.notFound,
        );
        expect(await snapshot(), before);
        expect(await db.select(db.undoBatches).get(), isEmpty);
      },
    );

    test('a soft-deleted id fails the whole call', () async {
      await seed(3);
      await TransactionsDao(db).softDelete('t1', at: clockMs);
      final before = await snapshot();
      expect(
        await codeOf(uc.apply({'t0', 't1'}, const DeleteTransactions())),
        BulkEditException.notFound,
      );
      expect(await snapshot(), before);
    });

    test(
      'a failure after the rows are written rolls everything back',
      () async {
        await seed(5);
        final before = await snapshot();
        await db.customStatement(
          'CREATE TRIGGER fail_undo BEFORE INSERT ON undo_batches '
          "BEGIN SELECT RAISE(ABORT, 'x'); END",
        );
        await expectLater(
          uc.apply({
            for (var i = 0; i < 5; i++) 't$i',
          }, const SetCategory(foodId)),
          throwsA(anything),
        );
        expect(await snapshot(), before);
        expect(await db.select(db.merchantRules).get(), isEmpty);
      },
    );

    test('empty, oversized, archived category, unknown account', () async {
      await seed(1);
      expect(
        await codeOf(uc.apply(<String>{}, const SetCategory(foodId))),
        BulkEditException.invalid,
      );
      expect(
        await codeOf(
          uc.apply({
            for (var i = 0; i < 1001; i++) 'x$i',
          }, const SetCategory(foodId)),
        ),
        BulkEditException.invalid,
      );
      await CategoriesDao(db).setArchived(foodId, archived: true);
      expect(
        await codeOf(uc.apply({'t0'}, const SetCategory(foodId))),
        BulkEditException.categoryUnavailable,
      );
      expect(
        await codeOf(uc.apply({'t0'}, const SetCategory('ghost'))),
        BulkEditException.categoryUnavailable,
      );
      expect(
        await codeOf(uc.apply({'t0'}, const SetAccount('ghost'))),
        BulkEditException.accountNotFound,
      );
    });

    test('duplicate ids in the selection count once', () async {
      await seed(2);
      final res = await uc.apply(['t0', 't0', 't1'], const SetCategory(foodId));
      expect(res.changed, 2);
    });
  });

  group('merchant rules ("always use for these merchants")', () {
    test('creates one rule per merchant; undo removes them', () async {
      await seed(4, merchantNorm: 'carrefour');
      await TransactionsDao(db).insert(
        txn(
          'c1',
          merchantNorm: null,
        ).copyWith(catalogMerchantId: const Value(7)),
      );
      await TransactionsDao(db).insert(txn('anon')); // no key: no rule
      final res = await uc.apply({
        't0',
        't1',
        't2',
        't3',
        'c1',
        'anon',
      }, const SetCategory(foodId, alwaysUseForMerchants: true));
      expect(res.rulesCreated, 2);
      final rules = await MerchantRulesDao(db).all();
      expect(
        {for (final r in rules) (r.matchKind, r.matchValue, r.categoryId)},
        {
          (RuleMatchKind.merchantNorm, 'carrefour', foodId),
          (RuleMatchKind.catalogMerchant, '7', foodId),
        },
      );
      final u = await uc.undo(res.batchId);
      expect(u.skipped, 0);
      expect(await MerchantRulesDao(db).all(), isEmpty);
    });

    test(
      'an existing rule is re-pointed and undo restores its category',
      () async {
        await seed(2, merchantNorm: 'carrefour');
        final rules = MerchantRulesDao(db);
        await rules.upsert(
          MerchantRulesCompanion.insert(
            id: 'old',
            matchKind: RuleMatchKind.merchantNorm,
            matchValue: 'carrefour',
            categoryId: billsId,
            createdAt: t0,
          ),
        );
        final res = await uc.apply({
          't0',
          't1',
        }, const SetCategory(foodId, alwaysUseForMerchants: true));
        expect((await rules.byId('old'))!.categoryId, foodId);
        await uc.undo(res.batchId);
        final r = (await rules.byId('old'))!;
        expect(r.categoryId, billsId);
        expect(r.createdAt, t0);
      },
    );

    test('a rule the user changed after the batch is not deleted', () async {
      await seed(2, merchantNorm: 'carrefour');
      final res = await uc.apply({
        't0',
        't1',
      }, const SetCategory(foodId, alwaysUseForMerchants: true));
      final rules = MerchantRulesDao(db);
      await rules.setCategory('id1', billsId);
      final u = await uc.undo(res.batchId);
      expect(u.skipped, 1);
      expect((await rules.byId('id1'))!.categoryId, billsId);
    });

    test('without the option no rule is created', () async {
      await seed(2, merchantNorm: 'carrefour');
      final res = await uc.apply({'t0', 't1'}, const SetCategory(foodId));
      expect(res.rulesCreated, 0);
      expect(await MerchantRulesDao(db).all(), isEmpty);
    });
  });

  group('undo safety', () {
    test(
      'a row edited after the bulk edit is left alone, others restored',
      () async {
        await seed(3);
        final before = await snapshot();
        final res = await uc.apply({
          't0',
          't1',
          't2',
        }, const SetCategory(foodId));
        clockMs += 1000;
        await TransactionsDao(db).updateById(
          't1',
          TransactionsCompanion(
            categoryId: const Value(billsId),
            updatedAt: Value(clockMs),
          ),
        );
        final u = await uc.undo(res.batchId);
        expect(u.restored, 2);
        expect(u.skipped, 1);
        final after = await snapshot();
        expect(after['t1']!['category_id'], billsId);
        expect(after['t0'], before['t0']);
        expect(after['t2'], before['t2']);
      },
    );

    test('a purged row is skipped, not an error', () async {
      await seed(2);
      final res = await uc.apply({'t0', 't1'}, const DeleteTransactions());
      await db.customStatement("DELETE FROM transactions WHERE id = 't1'");
      final u = await uc.undo(res.batchId);
      expect(u.restored, 1);
      expect(u.skipped, 1);
    });

    test(
      'two actors undoing at once: exactly one wins, state restored once',
      () async {
        await seed(10);
        final before = await snapshot();
        final res = await uc.apply({
          for (var i = 0; i < 10; i++) 't$i',
        }, const SetCategory(foodId));
        final other = BulkEditUseCase(
          db,
          clock: () =>
              DateTime.fromMillisecondsSinceEpoch(clockMs, isUtc: true),
        );
        final results = await Future.wait([
          codeOf(uc.undo(res.batchId)),
          codeOf(other.undo(res.batchId)),
        ]);
        expect(results.where((c) => c == null).length, 1);
        expect(
          results.whereType<String>().single,
          BulkEditException.undoNotFound,
        );
        expect(await snapshot(), before);
      },
    );

    test('a second undo finds nothing and changes nothing', () async {
      await seed(2);
      final res = await uc.apply({'t0', 't1'}, const SetCategory(foodId));
      await uc.undo(res.batchId);
      await TransactionsDao(db).updateById(
        't0',
        const TransactionsCompanion(categoryId: Value(billsId)),
      );
      final before = await snapshot();
      expect(
        await codeOf(uc.undo(res.batchId)),
        BulkEditException.undoNotFound,
      );
      expect(await snapshot(), before);
    });

    test(
      '24 h expiry: usable just inside, refused at the limit, batch kept',
      () async {
        await seed(2);
        final res = await uc.apply({'t0', 't1'}, const SetCategory(foodId));
        final created = clockMs;
        clockMs = created + undoWindow.inMilliseconds - 1;
        expect((await uc.undo(res.batchId)).restored, 2);

        final res2 = await uc.apply({'t0'}, const SetCategory(billsId));
        final created2 = clockMs;
        clockMs = created2 + undoWindow.inMilliseconds;
        final before = await snapshot();
        expect(
          await codeOf(uc.undo(res2.batchId)),
          BulkEditException.undoExpired,
        );
        expect(await snapshot(), before);
        expect(await UndoBatchesDao(db).byId(res2.batchId), isNotNull);
        expect(await uc.purgeExpired(), 1);
        expect(await UndoBatchesDao(db).byId(res2.batchId), isNull);
      },
    );

    test(
      'a corrupt before-image changes nothing and keeps the batch',
      () async {
        await seed(2);
        final before = await snapshot();
        await UndoBatchesDao(db).insert(
          id: 'bad',
          createdAt: clockMs,
          descriptionKey: 'undo.bulk.category',
          beforeJson: '{"v":1,"kind":"category","at":1,"rows":[{"id":"t0"}]}',
        );
        expect(await codeOf(uc.undo('bad')), BulkEditException.undoCorrupt);
        expect(await snapshot(), before);
        expect(await UndoBatchesDao(db).byId('bad'), isNotNull);
      },
    );

    test('unknown batch', () async {
      expect(await codeOf(uc.undo('nope')), BulkEditException.undoNotFound);
    });
  });

  test('a new bulk edit purges batches older than 24 h', () async {
    await seed(2);
    final old = await uc.apply({'t0'}, const SetCategory(foodId));
    clockMs += undoWindow.inMilliseconds + 1;
    await uc.apply({'t1'}, const SetCategory(foodId));
    expect(await UndoBatchesDao(db).byId(old.batchId), isNull);
  });
}
