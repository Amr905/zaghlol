// T-163: custom category CRUD and delete-with-replacement. Synthetic data.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/budgets_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/categorization/data/categories_admin.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

Future<String?> code(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on CategoriesAdminException catch (e) {
    return e.code;
  }
}

void main() {
  late AppDatabase db;
  late DriftCategoriesAdmin admin;
  var n = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    admin = DriftCategoriesAdmin(db, newId: () => 'c${n++}');
    final dao = CategoriesDao(db);
    await dao.upsertSystem(
      code: 'food',
      nameAr: 'أكل',
      nameEn: 'Food',
      icon: 'cart',
      color: '#174C4F',
      bucket: 'needs',
      sort: 1,
    );
    await AccountsDao(db).insert(account('acc1'));
  });
  tearDown(() => db.close());

  test('create validates name, bucket and uniqueness', () async {
    expect(
      await code(
        admin.create(
          name: ' ',
          bucket: 'wants',
          icon: 'cart',
          color: '#174C4F',
        ),
      ),
      CategoriesAdminException.invalidName,
    );
    expect(
      await code(
        admin.create(
          name: 'x' * 31,
          bucket: 'wants',
          icon: 'cart',
          color: '#174C4F',
        ),
      ),
      CategoriesAdminException.invalidName,
    );
    expect(
      await code(
        admin.create(
          name: 'Trips',
          bucket: 'bad',
          icon: 'cart',
          color: '#174C4F',
        ),
      ),
      CategoriesAdminException.invalidBucket,
    );
    expect(
      await code(
        admin.create(
          name: 'food',
          bucket: 'wants',
          icon: 'cart',
          color: '#174C4F',
        ),
      ),
      CategoriesAdminException.duplicateName,
    );
    final c = await admin.create(
      name: 'Trips',
      bucket: 'wants',
      icon: 'travel',
      color: '#0F7A55',
    );
    expect(c.isSystem, isFalse);
    expect((await admin.list()).map((x) => x.id), contains(c.id));
  });

  test('system categories cannot be edited or deleted', () async {
    expect(
      await code(
        admin.update(
          'sys:food',
          name: 'Z',
          bucket: 'needs',
          icon: 'cart',
          color: '#174C4F',
        ),
      ),
      CategoriesAdminException.systemReadOnly,
    );
    expect(
      await code(admin.deleteWithReplacement('sys:food', replacementId: 'c0')),
      CategoriesAdminException.systemReadOnly,
    );
  });

  test(
    'delete requires a replacement and moves transactions and rules',
    () async {
      final c = await admin.create(
        name: 'Trips',
        bucket: 'wants',
        icon: 'travel',
        color: '#0F7A55',
      );
      await TransactionsDao(db)
          .insert(txn('t1').copyWith(categoryId: Value(c.id)));
      expect(
        await code(admin.deleteWithReplacement(c.id, replacementId: '')),
        CategoriesAdminException.replacementRequired,
      );
      expect(
        await code(admin.deleteWithReplacement(c.id, replacementId: c.id)),
        CategoriesAdminException.replacementRequired,
      );
      expect(
        await admin.deleteWithReplacement(c.id, replacementId: 'sys:food'),
        1,
      );
      final row = await TransactionsDao(db).byId('t1');
      expect(row!.categoryId, 'sys:food');
      expect((await admin.list()).map((x) => x.id), isNot(contains(c.id)));
    },
  );

  test('delete frees children and moves their budget (FU-179a/b)', () async {
    final p = await admin.create(
      name: 'Trips',
      bucket: 'wants',
      icon: 'travel',
      color: '#0F7A55',
    );
    final child = await admin.create(
      name: 'Hotels',
      bucket: 'wants',
      icon: 'travel',
      color: '#0F7A55',
      parentId: p.id,
    );
    await db.customStatement(
      'INSERT INTO budgets (id, category_id, currency, limit_minor, period, '
      "created_at) VALUES ('b1', '${p.id}', 'EGP', 1000, 'cycle', 1)",
    );
    await db.customStatement(
      'INSERT INTO fired_alerts (kind, subject_id, period_key, threshold, '
      "fired_at) VALUES ('budget', 'b1', 'k', 80, 1)",
    );
    await admin.deleteWithReplacement(p.id, replacementId: 'sys:food');
    expect((await admin.list()).map((x) => x.id), contains(child.id));
    expect((await db.select(db.budgets).get()).single.categoryId, 'sys:food');
    expect(await db.select(db.firedAlerts).get(), hasLength(1));
  });

  test('delete re-points budgets and drops colliding ones (FU-179b)', () async {
    final c = await admin.create(
      name: 'Trips',
      bucket: 'wants',
      icon: 'travel',
      color: '#0F7A55',
    );
    final b = BudgetsDao(db);
    Money m(int v, String cur) => Money(Currency.of(cur), v);
    await b.insert(
      id: 'b1',
      categoryId: c.id,
      limit: m(100, 'EGP'),
      period: BudgetPeriod.cycle,
      createdAt: 1,
    );
    await b.insert(
      id: 'b2',
      categoryId: c.id,
      limit: m(100, 'USD'),
      period: BudgetPeriod.cycle,
      createdAt: 1,
    );
    await b.insert(
      id: 'b3',
      categoryId: 'sys:food',
      limit: m(500, 'EGP'),
      period: BudgetPeriod.cycle,
      createdAt: 1,
    );
    await admin.deleteWithReplacement(c.id, replacementId: 'sys:food');
    final rows = await db.select(db.budgets).get();
    expect(rows.map((r) => r.id).toSet(), {'b2', 'b3'});
    expect(rows.every((r) => r.categoryId == 'sys:food'), isTrue);
  });
}
