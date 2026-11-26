// T-356: the v6 → v7 step, frozen (LLM-CATEGORISE, D-94). In order:
// 1. drop the view and the two `offset_links` triggers that read
//    `transactions` (modern `ALTER TABLE … RENAME` refuses to run while a
//    view or trigger names a missing table);
// 2. rebuild `transactions` (CHECK widened: category_source 'ai') and
//    `outbox` (CHECK widened: kinds 'llm_cat_confirmation',
//    'llm_cat_correction'): create "<t>__v7" with the v7 dump's DDL, copy
//    every v6 column and the rowid by name, compare the row counts, drop the
//    old table, rename, re-create its indexes. Foreign keys are off during
//    the step (the opener); children keep their FK text and the opener runs
//    `PRAGMA foreign_key_check` before commit;
// 3. re-create, unchanged, what step 1 and the drop of `transactions`
//    removed: the view and every trigger on or reading `transactions`;
// 4. create `ai_merchant_suggestions` and `llm_cat_queue`.
// A stored row can't break a wider CHECK, but a failure of any statement
// aborts the step and the opener restores the byte-identical v6 file.
//
// Never edit: a later schema change is a new version with its own step. A
// test checks every list against the committed v6 and v7 dumps.

// ignore_for_file: lines_longer_than_80_chars, prefer_single_quotes

/// One table rebuild of the v6 → v7 step.
final class V7Rebuild {
  const V7Rebuild({
    required this.table,
    required this.createTemp,
    required this.columns,
    required this.indexes,
  });

  final String table;

  /// The v7 DDL of [table], created as [temp].
  final String createTemp;

  /// The v6 columns, copied by name (with the rowid).
  final List<String> columns;

  /// `CREATE INDEX` statements of [table] in v7.
  final List<String> indexes;

  /// The name the new table has until the rename.
  String get temp => '${table}__v7';
}

/// Dropped by name before the rebuilds, as (`VIEW` or `TRIGGER`, name).
const List<(String, String)> v7DroppedDependents = [
  ('TRIGGER', 'trg_offset_links_bi'),
  ('TRIGGER', 'trg_offset_links_bu'),
  ('VIEW', 'transactions_fts_row'),
];

