// T-163: custom category CRUD and delete-with-replacement. Synthetic data.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/categorization/data/categories_admin.dart';

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
}
