// T-077: bulk edit and one-step Undo (FR-TXN-06, domain-algorithms §14, D-36).
//
// One database transaction per call, so a bulk edit and an Undo are each all
// or none. The before-image goes to `undo_batches` in the same transaction.
// Money is never touched: only category, account and the soft-delete mark
// change, so every amount stays the exact integer minor units it was.
//
// Failures are code-only [BulkEditException]s (or DbWriteException); nothing
// here logs and no exception carries a value from a row.

import 'dart:convert';

import 'package:drift/drift.dart' show Expression, Value;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/accounts_dao.dart';
import '../../../core/db/daos/catalog_dao.dart' show isCanonicalMerchantKey;
import '../../../core/db/daos/categories_dao.dart';
import '../../../core/db/daos/merchant_rules_dao.dart';
import '../../../core/db/daos/misc_daos.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../../core/db/daos/write_errors.dart' show guardWrite;
import '../data/drift_transaction_repository.dart'
    show Clock, IdGenerator, maxIdsPerCall, newUuidV4;

/// How long an Undo batch can be used (domain-algorithms §14).
const Duration undoWindow = Duration(hours: 24);

/// Failure codes of this use case.
///
/// `BULK_INVALID`: empty or oversized id set, or a malformed target.
/// `BULK_NOT_FOUND`: some id is not a live transaction (nothing changed).
/// `BULK_CATEGORY_UNAVAILABLE`: category missing or archived.
/// `BULK_ACCOUNT_NOT_FOUND`: target account missing.
/// `BULK_UNDO_NOT_FOUND`: unknown or already used batch.
/// `BULK_UNDO_EXPIRED`: older than [undoWindow]; the batch is kept.
/// `BULK_UNDO_CORRUPT`: the stored before-image is unreadable; the batch is
/// kept untouched.
final class BulkEditException extends SafeException {
  BulkEditException(super.code);

  static const String invalid = 'BULK_INVALID';
  static const String notFound = 'BULK_NOT_FOUND';
  static const String categoryUnavailable = 'BULK_CATEGORY_UNAVAILABLE';
  static const String accountNotFound = 'BULK_ACCOUNT_NOT_FOUND';
  static const String undoNotFound = 'BULK_UNDO_NOT_FOUND';
  static const String undoExpired = 'BULK_UNDO_EXPIRED';
  static const String undoCorrupt = 'BULK_UNDO_CORRUPT';
}

/// What a bulk edit does to every selected row.
sealed class BulkChange {
  const BulkChange();
}

/// Sets the category (the rows become user-verified, source `user`). With
/// [alwaysUseForMerchants], also saves one merchant rule per distinct
/// merchant among the rows (catalog merchant, else normalised name; rows
/// with neither get no rule).
final class SetCategory extends BulkChange {
  const SetCategory(this.categoryId, {this.alwaysUseForMerchants = false});
  final String categoryId;
  final bool alwaysUseForMerchants;
}

/// Moves the rows to another account. Amounts and currencies are unchanged;
/// internal-transfer pairing is not recomputed.
final class SetAccount extends BulkChange {
  const SetAccount(this.accountId);
  final String accountId;
}

/// Soft-deletes the rows (restorable for 30 days; Undo restores at once).
final class DeleteTransactions extends BulkChange {
  const DeleteTransactions();
}

final class BulkEditResult {
  const BulkEditResult({
    required this.batchId,
    required this.changed,
    required this.rulesCreated,
  });

  /// The id to pass to [BulkEditUseCase.undo].
  final String batchId;
  final int changed;

  /// Rules newly created or re-pointed by this batch.
  final int rulesCreated;
}

final class UndoResult {
  const UndoResult({required this.restored, required this.skipped});

  /// Rows put back exactly as they were.
  final int restored;

  /// Rows (or rules) edited again after the bulk edit. They are left as the
  /// user last set them: Undo never overwrites a later edit.
  final int skipped;
}