/// The rebuilds, in order.
const List<V7Rebuild> v7Rebuilds = [
  V7Rebuild(
    table: 'transactions',
    createTemp: r"""CREATE TABLE "transactions__v7" ("id" TEXT NOT NULL PRIMARY KEY, "account_id" TEXT NOT NULL REFERENCES accounts(id), "raw_message_id" TEXT REFERENCES raw_messages(id)ON DELETE SET NULL, "source" TEXT NOT NULL CHECK (source IN ('sms', 'notification', 'shortcut', 'apple_pay', 'ocr', 'pdf', 'csv', 'voice', 'manual', 'share')), "direction" TEXT NOT NULL CHECK (direction IN ('expense', 'income', 'transfer_out', 'transfer_in', 'refund', 'fee')), "status" TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted', 'pending', 'declined', 'reversed')), "amount_minor" INTEGER NOT NULL CHECK (typeof(amount_minor) = 'integer' AND amount_minor BETWEEN 0 AND 9007199254740991), "currency" TEXT NOT NULL CHECK (currency GLOB '[A-Z][A-Z][A-Z]'), "original_amount_minor" INTEGER CHECK (original_amount_minor IS NULL OR(typeof(original_amount_minor) = 'integer' AND original_amount_minor BETWEEN 0 AND 9007199254740991)), "original_currency" TEXT CHECK (original_currency IS NULL OR original_currency GLOB '[A-Z][A-Z][A-Z]'), "occurred_at" INTEGER NOT NULL, "occurred_tz_offset_min" INTEGER NOT NULL CHECK (occurred_tz_offset_min BETWEEN -1080 AND 1080), "merchant_raw" TEXT, "merchant_norm" TEXT, "catalog_merchant_id" INTEGER, "counterparty_kind" TEXT CHECK (counterparty_kind IN ('merchant', 'ipa', 'phone', 'person', 'bank', 'own_account')), "counterparty_value" TEXT, "category_id" TEXT REFERENCES categories(id), "category_source" TEXT NOT NULL CHECK (category_source IN ('user', 'user_rule', 'catalog', 'heuristic', 'none', 'ai')), "is_user_verified" INTEGER NOT NULL DEFAULT 0 CHECK (is_user_verified IN (0, 1)), "transfer_pair_id" TEXT REFERENCES transfer_pairs(id)ON DELETE SET NULL, "is_internal" INTEGER NOT NULL DEFAULT 0 CHECK (is_internal IN (0, 1)), "reference_no" TEXT, "balance_after_minor" INTEGER CHECK (balance_after_minor IS NULL OR(typeof(balance_after_minor) = 'integer' AND balance_after_minor BETWEEN -9007199254740991 AND 9007199254740991)), "template_id" TEXT, "parse_confidence" REAL CHECK (parse_confidence IS NULL OR parse_confidence BETWEEN 0 AND 1), "dedupe_key" TEXT, "note" TEXT, "deleted_at" INTEGER, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, CHECK((original_amount_minor IS NULL)=(original_currency IS NULL)));""",
    columns: [
      'id',
      'account_id',
      'raw_message_id',
      'source',
      'direction',
      'status',
      'amount_minor',
      'currency',
      'original_amount_minor',
      'original_currency',
      'occurred_at',
      'occurred_tz_offset_min',
      'merchant_raw',
      'merchant_norm',
      'catalog_merchant_id',
      'counterparty_kind',
      'counterparty_value',
      'category_id',
      'category_source',
      'is_user_verified',
      'transfer_pair_id',
      'is_internal',
      'reference_no',
      'balance_after_minor',
      'template_id',
      'parse_confidence',
      'dedupe_key',
      'note',
      'deleted_at',
      'created_at',
      'updated_at',
    ],
    indexes: [
      r"""CREATE INDEX ix_txn_account_time ON transactions (account_id, occurred_at) WHERE deleted_at IS NULL""",
      r"""CREATE INDEX ix_txn_category_time ON transactions (category_id, occurred_at) WHERE deleted_at IS NULL""",
      r"""CREATE INDEX ix_txn_currency_time ON transactions (currency, occurred_at, direction) WHERE deleted_at IS NULL""",
      r"""CREATE INDEX ix_txn_merchant ON transactions (merchant_norm, occurred_at)""",
      r"""CREATE INDEX ix_txn_dedupe ON transactions (dedupe_key, occurred_at)""",
      r"""CREATE INDEX ix_txn_category_source ON transactions (category_source) WHERE is_user_verified = 0""",
    ],
  ),
  V7Rebuild(
    table: 'outbox',
    createTemp: r"""CREATE TABLE "outbox__v7" ("id" TEXT NOT NULL PRIMARY KEY, "kind" TEXT NOT NULL CHECK (kind IN ('contribution', 'bank_request', 'purchase_verify', 'llm_cat_confirmation', 'llm_cat_correction')), "payload" TEXT NOT NULL CHECK (length(CAST(payload AS BLOB)) <= 65536 AND instr(CAST(payload AS BLOB), X'00') = 0 AND CASE WHEN json_valid(payload) THEN json_type(payload) = 'object' ELSE 0 END), "created_at" INTEGER NOT NULL CHECK (typeof(created_at) = 'integer'), "attempts" INTEGER NOT NULL DEFAULT 0 CHECK (typeof(attempts) = 'integer' AND attempts >= 0), "next_attempt_at" INTEGER CHECK (next_attempt_at IS NULL OR typeof(next_attempt_at) = 'integer'));""",
    columns: [
      'id',
      'kind',
      'payload',
      'created_at',
      'attempts',
      'next_attempt_at',
    ],
    indexes: [r"""CREATE INDEX ix_outbox_kind ON outbox (kind, created_at)"""],
  ),
];

