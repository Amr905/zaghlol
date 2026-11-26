// T-359: Right / Wrong on an AI category (LLM-CATEGORISE, FR-LCAT-22/23/24,
// llm-categorise.md §5 and §7 "UI").
//
//  * confirm: the merchant gets a user rule in the suggestion's category (it
//    replaces the AI category on every row of that merchant, T-357), the
//    suggestion becomes `confirmed` and one `llm_cat_confirmation` row goes
//    to the outbox.
//  * correct: the same with the user's category; state `corrected`, outbox
//    `llm_cat_correction`, `userCategory` = the system code or `custom`
//    (a custom category's name or id is never queued).
//  * undo (within [undoWindow]): puts back the rule, the touched transaction
//    columns, the suggestion row and the outbox exactly as they were.
// Everything is one database transaction. Feedback exists only for a
// merchant that has an `unconfirmed` suggestion, i.e. one that was eligible
// and answered by the backend; a person payee never has one. Failures are
// code-only; nothing here logs, and no merchant text is ever carried.

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/ai_merchant_suggestions_dao.dart';
import '../../../core/db/daos/merchant_rules_dao.dart' as dao;
import '../../../core/db/daos/outbox_dao.dart';
import '../../../core/db/daos/write_errors.dart';
import '../../transactions/data/drift_transaction_repository.dart'
    show Clock, IdGenerator, newUuidV4;
import '../domain/merchant_rule.dart';

/// The Undo window (FR-LCAT-24).
const Duration llmCatUndoWindow = Duration(seconds: 5);

final class LlmCatFeedbackException extends SafeException {
  LlmCatFeedbackException(super.code);

  /// The merchant has no `unconfirmed` AI suggestion (never suggested,
  /// already decided, or no answer).
  static const String notPending = 'LCAT_FEEDBACK_NOT_PENDING';

  /// "Wrong" with the category the AI already chose.
  static const String sameCategory = 'LCAT_FEEDBACK_SAME_CATEGORY';

  /// The Undo window ended, or the receipt was already used.
  static const String undoExpired = 'LCAT_FEEDBACK_UNDO_EXPIRED';
}

/// What the UI keeps for the 5-second Undo. Holds the exact rows to put back.
final class LlmCatFeedbackReceipt {
  LlmCatFeedbackReceipt._({
    required this.merchantNorm,
    required this.expiresAt,
    required this.ruleId,
    required this._previousRule,
    required this._transactions,
    required this.outboxId,
    required this.verdictWrong,
    required this.categoryId,
  });

  final String merchantNorm;
  final DateTime expiresAt;

  /// The category the merchant now has (for the confirmation message).
  final String categoryId;
  final bool verdictWrong;
  final String ruleId;
  final String? outboxId;
  final MerchantRuleRow? _previousRule;
  final List<_TxnState> _transactions;
  bool _used = false;

  @override
  String toString() => 'LlmCatFeedbackReceipt';
}

final class _TxnState {
  const _TxnState(this.id, this.categoryId, this.source, this.updatedAt);
  final String id;
  final String? categoryId;
  final String source;
  final int updatedAt;
}

class LlmCatFeedback {
  LlmCatFeedback(this._db, this._rules, {Clock? clock, IdGenerator? newId})
    : _now = clock ?? DateTime.now,
      _newId = newId ?? newUuidV4;

  final AppDatabase _db;
  final RulesRepository _rules;
  final Clock _now;
  final IdGenerator _newId;

  /// "Right": keeps the AI's category as the user's rule.
  Future<LlmCatFeedbackReceipt> confirm(String merchantNorm) =>
      _decide(merchantNorm, chosenCategoryId: null);

  /// "Wrong": [chosenCategoryId] (from the picker) replaces the AI's. A
  /// cancelled picker never reaches here, so nothing changes.
  Future<LlmCatFeedbackReceipt> correct(
    String merchantNorm,
    String chosenCategoryId,
  ) => _decide(merchantNorm, chosenCategoryId: chosenCategoryId);

