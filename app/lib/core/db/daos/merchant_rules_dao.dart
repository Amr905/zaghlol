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

  Future<MerchantRuleRow?> byId(String id) => guardRead(
    () => (_db.select(
      _db.merchantRules,
    )..where((r) => r.id.equals(id))).getSingleOrNull(),
  );

  /// Points rule [id] at [categoryId]. Returns the rows changed (0 or 1).
  Future<int> setCategory(String id, String categoryId) => guardWrite(
    () => (_db.update(_db.merchantRules)..where((r) => r.id.equals(id))).write(
      MerchantRulesCompanion(categoryId: Value(categoryId)),
    ),
  );

  Future<int> deleteById(String id) => guardWrite(
    () => (_db.delete(_db.merchantRules)..where((r) => r.id.equals(id))).go(),
  );

  /// Rows of one rule that apply-to-past may touch (T-074). One predicate
  /// shared by count, list and update, so the preview and the write agree.
  ///
  /// Never destroy a user edit on doubt: a row qualifies only when it is
  /// live, not internal, not user-verified, and its category came from the
  /// pipeline (`none`, `catalog`, `heuristic`). `user` and `user_rule` rows
  /// (an edit, or another rule's work) are left alone, as is a row already
  /// in the rule's category. The rule row, its category and the archive flag
  /// are read inside the same statement, so a rule deleted or a category
  /// archived by another connection leaves nothing to change.
  static const String _eligible = '''
transactions.deleted_at IS NULL
AND transactions.is_internal = 0
AND transactions.is_user_verified = 0
AND transactions.category_source IN ('none', 'catalog', 'heuristic')
AND EXISTS (
  SELECT 1 FROM merchant_rules r
  JOIN categories c ON c.id = r.category_id AND c.is_archived = 0
  WHERE r.id = ?1
    AND (transactions.category_id IS NULL OR transactions.category_id <> r.category_id)
    AND (
      (r.match_kind = 'merchant_norm' AND transactions.merchant_norm = r.match_value)
      OR (r.match_kind = 'counterparty' AND transactions.counterparty_value = r.match_value)
      OR (r.match_kind = 'catalog_merchant'
          AND transactions.catalog_merchant_id = CAST(r.match_value AS INTEGER))
    )
)''';

  static String _idsClause(Set<String>? ids) => ids == null
      ? ''
      : ' AND transactions.id IN (${List.filled(ids.length, '?').join(',')})';

  List<Variable> _vars(String ruleId, Set<String>? ids, [int? at]) => [
    Variable.withString(ruleId),
    if (at != null) Variable.withInt(at),
    if (ids != null)
      for (final id in ids) Variable.withString(id),
  ];

  /// Number of past transactions rule [ruleId] would change.
  Future<int> countPastMatches(String ruleId) => guardRead(() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM transactions WHERE $_eligible',
          variables: [Variable.withString(ruleId)],
          readsFrom: {_db.transactions, _db.merchantRules},
        )
        .getSingle();
    return row.read<int>('c');
  });

  /// Ids of up to [limit] past transactions rule [ruleId] would change,
  /// newest first.
  Future<List<String>> pastMatchIds(String ruleId, {required int limit}) =>
      guardRead(() async {
        final rows = await _db
            .customSelect(
              'SELECT id FROM transactions WHERE $_eligible '
              'ORDER BY occurred_at DESC, id LIMIT $limit',
              variables: [Variable.withString(ruleId)],
              readsFrom: {_db.transactions, _db.merchantRules},
            )
            .get();
        return [for (final r in rows) r.read<String>('id')];
      });

  /// Points the eligible past transactions of rule [ruleId] (limited to
  /// [ids] when given) at the rule's category in ONE conditional statement
  /// (every guard is re-checked in SQL, so a user edit committed by another
  /// connection is never overwritten), then stamps the rule's
  /// `last_applied_at`. Returns the number of transactions changed.
  ///
  /// Deliberately not wrapped in a drift transaction: `BEGIN IMMEDIATE`
  /// from a second connection fails at once with SQLITE_BUSY instead of
  /// waiting for the busy timeout, while a lone write statement waits. The
  /// stamp is metadata, so a crash between the two statements loses
  /// nothing.
  Future<int> applyToPast(
    String ruleId, {
    required Set<String>? ids,
    required int at,
  }) async {
    final changed = await guardWrite(
      () => _db.customUpdate(
        'UPDATE transactions SET '
        'category_id = (SELECT category_id FROM merchant_rules WHERE id = ?1), '
        "category_source = 'user_rule', updated_at = ?2 "
        'WHERE $_eligible${_idsClause(ids)}',
        variables: _vars(ruleId, ids, at),
        updates: {_db.transactions},
      ),
    );
    await markApplied(ruleId, at: at);
    return changed;
  }
}