/// Re-created after the rebuilds, unchanged from v6, in dump order: the
/// view and the triggers on or reading `transactions`.
const List<(String, String)> v7RestoredObjects = [
  (
    'trg_offset_links_bi',
    r"""CREATE TRIGGER trg_offset_links_bi BEFORE INSERT ON offset_links BEGIN SELECT RAISE (ABORT, 'OFFSET_CURRENCY_MISMATCH') WHERE (SELECT currency FROM transactions WHERE id = new.expense_txn_id) IS NOT (SELECT currency FROM transactions WHERE id = new.source_txn_id) AND EXISTS (SELECT 1 FROM transactions WHERE id = new.expense_txn_id) AND EXISTS (SELECT 1 FROM transactions WHERE id = new.source_txn_id);SELECT RAISE (ABORT, 'OFFSET_PARTICIPANT_MISMATCH') WHERE new.participant_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM split_participants WHERE id = new.participant_id AND expense_txn_id = new.expense_txn_id);SELECT RAISE (ABORT, 'OFFSET_EXCEEDS_EXPENSE') WHERE new.amount_minor + (SELECT coalesce(sum(amount_minor), 0) FROM offset_links WHERE expense_txn_id = new.expense_txn_id) > (SELECT amount_minor FROM transactions WHERE id = new.expense_txn_id);SELECT RAISE (ABORT, 'OFFSET_EXCEEDS_SOURCE') WHERE new.amount_minor + (SELECT coalesce(sum(amount_minor), 0) FROM offset_links WHERE source_txn_id = new.source_txn_id) > (SELECT amount_minor FROM transactions WHERE id = new.source_txn_id);END""",
  ),
  (
    'trg_offset_links_bu',
    r"""CREATE TRIGGER trg_offset_links_bu BEFORE UPDATE ON offset_links BEGIN SELECT RAISE (ABORT, 'OFFSET_CURRENCY_MISMATCH') WHERE (SELECT currency FROM transactions WHERE id = new.expense_txn_id) IS NOT (SELECT currency FROM transactions WHERE id = new.source_txn_id) AND EXISTS (SELECT 1 FROM transactions WHERE id = new.expense_txn_id) AND EXISTS (SELECT 1 FROM transactions WHERE id = new.source_txn_id);SELECT RAISE (ABORT, 'OFFSET_PARTICIPANT_MISMATCH') WHERE new.participant_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM split_participants WHERE id = new.participant_id AND expense_txn_id = new.expense_txn_id);SELECT RAISE (ABORT, 'OFFSET_EXCEEDS_EXPENSE') WHERE new.amount_minor + (SELECT coalesce(sum(amount_minor), 0) FROM offset_links WHERE expense_txn_id = new.expense_txn_id AND id <> old.id) > (SELECT amount_minor FROM transactions WHERE id = new.expense_txn_id);SELECT RAISE (ABORT, 'OFFSET_EXCEEDS_SOURCE') WHERE new.amount_minor + (SELECT coalesce(sum(amount_minor), 0) FROM offset_links WHERE source_txn_id = new.source_txn_id AND id <> old.id) > (SELECT amount_minor FROM transactions WHERE id = new.source_txn_id);END""",
  ),
  (
    'trg_txn_offset_bu',
    r"""CREATE TRIGGER trg_txn_offset_bu BEFORE UPDATE OF amount_minor, currency ON transactions BEGIN SELECT RAISE (ABORT, 'OFFSET_CURRENCY_MISMATCH') WHERE new.currency IS NOT old.currency AND EXISTS (SELECT 1 FROM offset_links WHERE expense_txn_id = old.id OR source_txn_id = old.id);SELECT RAISE (ABORT, 'OFFSET_EXCEEDS_EXPENSE') WHERE (SELECT coalesce(sum(amount_minor), 0) FROM offset_links WHERE expense_txn_id = old.id) > new.amount_minor;SELECT RAISE (ABORT, 'OFFSET_EXCEEDS_SOURCE') WHERE (SELECT coalesce(sum(amount_minor), 0) FROM offset_links WHERE source_txn_id = old.id) > new.amount_minor;END""",
  ),
  (
    'transactions_fts_row',
    r"""CREATE VIEW transactions_fts_row AS SELECT id AS txn_id, CASE WHEN merchant_norm IS NULL OR merchant_norm = merchant_raw THEN merchant_raw WHEN merchant_raw IS NULL THEN merchant_norm ELSE merchant_raw || ' ' || merchant_norm END AS merchant, counterparty_value AS counterparty, note, latin || ' ' || "replace"("replace"("replace"("replace"("replace"("replace"("replace"("replace"("replace"("replace"("replace"(latin, '0', '٠'), '1', '١'), '2', '٢'), '3', '٣'), '4', '٤'), '5', '٥'), '6', '٦'), '7', '٧'), '8', '٨'), '9', '٩'), '.', '٫') AS amount_text FROM (SELECT id, merchant_raw, merchant_norm, counterparty_value, note, CASE WHEN currency IN ('BIF', 'CLP', 'DJF', 'GNF', 'ISK', 'JPY', 'KMF', 'KRW', 'PYG', 'RWF', 'UGX', 'UYI', 'VND', 'VUV', 'XAF', 'XOF', 'XPF') THEN format('%d', amount_minor) WHEN currency IN ('BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND') THEN format('%d.%03d', amount_minor / 1000, amount_minor % 1000) WHEN currency IN ('CLF', 'UYW') THEN format('%d.%04d', amount_minor / 10000, amount_minor % 10000) ELSE format('%d.%02d', amount_minor / 100, amount_minor % 100) END AS latin FROM transactions)""",
  ),
  (
    'trg_txn_fts_ai',
    r"""CREATE TRIGGER trg_txn_fts_ai AFTER INSERT ON transactions BEGIN INSERT INTO transactions_fts_src (txn_id, merchant, counterparty, note, amount_text) SELECT txn_id, merchant, counterparty, note, amount_text FROM transactions_fts_row WHERE txn_id = new.id;END""",
  ),
  (
    'trg_txn_fts_au',
    r"""CREATE TRIGGER trg_txn_fts_au AFTER UPDATE OF id, merchant_raw, merchant_norm, counterparty_value, note, amount_minor, currency ON transactions BEGIN DELETE FROM transactions_fts_src WHERE txn_id = old.id;INSERT INTO transactions_fts_src (txn_id, merchant, counterparty, note, amount_text) SELECT txn_id, merchant, counterparty, note, amount_text FROM transactions_fts_row WHERE txn_id = new.id;END""",
  ),
  (
    'trg_txn_fts_ad',
    r"""CREATE TRIGGER trg_txn_fts_ad AFTER DELETE ON transactions BEGIN DELETE FROM transactions_fts_src WHERE txn_id = old.id;END""",
  ),
];