class BulkEditUseCase {
  BulkEditUseCase(this._db, {Clock? clock, IdGenerator? newId})
    : _now = clock ?? DateTime.now,
      _newId = newId ?? newUuidV4,
      _txns = TransactionsDao(_db),
      _rules = MerchantRulesDao(_db),
      _undo = UndoBatchesDao(_db),
      _categories = CategoriesDao(_db),
      _accounts = AccountsDao(_db);

  final AppDatabase _db;
  final Clock _now;
  final IdGenerator _newId;
  final TransactionsDao _txns;
  final MerchantRulesDao _rules;
  final UndoBatchesDao _undo;
  final CategoriesDao _categories;
  final AccountsDao _accounts;

  int _nowMs() => _now().toUtc().millisecondsSinceEpoch;

  /// Applies [change] to the live transactions [ids] in one database
  /// transaction and records the before-image. All or none: any id that is
  /// not a live row fails the whole call.
  Future<BulkEditResult> apply(Iterable<String> ids, BulkChange change) async {
    final unique = ids.toSet();
    if (unique.isEmpty || unique.length > maxIdsPerCall) _invalid();
    final now = _nowMs();
    final batchId = _newId();
    return _txns.inTransaction(() async {
      await _undo.purgeOlderThan(now - undoWindow.inMilliseconds + 1);
      final rows = <TransactionRow>[];
      for (final id in unique) {
        final row = await _txns.byId(id);
        if (row == null || row.deletedAt != null) {
          throw BulkEditException(BulkEditException.notFound);
        }
        rows.add(row);
      }
      final image = <String, Object?>{
        'v': 1,
        'at': now,
        'rows': <Object?>[],
        'rules_created': <Object?>[],
        'rules_repointed': <Object?>[],
      };
      final imageRows = image['rows']! as List<Object?>;
      var rulesTouched = 0;

      switch (change) {
        case SetCategory(:final categoryId, :final alwaysUseForMerchants):
          if (categoryId.isEmpty) _invalid();
          final c = await _categories.byId(categoryId);
          if (c == null || c.isArchived != 0) {
            throw BulkEditException(BulkEditException.categoryUnavailable);
          }
          image['kind'] = 'category';
          image['to'] = categoryId;
          for (final r in rows) {
            imageRows.add({
              'id': r.id,
              'cat': r.categoryId,
              'src': r.categorySource,
              'ver': r.isUserVerified,
              'upd': r.updatedAt,
            });
            await _write(
              r.id,
              TransactionsCompanion(
                categoryId: Value(categoryId),
                categorySource: const Value('user'),
                isUserVerified: const Value(1),
                updatedAt: Value(now),
              ),
            );
          }
          if (alwaysUseForMerchants) {
            rulesTouched = await _saveRules(rows, categoryId, now, image);
          }
        case SetAccount(:final accountId):
          if (accountId.isEmpty) _invalid();
          if (await _accounts.byId(accountId) == null) {
            throw BulkEditException(BulkEditException.accountNotFound);
          }
          image['kind'] = 'account';
          image['to'] = accountId;
          for (final r in rows) {
            imageRows.add({'id': r.id, 'acc': r.accountId, 'upd': r.updatedAt});
            await _write(
              r.id,
              TransactionsCompanion(
                accountId: Value(accountId),
                updatedAt: Value(now),
              ),
            );
          }
        case DeleteTransactions():
          image['kind'] = 'delete';
          for (final r in rows) {
            imageRows.add({'id': r.id, 'upd': r.updatedAt});
            if (await _txns.softDelete(r.id, at: now) != 1) {
              throw BulkEditException(BulkEditException.notFound);
            }
          }
      }

      await _undo.insert(
        id: batchId,
        createdAt: now,
        descriptionKey: switch (change) {
          SetCategory() => 'undo.bulk.category',
          SetAccount() => 'undo.bulk.account',
          DeleteTransactions() => 'undo.bulk.delete',
        },
        beforeJson: jsonEncode(image),
      );
      return BulkEditResult(
        batchId: batchId,
        changed: rows.length,
        rulesCreated: rulesTouched,
      );
    });
  }