  Future<LlmCatFeedbackReceipt> _decide(
    String merchantNorm, {
    required String? chosenCategoryId,
  }) {
    final wrong = chosenCategoryId != null;
    final at = _now().toUtc();
    final ms = at.millisecondsSinceEpoch;
    return guardWrite(
      () => _db.transaction(() async {
        final sug = await AiMerchantSuggestionsDao(_db)
            .byMerchant(merchantNorm);
        final aiCat = sug?.categoryId;
        if (sug == null ||
            sug.state != AiSuggestionStateCode.unconfirmed ||
            aiCat == null) {
          throw LlmCatFeedbackException(LlmCatFeedbackException.notPending);
        }
        if (wrong && chosenCategoryId == aiCat) {
          throw LlmCatFeedbackException(LlmCatFeedbackException.sameCategory);
        }
        final target = chosenCategoryId ?? aiCat;
        final rulesDao = dao.MerchantRulesDao(_db);
        final prevRule = await rulesDao.find(
          dao.RuleMatchKind.merchantNorm,
          merchantNorm,
        );
        final before = await _txnStates(merchantNorm);

        final rule = await _rules.save(
          kind: RuleMatchKind.merchantNorm,
          value: merchantNorm,
          categoryId: target,
        );
        await _rules.applyToPast(rule.id);
        // applyToPast skips rows already in the rule's category, so a Right
        // would leave their AI mark: they become rule-sourced too (same
        // guards as the recategorizer: live, not internal, not verified).
        await _db.customUpdate(
          "UPDATE transactions SET category_source = 'user_rule', "
          'updated_at = ?1 WHERE merchant_norm = ?2 AND category_id = ?3 '
          "AND category_source = 'ai' AND deleted_at IS NULL "
          'AND is_internal = 0 AND is_user_verified = 0',
          variables: [
            Variable.withInt(ms),
            Variable.withString(merchantNorm),
            Variable.withString(target),
          ],
          updates: {_db.transactions},
        );
        await AiMerchantSuggestionsDao(_db).decide(
          merchantNorm,
          state: wrong
              ? AiSuggestionStateCode.corrected
              : AiSuggestionStateCode.confirmed,
          at: ms,
        );

        // The outbox item: closed fields only; a missing system code on the
        // AI side (never expected) just means nothing is queued.
        final aiCode = await _systemCode(aiCat);
        final src = sug.source;
        String? outboxId;
        if (aiCode != null && src != null) {
          outboxId = _newId();
          await OutboxDao(_db).enqueue(
            id: outboxId,
            kind: wrong
                ? OutboxKind.llmCatCorrection
                : OutboxKind.llmCatConfirmation,
            payload: {
              'merchantNorm': merchantNorm,
              'verdict': wrong ? 'wrong' : 'right',
              'aiCategory': aiCode,
              'userCategory': wrong ? await _userCode(target) : aiCode,
              'source': src,
            },
            createdAt: ms,
          );
        }
        return LlmCatFeedbackReceipt._(
          merchantNorm: merchantNorm,
          expiresAt: at.add(llmCatUndoWindow),
          ruleId: rule.id,
          previousRule: prevRule,
          transactions: before,
          outboxId: outboxId,
          verdictWrong: wrong,
          categoryId: target,
        );
      }),
    );
  }

  /// Restores the rule, the merchant's transaction rows, the suggestion and
  /// the outbox to what [receipt] captured. Throws `LCAT_FEEDBACK_UNDO_EXPIRED`
  /// after [llmCatUndoWindow] or on a second use; changes nothing then.
  Future<void> undo(LlmCatFeedbackReceipt receipt) async {
    if (receipt._used || _now().toUtc().isAfter(receipt.expiresAt)) {
      throw LlmCatFeedbackException(LlmCatFeedbackException.undoExpired);
    }
    receipt._used = true;
    await guardWrite(
      () => _db.transaction(() async {
        // Rows first, while the rule still exists.
        for (final t in receipt._transactions) {
          // Only a row still as this feedback left it (a later user edit
          // wins): a rule-sourced row in the rule's category.
          await _db.customUpdate(
            'UPDATE transactions SET category_id = ?1, category_source = ?2, '
            'updated_at = ?3 WHERE id = ?4 '
            "AND category_source = 'user_rule' AND category_id IS ?5",
            variables: [
              Variable<String>(t.categoryId),
              Variable.withString(t.source),
              Variable.withInt(t.updatedAt),
              Variable.withString(t.id),
              Variable.withString(receipt.categoryId),
            ],
            updates: {_db.transactions},
          );
        }
        final prev = receipt._previousRule;
        if (prev == null) {
          await dao.MerchantRulesDao(_db).deleteById(receipt.ruleId);
        } else {
          await _db.customUpdate(
            'UPDATE merchant_rules SET category_id = ?1, '
            'last_applied_at = ?2 WHERE id = ?3',
            variables: [
              Variable.withString(prev.categoryId),
              Variable<int>(prev.lastAppliedAt),
              Variable.withString(prev.id),
            ],
            updates: {_db.merchantRules},
          );
        }
        await AiMerchantSuggestionsDao(_db).undoDecision(receipt.merchantNorm);
        final o = receipt.outboxId;
        if (o != null) await OutboxDao(_db).deleteIds([o]);
      }),
    );
  }

  Future<List<_TxnState>> _txnStates(String merchantNorm) async {
    final rows = await _db
        .customSelect(
          'SELECT id, category_id, category_source, updated_at '
          'FROM transactions WHERE merchant_norm = ?1 ORDER BY id',
          variables: [Variable.withString(merchantNorm)],
          readsFrom: {_db.transactions},
        )
        .get();
    return [
      for (final r in rows)
        _TxnState(
          r.read<String>('id'),
          r.read<String?>('category_id'),
          r.read<String>('category_source'),
          r.read<int>('updated_at'),
        ),
    ];
  }

  Future<String?> _systemCode(String categoryId) async {
    final r = await (_db.select(
      _db.categories,
    )..where((c) => c.id.equals(categoryId))).getSingleOrNull();
    return r == null || r.isCustom != 0 ? null : r.systemCode;
  }

  /// The system code, or `custom` for a user category (its name is never
  /// queued).
  Future<String> _userCode(String categoryId) async =>
      await _systemCode(categoryId) ?? 'custom';
}