/// The names and statements of the objects v7 adds, in creation order.
const List<(String, String)> v7AddedObjects = [
  (
    'ai_merchant_suggestions',
    r"""CREATE TABLE "ai_merchant_suggestions" ("merchant_norm" TEXT NOT NULL PRIMARY KEY CHECK (length(merchant_norm) BETWEEN 2 AND 64 AND merchant_norm NOT GLOB '*[^a-z0-9 ]*' AND merchant_norm NOT GLOB ' *' AND merchant_norm NOT GLOB '* ' AND merchant_norm NOT GLOB '*  *' AND instr(CAST(merchant_norm AS BLOB), X'00') = 0), "category_id" TEXT REFERENCES categories(id), "confidence" INTEGER CHECK (confidence IS NULL OR(typeof(confidence) = 'integer' AND confidence BETWEEN 0 AND 100)), "source" TEXT CHECK (source IS NULL OR source IN ('llm', 'cache', 'catalog')), "state" TEXT NOT NULL CHECK (state IN ('unconfirmed', 'confirmed', 'corrected', 'no_answer')), "created_at" INTEGER NOT NULL CHECK (typeof(created_at) = 'integer'), "decided_at" INTEGER CHECK (decided_at IS NULL OR typeof(decided_at) = 'integer'), CHECK((state = 'no_answer')=(category_id IS NULL)), CHECK(state = 'no_answer' OR(confidence IS NOT NULL AND source IS NOT NULL)), CHECK((state IN ('confirmed', 'corrected'))=(decided_at IS NOT NULL)));""",
  ),
  (
    'llm_cat_queue',
    r"""CREATE TABLE "llm_cat_queue" ("merchant_norm" TEXT NOT NULL PRIMARY KEY CHECK (length(merchant_norm) BETWEEN 2 AND 64 AND merchant_norm NOT GLOB '*[^a-z0-9 ]*' AND merchant_norm NOT GLOB ' *' AND merchant_norm NOT GLOB '* ' AND merchant_norm NOT GLOB '*  *' AND instr(CAST(merchant_norm AS BLOB), X'00') = 0), "txn_count" INTEGER NOT NULL CHECK (typeof(txn_count) = 'integer' AND txn_count >= 1), "first_queued_at" INTEGER NOT NULL CHECK (typeof(first_queued_at) = 'integer'), "last_seen_at" INTEGER NOT NULL CHECK (typeof(last_seen_at) = 'integer'), "attempts" INTEGER NOT NULL DEFAULT 0 CHECK (typeof(attempts) = 'integer' AND attempts >= 0), "next_attempt_at" INTEGER CHECK (next_attempt_at IS NULL OR typeof(next_attempt_at) = 'integer'));""",
  ),
];
