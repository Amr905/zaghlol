// T-075: re-categorizing EXISTING transactions (catalog update FR-SYNC-05,
// re-parse, backfill, T-077) without ever overwriting a user's work.
//
// Rules (parsing-engine §5 "Categorizer design", design note "Never
// overwrite"):
//  * One conditional UPDATE per row. Every guard is re-checked in SQL, so a
//    user edit committed by another connection between the read and the
//    write wins: `deleted_at IS NULL`, not internal, not user-verified, a
//    pipeline source only, and the old category and catalog merchant must
//    still be what this run read.
//  * `user` and `user_rule` rows are never touched.
//  * No downgrade: a `none` decision changes nothing (doubt means no
//    change); a heuristic never replaces a catalog category.
//  * A target category that is archived or missing is skipped (the EXISTS
//    in the same statement).
//  * A decision without a catalog merchant keeps the row's merchant.
//  * T-357 (LLM-CATEGORISE): an `ai` decision only fills a "needs
//    classification" row (`none`, no category); a rule, catalog or keyword
//    decision replaces an `ai` category (FU-408), and a catalog one drops
//    the merchant's unconfirmed suggestion.
// Failures are code-only; nothing here logs or carries merchant text.

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart'
    show kCashCategoryId, kInstapayCategoryId;
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/ai_merchant_suggestions_dao.dart';
import '../../../core/db/daos/write_errors.dart';
import 'categorizer_ports.dart';

/// Rows read and decided per transaction (one DB transaction per chunk).
const int recategorizeChunk = 200;

/// Result of [Recategorizer.run].
final class RecategorizeReport {
  const RecategorizeReport({required this.scanned, required this.changed});

  final int scanned;
  final int changed;
}

class Recategorizer {
  Recategorizer(this._db);

  final AppDatabase _db;

  /// Sources a decision of [source] may replace. A result never replaces a
  /// better one: heuristic over none/heuristic only.
  static List<String> replaceable(CategorySource source) => switch (source) {
    CategorySource.userRule ||
    CategorySource.catalog => const ['none', 'catalog', 'heuristic', 'ai'],
    CategorySource.heuristic => const ['none', 'heuristic', 'ai'],
    // Only "needs classification" (with the old category null, below).
    CategorySource.ai => const ['none'],
    CategorySource.none => const [],
  };

  /// The sources [run] scans (every pipeline source).
  static const String _pipelineSources = "('none','catalog','heuristic','ai')";

  /// The statement, exposed so a test can assert every guard is in the one
  /// statement (FU-095). `?` order: category, source, merchant, at, id,
  /// old category, old merchant, then one per replaceable source. All are
  /// numbered, so no bare `?` can shift them.
  static String sqlFor(int sources) =>
      'UPDATE transactions SET category_id = ?1, category_source = ?2, '
      'catalog_merchant_id = COALESCE(?3, catalog_merchant_id), '
      'updated_at = ?4 '
      'WHERE id = ?5 '
      'AND deleted_at IS NULL AND is_internal = 0 AND is_user_verified = 0 '
      'AND category_source IN (${[for (var i = 0; i < sources; i++) "?${8 + i}"].join(",")}) '
      'AND category_id IS ?6 AND catalog_merchant_id IS ?7 '
      'AND EXISTS (SELECT 1 FROM categories c WHERE c.id = ?1 '
      'AND c.is_archived = 0) '
      'AND (category_id IS NOT ?1 OR category_source <> ?2 '
      'OR catalog_merchant_id IS NOT COALESCE(?3, catalog_merchant_id))';

  /// Applies [decision] to transaction [id], which this run read with
  /// [oldCategoryId] and [oldCatalogMerchantId]. Returns rows changed (0 or
  /// 1). 0 when the decision is `none`, nothing would change, or any guard
  /// fails (a concurrent edit won).
  Future<int> apply({
    required String id,
    required String? oldCategoryId,
    required int? oldCatalogMerchantId,
    required CategoryDecision decision,
    required int at,
  }) async {
    final target = decision.categoryId;
    final from = replaceable(decision.source);
    if (target == null || from.isEmpty) return 0;
    // The AI never replaces a category, whatever its source.
    if (decision.source == CategorySource.ai && oldCategoryId != null) {
      return 0;
    }
    // CAT-cash / CAT-INSTAPAY: a catalog or keyword hit never replaces the
    // event category; only a user rule does.
    if (decision.source != CategorySource.userRule &&
        (oldCategoryId == kCashCategoryId ||
            oldCategoryId == kInstapayCategoryId)) {
      return 0;
    }
    return guardWrite(
      () => _db.customUpdate(
        sqlFor(from.length),
        variables: [
          Variable.withString(target),
          Variable.withString(decision.source.code),
          Variable<int>(decision.catalogMerchantId),
          Variable.withInt(at),
          Variable.withString(id),
          Variable<String>(oldCategoryId),
          Variable<int>(oldCatalogMerchantId),
          for (final s in from) Variable.withString(s),
        ],
        updates: {_db.transactions},
      ),
    );
  }

