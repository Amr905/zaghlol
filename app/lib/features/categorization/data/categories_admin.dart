// T-163: custom category management behind S-63/S-64 (FR-CAT-07). System
// categories are read-only; custom ones (Gold) are created, edited and
// deleted here. Delete needs a replacement: its transactions and rules move
// there in one database transaction, then the category is archived (rows
// that reference it stay valid). Failures are code-only; nothing here logs.

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/categories_dao.dart';
import '../../transactions/data/drift_transaction_repository.dart'
    show Clock, IdGenerator, newUuidV4;
import '../../transactions/data/transactions_providers.dart';

/// One category as the screens show it.
final class CategoryItem {
  const CategoryItem({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.icon,
    required this.color,
    required this.bucket,
    required this.isSystem,
    this.parentId,
  });

  final String id;
  final String nameAr;
  final String nameEn;
  final String icon;
  final String color;
  final String bucket;
  final bool isSystem;
  final String? parentId;

  String name(String languageCode) => languageCode == 'ar' ? nameAr : nameEn;
}

final class CategoriesAdminException implements Exception {
  const CategoriesAdminException(this.code);
  final String code;

  static const String invalidName = 'CAT_INVALID_NAME';
  static const String duplicateName = 'CAT_DUPLICATE_NAME';
  static const String invalidBucket = 'CAT_INVALID_BUCKET';
  static const String notFound = 'CAT_NOT_FOUND';
  static const String systemReadOnly = 'CAT_SYSTEM_READ_ONLY';
  static const String replacementRequired = 'CAT_REPLACEMENT_REQUIRED';
  static const String badParent = 'CAT_BAD_PARENT';

  @override
  String toString() => 'CategoriesAdminException($code)';
}

abstract interface class CategoriesAdmin {
  /// Active categories, system first by sort.
  Future<List<CategoryItem>> list();

  /// Creates a custom category. Gold gating is the caller's job; reading is
  /// never gated (BR-GOLD-04).
  Future<CategoryItem> create({
    required String name,
    required String bucket,
    required String icon,
    required String color,
    String? parentId,
  });

  Future<CategoryItem> update(
    String id, {
    required String name,
    required String bucket,
    required String icon,
    required String color,
    String? parentId,
  });

  /// Moves everything that uses [id] to [replacementId], then archives [id]
  /// (and its subcategories). Returns the number of transactions moved.
  Future<int> deleteWithReplacement(String id, {required String replacementId});
}

const Set<String> categoryBuckets = {
  'needs',
  'wants',
  'obligations',
  'savings',
  'income',
  'giving',
};

class DriftCategoriesAdmin implements CategoriesAdmin {
  DriftCategoriesAdmin(this._db, {Clock? clock, IdGenerator? newId})
    : _dao = CategoriesDao(_db),
      _now = clock ?? DateTime.now,
      _newId = newId ?? newUuidV4;

  final AppDatabase _db;
  final CategoriesDao _dao;
  final Clock _now;
  final IdGenerator _newId;

  static CategoryItem _item(CategoryRow r) => CategoryItem(
    id: r.id,
    nameAr: r.nameAr,
    nameEn: r.nameEn,
    icon: r.icon,
    color: r.color,
    bucket: r.bucket,
    isSystem: r.systemCode != null,
    parentId: r.parentId,
  );

  @override
  Future<List<CategoryItem>> list() async => [
    for (final r in await _dao.active()) _item(r),
  ];

  Future<String> _checked(
    String name,
    String bucket, {
    String? exceptId,
    String? parentId,
  }) async {
    final n = name.trim();
    if (n.isEmpty || n.length > 30) {
      throw const CategoriesAdminException(
        CategoriesAdminException.invalidName,
      );
    }
    if (!categoryBuckets.contains(bucket)) {
      throw const CategoriesAdminException(
        CategoriesAdminException.invalidBucket,
      );
    }
    final lower = n.toLowerCase();
    for (final c in await _dao.active()) {
      if (c.id != exceptId &&
          (c.nameAr.toLowerCase() == lower ||
              c.nameEn.toLowerCase() == lower)) {
        throw const CategoriesAdminException(
          CategoriesAdminException.duplicateName,
        );
      }
    }
    if (parentId != null) {
      final p = await _dao.byId(parentId);
      if (p == null ||
          p.isArchived != 0 ||
          p.parentId != null ||
          p.id == exceptId) {
        throw const CategoriesAdminException(
          CategoriesAdminException.badParent,
        );
      }
    }
    return n;
  }

  @override
  Future<CategoryItem> create({
    required String name,
    required String bucket,
    required String icon,
    required String color,
    String? parentId,
  }) async {
    final n = await _checked(name, bucket, parentId: parentId);
    final id = _newId();
    final max = (await _dao.active()).fold<int>(
      0,
      (m, c) => c.sort > m ? c.sort : m,
    );
    await _dao.insert(
      CategoriesCompanion.insert(
        id: id,
        nameAr: n,
        nameEn: n,
        icon: icon,
        color: color,
        bucket: bucket,
        sort: max + 1,
        parentId: Value(parentId),
      ),
    );
    return _item((await _dao.byId(id))!);
  }

  @override
  Future<CategoryItem> update(
    String id, {
    required String name,
    required String bucket,
    required String icon,
    required String color,
    String? parentId,
  }) async {
    final row = await _dao.byId(id);
    if (row == null) {
      throw const CategoriesAdminException(CategoriesAdminException.notFound);
    }
    if (row.systemCode != null) {
      throw const CategoriesAdminException(
        CategoriesAdminException.systemReadOnly,
      );
    }
    final n = await _checked(name, bucket, exceptId: id, parentId: parentId);
    await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        nameAr: Value(n),
        nameEn: Value(n),
        icon: Value(icon),
        color: Value(color),
        bucket: Value(bucket),
        parentId: Value(parentId),
      ),
    );
    return _item((await _dao.byId(id))!);
  }

  @override
  Future<int> deleteWithReplacement(
    String id, {
    required String replacementId,
  }) async {
    if (replacementId.isEmpty || replacementId == id) {
      throw const CategoriesAdminException(
        CategoriesAdminException.replacementRequired,
      );
    }
    final row = await _dao.byId(id);
    final rep = await _dao.byId(replacementId);
    if (row == null) {
      throw const CategoriesAdminException(CategoriesAdminException.notFound);
    }
    if (row.systemCode != null) {
      throw const CategoriesAdminException(
        CategoriesAdminException.systemReadOnly,
      );
    }
    if (rep == null || rep.isArchived != 0 || rep.parentId == id) {
      throw const CategoriesAdminException(
        CategoriesAdminException.replacementRequired,
      );
    }
    final at = _now().toUtc().millisecondsSinceEpoch;
    return _db.transaction(() async {
      final moved = await _db.customUpdate(
        'UPDATE transactions SET category_id = ?1, updated_at = ?2 '
        'WHERE category_id = ?3',
        variables: [
          Variable.withString(replacementId),
          Variable.withInt(at),
          Variable.withString(id),
        ],
        updates: {_db.transactions},
      );
      await _db.customUpdate(
        'UPDATE merchant_rules SET category_id = ?1 WHERE category_id = ?2',
        variables: [
          Variable.withString(replacementId),
          Variable.withString(id),
        ],
        updates: {_db.merchantRules},
      );
      await _dao.setArchived(id, archived: true);
      return moved;
    });
  }
}

final categoriesAdminProvider = FutureProvider<CategoriesAdmin>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftCategoriesAdmin(
    db,
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
  );
}, name: 'categoriesAdminProvider');