  /// Undoes batch [batchId] in one database transaction: restores each row
  /// to its before-image and removes the rules the batch created. A row or
  /// rule edited after the batch is left alone and counted as skipped. The
  /// batch is consumed in the same transaction, so a second Undo (a retry or
  /// another engine) finds nothing and changes nothing.
  Future<UndoResult> undo(String batchId) async {
    if (batchId.isEmpty) _invalid();
    final now = _nowMs();
    return _txns.inTransaction(() async {
      final batch = await _undo.byId(batchId);
      if (batch == null) {
        throw BulkEditException(BulkEditException.undoNotFound);
      }
      if (batch.createdAt <= now - undoWindow.inMilliseconds) {
        throw BulkEditException(BulkEditException.undoExpired);
      }
      final image = _parse(batch.beforeJson);
      var restored = 0;
      var skipped = 0;
      for (final r in image.rows) {
        final ok = switch (image.kind) {
          'category' => await _undoCategory(r, image),
          'account' => await _undoAccount(r, image),
          _ => await _undoDelete(r, image),
        };
        ok ? restored++ : skipped++;
      }
      for (final id in image.rulesCreated) {
        final rule = await _rules.byId(id);
        if (rule == null) continue;
        if (rule.categoryId == image.to) {
          await _rules.deleteById(id);
        } else {
          skipped++;
        }
      }
      for (final p in image.rulesRepointed) {
        final rule = await _rules.byId(p.id);
        if (rule == null) continue;
        if (rule.categoryId == image.to) {
          await _rules.setCategory(p.id, p.from);
        } else {
          skipped++;
        }
      }
      // Exactly one winner: the batch row is consumed here, inside the
      // transaction. Zero rows means someone else got there first.
      if (await _undo.deleteById(batchId) != 1) {
        throw BulkEditException(BulkEditException.undoNotFound);
      }
      return UndoResult(restored: restored, skipped: skipped);
    });
  }

  /// Deletes expired batches. Returns how many were removed.
  Future<int> purgeExpired() =>
      _undo.purgeOlderThan(_nowMs() - undoWindow.inMilliseconds + 1);

  Future<void> _write(String id, TransactionsCompanion patch) async {
    if (await _txns.updateById(id, patch) != 1) {
      throw BulkEditException(BulkEditException.notFound);
    }
  }

  // Each restore is conditional on the row still being exactly as the batch
  // left it (stamp and changed field), so a later edit is never overwritten.

  /// Writes [patch] to [id] only while it still carries the batch's stamp
  /// and the one changed field the batch set. Returns the rows changed.
  Future<int> _restoreIf(
    String id, {
    required int expectUpdatedAt,
    required TransactionsCompanion patch,
    String? expectCategoryId,
    String? expectAccountId,
    int? expectDeletedAt,
  }) => guardWrite(
    () =>
        (_db.update(_db.transactions)..where(
              (t) => Expression.and([
                t.id.equals(id),
                t.updatedAt.equals(expectUpdatedAt),
                if (expectCategoryId != null)
                  t.categoryId.equals(expectCategoryId),
                if (expectAccountId != null)
                  t.accountId.equals(expectAccountId),
                if (expectDeletedAt != null)
                  t.deletedAt.equals(expectDeletedAt),
              ]),
            ))
            .write(patch),
  );

  Future<bool> _undoCategory(_ImageRow r, _Image image) async {
    final n = await _restoreIf(
      r.id,
      expectUpdatedAt: image.at,
      expectCategoryId: image.to,
      patch: TransactionsCompanion(
        categoryId: Value(r.cat),
        categorySource: Value(r.src!),
        isUserVerified: Value(r.ver!),
        updatedAt: Value(r.upd),
      ),
    );
    return n == 1;
  }

  Future<bool> _undoAccount(_ImageRow r, _Image image) async {
    final n = await _restoreIf(
      r.id,
      expectUpdatedAt: image.at,
      expectAccountId: image.to,
      patch: TransactionsCompanion(
        accountId: Value(r.acc!),
        updatedAt: Value(r.upd),
      ),
    );
    return n == 1;
  }

