// T-018: user merchant rules (database-schema §2.4, FR-CAT-05/08; never
// uploaded). One rule per (match_kind, match_value); the value's form is
// CHECKed per kind (financial_b.drift). The rules repository (T-074) builds
// on this. Writes go through guardWrite; nothing here logs.

import 'package:drift/drift.dart';

import '../app_database.dart';
import 'write_errors.dart';

/// `merchant_rules.match_kind` values.
abstract final class RuleMatchKind {
  static const String catalogMerchant = 'catalog_merchant';
  static const String merchantNorm = 'merchant_norm';
  static const String counterparty = 'counterparty';
}

class MerchantRulesDao {
  MerchantRulesDao(this._db);

  final AppDatabase _db;

  /// Inserts rule [row], or, when a rule for the same (kind, value) exists,
  /// points that rule at `row.categoryId` (its id and `created_at` stay).
  Future<void> upsert(MerchantRulesCompanion row) => guardWrite(
    () => _db
        .into(_db.merchantRules)
        .insert(
          row,
          onConflict: DoUpdate(
            (_) => MerchantRulesCompanion(categoryId: row.categoryId),
            target: [_db.merchantRules.matchKind, _db.merchantRules.matchValue],
          ),
        ),
  );

  /// The rule for ([kind], [value]), if any.
  Future<MerchantRuleRow?> find(String kind, String value) => guardRead(
    () =>
        (_db.select(_db.merchantRules)..where(
              (r) => r.matchKind.equals(kind) & r.matchValue.equals(value),
            ))
            .getSingleOrNull(),
  );

  Future<List<MerchantRuleRow>> all() => (_db.select(
    _db.merchantRules,
  )..orderBy([(r) => OrderingTerm.asc(r.createdAt)])).get();

  /// Records that rule [id] was applied at [at] (apply-to-past).
  Future<int> markApplied(String id, {required int at}) => guardWrite(
    () => (_db.update(_db.merchantRules)..where((r) => r.id.equals(id))).write(
      MerchantRulesCompanion(lastAppliedAt: Value(at)),
    ),
  );

  Future<int> deleteById(String id) => guardWrite(
    () => (_db.delete(_db.merchantRules)..where((r) => r.id.equals(id))).go(),
  );
}
