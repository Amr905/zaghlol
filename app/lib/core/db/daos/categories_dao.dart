// T-018: categories (database-schema §2.4; the table is v2, T-017). System
// categories have id `sys:<code>` and `system_code = <code>` (seeded by
// T-030, updated by catalog `category` ops); custom ones (Gold) have a ULID
// id and no system code. Categories are archived, not deleted: transactions,
// rules and budgets reference them. Writes go through guardWrite; nothing
// here logs.

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

/// The id of the system category [code] (`sys:groceries`).
String systemCategoryId(String code) => 'sys:$code';

class CategoriesDao {
  CategoriesDao(this._db);

  final AppDatabase _db;

  Future<void> insert(CategoriesCompanion row) =>
      guardWrite(() => _db.into(_db.categories).insert(row));

  /// Inserts or updates the system category [code] from a catalog
  /// `category` op (an UPDATE on conflict: references stay valid). Keeps
  /// `is_archived` on update.
  Future<void> upsertSystem({
    required String code,
    required String nameAr,
    required String nameEn,
    required String icon,
    required String color,
    required String bucket,
    required int sort,
  }) => guardWrite(
    () => _db
        .into(_db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: systemCategoryId(code),
            systemCode: Value(code),
            nameAr: nameAr,
            nameEn: nameEn,
            icon: icon,
            color: color,
            bucket: bucket,
            sort: sort,
          ),
          onConflict: DoUpdate(
            (_) => CategoriesCompanion(
              nameAr: Value(nameAr),
              nameEn: Value(nameEn),
              icon: Value(icon),
              color: Value(color),
              bucket: Value(bucket),
              sort: Value(sort),
            ),
            target: [_db.categories.id],
          ),
        ),
  );

  Future<CategoryRow?> byId(String id) => (_db.select(
    _db.categories,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<CategoryRow?> bySystemCode(String code) => (_db.select(
    _db.categories,
  )..where((c) => c.systemCode.equals(code))).getSingleOrNull();

  /// Categories not archived, by `sort` then id.
  Future<List<CategoryRow>> active() =>
      (_db.select(_db.categories)
            ..where((c) => c.isArchived.equals(0))
            ..orderBy([
              (c) => OrderingTerm.asc(c.sort),
              (c) => OrderingTerm.asc(c.id),
            ]))
          .get();

  /// Archives (or, with [archived] false, restores) category [id]. Returns
  /// the rows changed (0 or 1).
  Future<int> setArchived(String id, {required bool archived}) => guardWrite(
    () => (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(isArchived: Value(archived ? 1 : 0)),
    ),
  );
}