  Future<bool> _undoDelete(_ImageRow r, _Image image) async {
    final n = await _restoreIf(
      r.id,
      expectUpdatedAt: image.at,
      expectDeletedAt: image.at,
      patch: TransactionsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(r.upd),
      ),
    );
    return n == 1;
  }

  /// Saves one rule per distinct merchant key; records created rules and
  /// re-pointed ones (with their old category) in [image]. Returns how many
  /// rules changed.
  Future<int> _saveRules(
    List<TransactionRow> rows,
    String categoryId,
    int now,
    Map<String, Object?> image,
  ) async {
    final keys = <(String, String)>{};
    for (final r in rows) {
      final catalog = r.catalogMerchantId;
      final norm = r.merchantNorm;
      if (catalog != null && catalog >= 1) {
        keys.add((RuleMatchKind.catalogMerchant, '$catalog'));
      } else if (norm != null && isCanonicalMerchantKey(norm)) {
        keys.add((RuleMatchKind.merchantNorm, norm));
      }
    }
    final created = image['rules_created']! as List<Object?>;
    final repointed = image['rules_repointed']! as List<Object?>;
    var changed = 0;
    for (final (kind, value) in keys) {
      final existing = await _rules.find(kind, value);
      if (existing == null) {
        final id = _newId();
        await _rules.upsert(
          MerchantRulesCompanion.insert(
            id: id,
            matchKind: kind,
            matchValue: value,
            categoryId: categoryId,
            createdAt: now,
          ),
        );
        created.add(id);
        changed++;
      } else if (existing.categoryId != categoryId) {
        repointed.add({'id': existing.id, 'from': existing.categoryId});
        await _rules.setCategory(existing.id, categoryId);
        changed++;
      }
    }
    return changed;
  }

  _Image _parse(String json) {
    try {
      final m = jsonDecode(json) as Map<String, Object?>;
      final kind = m['kind']! as String;
      if (m['v'] != 1 || !{'category', 'account', 'delete'}.contains(kind)) {
        throw const FormatException();
      }
      return _Image(
        kind: kind,
        at: m['at']! as int,
        to: m['to'] as String?,
        rows: [
          for (final r
              in (m['rows']! as List<Object?>).cast<Map<String, Object?>>())
            _ImageRow(
              id: r['id'] as String,
              upd: r['upd'] as int,
              cat: r['cat'] as String?,
              src: r['src'] as String?,
              ver: r['ver'] as int?,
              acc: r['acc'] as String?,
            ),
        ],
        rulesCreated: [
          for (final id in (m['rules_created']! as List<Object?>))
            id! as String,
        ],
        rulesRepointed: [
          for (final p
              in (m['rules_repointed']! as List<Object?>)
                  .cast<Map<String, Object?>>())
            (id: p['id'] as String, from: p['from'] as String),
        ],
      );
    } on Object {
      // Unreadable before-image: keep the batch, change nothing.
      throw BulkEditException(BulkEditException.undoCorrupt);
    }
  }

  static Never _invalid() => throw BulkEditException(BulkEditException.invalid);
}

final class _Image {
  _Image({
    required this.kind,
    required this.at,
    required this.to,
    required this.rows,
    required this.rulesCreated,
    required this.rulesRepointed,
  }) {
    // A category/account batch without its target, or a row missing the
    // fields its kind needs, is corrupt, not "restore to null".
    final needsTo = kind != 'delete';
    final bad =
        (needsTo && to == null) ||
        rows.any(
          (r) =>
              (kind == 'category' && (r.src == null || r.ver == null)) ||
              (kind == 'account' && r.acc == null),
        );
    if (bad) throw const FormatException();
  }

  final String kind;
  final int at;
  final String? to;
  final List<_ImageRow> rows;
  final List<String> rulesCreated;
  final List<({String id, String from})> rulesRepointed;
}

final class _ImageRow {
  _ImageRow({
    required this.id,
    required this.upd,
    this.cat,
    this.src,
    this.ver,
    this.acc,
  });
  final String id;
  final int upd;
  final String? cat;
  final String? src;
  final int? ver;
  final String? acc;
}
