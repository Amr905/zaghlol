// FU-254 (CAT-INSTAPAY / CAT-CASH): rows saved before the Cash and InstaPay
// categories existed keep their old category, and no raw event is stored on
// the row. This one-time pass re-derives the event from what the row does
// keep: the template id (the registry knows its event) and an InstaPay
// address counterparty on a transfer.
//
// Never touches a user's work: only `none` / `catalog` / `heuristic` (and,
// T-357, `ai`: the event outranks the AI tier) rows that are not
// user-verified (the same set the ingest event hint replaces);
// `user` and `user_rule` rows are skipped, and every guard is re-checked in
// the UPDATE itself. Bounded chunks, one DB transaction each, behind the
// restore pause gate. Done is marked in `db_meta`; a gate refusal or a
// missing category leaves it unmarked, so the next start retries. Nothing
// here logs or carries message text.

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart'
    show kCashCategoryId, kInstapayCategoryId;
import 'package:zaghlol_parsing/zaghlol_parsing.dart' show Registry;

import '../../../core/db/app_database.dart';
import '../../../ingestion/ingestion_pause_gate.dart';
import '../../ingestion/domain/ingest_rules.dart' show eventCategoryOf;

/// `db_meta` key set when the pass has run to completion.
const String eventCategoryBackfillKey = 'event_category_backfill_v1';

/// Rows read per DB transaction.
const int eventBackfillChunk = 200;

/// Template id -> the category its event implies (Cash / InstaPay only).
Map<String, String> eventCategoryByTemplate(Registry registry) => {
  for (final i in registry.institutions)
    for (final t in i.templates) t.id: ?eventCategoryOf(t.event),
};

/// Runs the pass once. Returns rows changed, or null when it did not run to
/// completion (already done, gate closed, a category missing).
Future<int?> backfillEventCategories(
  AppDatabase db,
  Registry registry, {
  required int at,
  IngestionPauseGate? gate,
}) async {
  final done = await (db.select(
    db.dbMeta,
  )..where((t) => t.key.equals(eventCategoryBackfillKey))).getSingleOrNull();
  if (done != null) return null;
  final live = await db
      .customSelect(
        'SELECT count(*) AS n FROM categories WHERE is_archived = 0 '
        'AND id IN (?1, ?2)',
        variables: [
          Variable.withString(kCashCategoryId),
          Variable.withString(kInstapayCategoryId),
        ],
        readsFrom: {db.categories},
      )
      .getSingle();
  if (live.read<int>('n') != 2) return null;

  final byTemplate = eventCategoryByTemplate(registry);
  var cursor = '';
  var changed = 0;
  try {
    while (true) {
      final rows = await db
          .customSelect(
            'SELECT id, template_id, direction, counterparty_kind, '
            'category_id FROM transactions '
            'WHERE id > ?1 AND deleted_at IS NULL AND is_internal = 0 '
            'AND is_user_verified = 0 '
            "AND category_source IN ('none','catalog','heuristic','ai') "
            "AND (template_id IS NOT NULL OR counterparty_kind = 'ipa') "
            'ORDER BY id LIMIT $eventBackfillChunk',
            variables: [Variable.withString(cursor)],
            readsFrom: {db.transactions},
          )
          .get();
      if (rows.isEmpty) break;
      Future<void> write() => db.transaction(() async {
        for (final r in rows) {
          final target = _targetOf(
            byTemplate[r.read<String?>('template_id')],
            direction: r.read<String>('direction'),
            counterpartyKind: r.read<String?>('counterparty_kind'),
          );
          if (target == null || target == r.read<String?>('category_id')) {
            continue;
          }
          changed += await db.customUpdate(
            'UPDATE transactions SET category_id = ?1, '
            "category_source = 'heuristic', updated_at = ?2 "
            'WHERE id = ?3 AND deleted_at IS NULL AND is_internal = 0 '
            'AND is_user_verified = 0 '
            "AND category_source IN ('none','catalog','heuristic','ai') "
            'AND category_id IS NOT ?1 '
            'AND EXISTS (SELECT 1 FROM categories c WHERE c.id = ?1 '
            'AND c.is_archived = 0)',
            variables: [
              Variable.withString(target),
              Variable.withInt(at),
              Variable.withString(r.read<String>('id')),
            ],
            updates: {db.transactions},
          );
        }
      });
      await (gate == null ? write() : gate.guard(write));
      cursor = rows.last.read<String>('id');
    }
  } on Object {
    return null;
  }
  Future<void> mark() => db
      .into(db.dbMeta)
      .insert(
        DbMetaCompanion.insert(key: eventCategoryBackfillKey, value: '1'),
        mode: InsertMode.insertOrReplace,
      );
  try {
    await (gate == null ? mark() : gate.guard(mark));
  } on Object {
    return null; // gate closed: the marker stays unset, a rerun is idempotent
  }
  return changed;
}

String? _targetOf(
  String? templateCategory, {
  required String direction,
  required String? counterpartyKind,
}) {
  if (templateCategory != null) return templateCategory;
  if (counterpartyKind == 'ipa' &&
      (direction == 'transfer_out' || direction == 'transfer_in')) {
    return kInstapayCategoryId;
  }
  return null;
}
