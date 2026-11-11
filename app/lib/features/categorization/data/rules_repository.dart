// T-074: the Drift-backed [RulesRepository]. Validates a rule's value per
// kind before it reaches SQL (the CHECKs are the backstop), and applies a
// rule to past transactions in one conditional statement that re-checks
// every guard in SQL, so a concurrent edit by another connection is never
// overwritten. Failures are code-only; nothing here logs.

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/catalog_dao.dart' show isCanonicalMerchantKey;
import '../../../core/db/daos/categories_dao.dart';
import '../../../core/db/daos/merchant_rules_dao.dart' as dao;
import '../../transactions/data/drift_transaction_repository.dart'
    show Clock, IdGenerator, maxIdsPerCall, newUuidV4;
import '../domain/merchant_rule.dart';

/// Longest counterparty value (matches the table CHECK), in code units.
const int maxCounterpartyLength = 128;

/// Largest page [DriftRulesRepository.pastMatchIds] returns.
const int maxPastMatchPage = 500;

final RegExp _catalogId = RegExp(r'^[1-9][0-9]{0,9}$');
final RegExp _controls = RegExp(r'[\u0000-\u001f\u007f-\u009f]');

class DriftRulesRepository implements RulesRepository {
  DriftRulesRepository(
    this._rules,
    this._categories, {
    Clock? clock,
    IdGenerator? newId,
  }) : _now = clock ?? DateTime.now,
       _newId = newId ?? newUuidV4;

  final dao.MerchantRulesDao _rules;
  final CategoriesDao _categories;
  final Clock _now;
  final IdGenerator _newId;

  int _nowMs() => _now().toUtc().millisecondsSinceEpoch;

  static bool validValue(RuleMatchKind kind, String value) => switch (kind) {
    RuleMatchKind.merchantNorm => isCanonicalMerchantKey(value),
    RuleMatchKind.catalogMerchant => _catalogId.hasMatch(value),
    RuleMatchKind.counterparty =>
      value.isNotEmpty &&
          value.length <= maxCounterpartyLength &&
          !_controls.hasMatch(value),
  };

  Future<void> _requireUsableCategory(String categoryId) async {
    final c = await _categories.byId(categoryId);
    if (c == null || c.isArchived != 0) {
      throw RulesException(RulesException.categoryUnavailable);
    }
  }

  @override
  Future<List<MerchantRule>> list() async => [
    for (final r in await _rules.all()) _toRule(r),
  ];

  @override
  Future<MerchantRule> save({
    required RuleMatchKind kind,
    required String value,
    required String categoryId,
  }) async {
    if (!validValue(kind, value) || categoryId.isEmpty) {
      throw RulesException(RulesException.invalid);
    }
    await _requireUsableCategory(categoryId);
    await _rules.upsert(
      MerchantRulesCompanion.insert(
        id: _newId(),
        matchKind: kind.code,
        matchValue: value,
        categoryId: categoryId,
        createdAt: _nowMs(),
      ),
    );
    final row = await _rules.find(kind.code, value);
    if (row == null) throw RulesException(RulesException.notFound);
    return _toRule(row);
  }

  @override
  Future<MerchantRule> changeCategory(String id, String categoryId) async {
    await _requireUsableCategory(categoryId);
    final n = await _rules.setCategory(id, categoryId);
    final row = await _rules.byId(id);
    if (n == 0 || row == null) throw RulesException(RulesException.notFound);
    return _toRule(row);
  }

  @override
  Future<bool> delete(String id) async => await _rules.deleteById(id) > 0;

  @override
  Future<int> countPastMatches(String id) => _rules.countPastMatches(id);

  @override
  Future<List<String>> pastMatchIds(String id, {int limit = 200}) {
    if (limit < 1) throw RulesException(RulesException.invalid);
    return _rules.pastMatchIds(
      id,
      limit: limit > maxPastMatchPage ? maxPastMatchPage : limit,
    );
  }

  @override
  Future<int> applyToPast(String id, {Set<String>? transactionIds}) async {
    if (transactionIds != null) {
      if (transactionIds.length > maxIdsPerCall) {
        throw RulesException(RulesException.invalid);
      }
      // An empty choice means "nothing", never "everything".
      if (transactionIds.isEmpty) return 0;
    }
    return await _rules.applyToPast(id, ids: transactionIds, at: _nowMs());
  }

  @override
  Future<RuleMatch?> match({
    String? counterparty,
    String? merchantNorm,
    int? catalogMerchantId,
  }) async {
    final keys = <(RuleMatchKind, String)>[
      if (counterparty != null) (RuleMatchKind.counterparty, counterparty),
      if (merchantNorm != null) (RuleMatchKind.merchantNorm, merchantNorm),
      if (catalogMerchantId != null)
        (RuleMatchKind.catalogMerchant, '$catalogMerchantId'),
    ];
    for (final (kind, value) in keys) {
      if (!validValue(kind, value)) continue;
      final row = await _rules.find(kind.code, value);
      if (row != null) {
        return RuleMatch(ruleId: row.id, categoryId: row.categoryId);
      }
    }
    return null;
  }

  MerchantRule _toRule(MerchantRuleRow r) {
    final kind = RuleMatchKind.tryFromCode(r.matchKind);
    if (kind == null) throw RulesException(RulesException.corruptRow);
    return MerchantRule(
      id: r.id,
      kind: kind,
      value: r.matchValue,
      categoryId: r.categoryId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true),
      lastAppliedAt: r.lastAppliedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(r.lastAppliedAt!, isUtc: true),
    );
  }
}