  /// Re-categorizes every eligible transaction with [categorizer], one
  /// distinct input once (the categorizer should be created with
  /// `memoize: true`), in id order, [recategorizeChunk] rows per DB
  /// transaction. Safe to re-run; safe next to a user editing.
  Future<RecategorizeReport> run(
    Categorizer categorizer, {
    required int at,
  }) async {
    var cursor = '';
    var scanned = 0;
    var changed = 0;
    while (true) {
      final rows = await _db
          .customSelect(
            'SELECT id, merchant_raw, merchant_norm, counterparty_kind, '
            'counterparty_value, category_id, category_source, '
            'catalog_merchant_id '
            'FROM transactions '
            'WHERE id > ?1 AND deleted_at IS NULL AND is_internal = 0 '
            'AND is_user_verified = 0 '
            'AND category_source IN $_pipelineSources '
            'ORDER BY id LIMIT $recategorizeChunk',
            variables: [Variable.withString(cursor)],
            readsFrom: {_db.transactions},
          )
          .get();
      if (rows.isEmpty) break;
      changed += await _decideAndApply(rows, categorizer, at: at);
      scanned += rows.length;
      cursor = rows.last.read<String>('id');
    }
    return RecategorizeReport(scanned: scanned, changed: changed);
  }

  /// T-357: applies [merchantNorm]'s new AI suggestion. Reads only that
  /// merchant's "needs classification" rows (live, not internal, not
  /// user-verified, `none` with no category) and runs the full
  /// [categorizer] on each, so a row of the same key that is a transfer,
  /// own-account or event row still gets what the chain says (usually
  /// nothing). Every other row of the merchant is never read, let alone
  /// written. Idempotent: a second call changes nothing.
  Future<RecategorizeReport> applySuggestion(
    String merchantNorm,
    Categorizer categorizer, {
    required int at,
  }) async {
    var cursor = '';
    var scanned = 0;
    var changed = 0;
    while (true) {
      final rows = await guardRead(
        () => _db
            .customSelect(
              'SELECT id, merchant_raw, merchant_norm, counterparty_kind, '
              'counterparty_value, category_id, category_source, '
              'catalog_merchant_id '
              'FROM transactions '
              'WHERE merchant_norm = ?1 AND id > ?2 '
              'AND $needsClassificationSql '
              'ORDER BY id LIMIT $recategorizeChunk',
              variables: [
                Variable.withString(merchantNorm),
                Variable.withString(cursor),
              ],
              readsFrom: {_db.transactions},
            )
            .get(),
      );
      if (rows.isEmpty) break;
      changed += await _decideAndApply(rows, categorizer, at: at);
      scanned += rows.length;
      cursor = rows.last.read<String>('id');
    }
    return RecategorizeReport(scanned: scanned, changed: changed);
  }

  Future<int> _decideAndApply(
    List<QueryRow> rows,
    Categorizer categorizer, {
    required int at,
  }) async {
    final work =
        <
          ({
            String id,
            String? norm,
            String? cat,
            String source,
            int? merchant,
            CategoryDecision d,
          })
        >[];
    for (final r in rows) {
      final d = await categorizer.categorize(
        categorizeInputFor(
          merchantRaw: r.read<String?>('merchant_raw'),
          merchantNorm: r.read<String?>('merchant_norm'),
          counterpartyKind: r.read<String?>('counterparty_kind'),
          counterpartyValue: r.read<String?>('counterparty_value'),
        ),
      );
      work.add((
        id: r.read<String>('id'),
        norm: r.read<String?>('merchant_norm'),
        cat: r.read<String?>('category_id'),
        source: r.read<String>('category_source'),
        merchant: r.read<int?>('catalog_merchant_id'),
        d: d,
      ));
    }
    var changed = 0;
    await _db.transaction(() async {
      final replacedAi = <String>{};
      for (final w in work) {
        final n = await apply(
          id: w.id,
          oldCategoryId: w.cat,
          oldCatalogMerchantId: w.merchant,
          decision: w.d,
          at: at,
        );
        changed += n;
        if (n > 0 &&
            w.source == CategorySource.ai.code &&
            w.d.source == CategorySource.catalog &&
            w.norm != null) {
          replacedAi.add(w.norm!);
        }
      }
      // A later catalog hit replaces an unconfirmed suggestion (FR-LCAT-20);
      // a confirmed or corrected one is the user's and stays.
      final dao = AiMerchantSuggestionsDao(_db);
      for (final m in replacedAi) {
        await dao.deleteUnconfirmed(m);
      }
    });
    return changed;
  }
}

/// T-357: the "needs classification" state, the only one an AI suggestion
/// ever fills: a live, not internal, not user-verified row with no
/// category from no source.
const String needsClassificationSql =
    'deleted_at IS NULL AND is_internal = 0 AND is_user_verified = 0 '
    "AND category_source = 'none' AND category_id IS NULL";
