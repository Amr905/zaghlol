// T-018: the v2 → v3 step (design note §1, §6), frozen. In order:
// 1. drop the two offset-link triggers that v3 changes (T-017 review m-1);
// 2. the exact CREATE statements of drift_schemas/app_database/
//    drift_schema_v3.json for every object that is new in v3 or whose SQL
//    differs from v2, in the dump's order, without `IF NOT EXISTS` (a stray
//    object of the same name fails the step and the opener restores the
//    pre-migration copy);
// 3. the FTS5 options of v3 (T-017 review S-2), which are data in the FTS
//    config tables, not schema, so no dump holds them.
//
// Never edit: a later schema change is a new version with its own step.
// Tests check lists 1–2 against the committed v2 and v3 dumps, and list 3
// against [ftsOptionStatements] at the time v3 shipped.

// ignore_for_file: lines_longer_than_80_chars, prefer_single_quotes

/// v2 triggers whose SQL changes in v3: dropped, then re-created by
/// [v3AddedObjects]. No `IF EXISTS`: a v2 file without them is not a v2
/// file, and the step fails.
const List<String> v3DroppedTriggers = [
  'trg_offset_links_bi',
  'trg_offset_links_bu',
];

/// The names and statements of the objects v3 adds or re-creates, in
/// creation order.
const List<(String, String)> v3AddedObjects = [
  (
    'catalog_merchants',
    r"""CREATE TABLE "catalog_merchants" ("id" INTEGER NOT NULL PRIMARY KEY CHECK (id >= 1), "canonical" TEXT NOT NULL CHECK (length(canonical) BETWEEN 1 AND 200), "name_ar" TEXT, "name_en" TEXT, "category_code" TEXT NOT NULL CHECK (length(category_code) BETWEEN 2 AND 32 AND category_code GLOB '[a-z]*' AND category_code NOT GLOB '*[^a-z0-9_]*'), "logo_key" TEXT, "version" INTEGER NOT NULL CHECK (version >= 0));""",
  ),
  (
    'catalog_aliases',
    r"""CREATE TABLE "catalog_aliases" ("id" INTEGER NOT NULL PRIMARY KEY, "merchant_id" INTEGER NOT NULL REFERENCES catalog_merchants(id)ON DELETE CASCADE, "alias_norm" TEXT NOT NULL CHECK (length(alias_norm) BETWEEN 1 AND 64 AND alias_norm NOT GLOB '*[^a-z0-9 ]*' AND alias_norm NOT GLOB ' *' AND alias_norm NOT GLOB '* ' AND alias_norm NOT GLOB '*  *'), "match" TEXT NOT NULL CHECK ("match" IN ('exact', 'prefix', 'token')), UNIQUE(alias_norm, merchant_id));""",
  ),
  (
    'ix_alias_merchant',
    r"""CREATE INDEX ix_alias_merchant ON catalog_aliases (merchant_id)""",
  ),
  (
    'catalog_alias_fts',
    r"""CREATE VIRTUAL TABLE "catalog_alias_fts" USING fts5(alias_norm, content='catalog_aliases', content_rowid='id', tokenize='trigram');""",
  ),
  (
    'trg_alias_fts_ai',
    r"""CREATE TRIGGER trg_alias_fts_ai AFTER INSERT ON catalog_aliases BEGIN INSERT INTO catalog_alias_fts ("rowid", alias_norm) VALUES (new.id, new.alias_norm);END""",
  ),
  (
    'trg_alias_fts_ad',
    r"""CREATE TRIGGER trg_alias_fts_ad AFTER DELETE ON catalog_aliases BEGIN INSERT INTO catalog_alias_fts (catalog_alias_fts, "rowid", alias_norm) VALUES ('delete', old.id, old.alias_norm);END""",
  ),
  (
    'trg_alias_fts_au',
    r"""CREATE TRIGGER trg_alias_fts_au AFTER UPDATE OF id, alias_norm ON catalog_aliases BEGIN INSERT INTO catalog_alias_fts (catalog_alias_fts, "rowid", alias_norm) VALUES ('delete', old.id, old.alias_norm);INSERT INTO catalog_alias_fts ("rowid", alias_norm) VALUES (new.id, new.alias_norm);END""",
  ),
  (
    'catalog_keywords',
    r"""CREATE TABLE "catalog_keywords" ("keyword_norm" TEXT NOT NULL CHECK (length(keyword_norm) BETWEEN 1 AND 64 AND keyword_norm NOT GLOB('*[' || char(1) || '-' || char(31) || char(127) || '-' || char(159) || ']*')AND keyword_norm NOT GLOB ' *' AND keyword_norm NOT GLOB '* ' AND keyword_norm NOT GLOB '*  *'), "lang" TEXT NOT NULL CHECK (lang GLOB '[a-z][a-z]'), "category_code" TEXT NOT NULL CHECK (length(category_code) BETWEEN 2 AND 32 AND category_code GLOB '[a-z]*' AND category_code NOT GLOB '*[^a-z0-9_]*'), "weight" INTEGER NOT NULL CHECK (typeof(weight) = 'integer' AND weight BETWEEN 0 AND 100), PRIMARY KEY(keyword_norm, lang));""",
  ),
  (
    'catalog_meta',
    r"""CREATE TABLE "catalog_meta" ("id" INTEGER NOT NULL PRIMARY KEY CHECK (id = 1), "version" INTEGER NOT NULL CHECK (version >= 0), "applied_at" INTEGER NOT NULL, "signature_kid" TEXT NOT NULL CHECK (length(signature_kid) BETWEEN 1 AND 128));""",
  ),
  (
    'merchant_rules',
    r"""CREATE TABLE "merchant_rules" ("id" TEXT NOT NULL PRIMARY KEY, "match_kind" TEXT NOT NULL CHECK (match_kind IN ('catalog_merchant', 'merchant_norm', 'counterparty')), "match_value" TEXT NOT NULL, "category_id" TEXT NOT NULL REFERENCES categories(id), "created_at" INTEGER NOT NULL, "last_applied_at" INTEGER, UNIQUE(match_kind, match_value), CHECK(match_kind <> 'merchant_norm' OR(length(match_value) BETWEEN 1 AND 64 AND match_value NOT GLOB '*[^a-z0-9 ]*' AND match_value NOT GLOB ' *' AND match_value NOT GLOB '* ' AND match_value NOT GLOB '*  *')), CHECK(match_kind <> 'catalog_merchant' OR(length(match_value) BETWEEN 1 AND 10 AND match_value GLOB '[1-9]*' AND match_value NOT GLOB '*[^0-9]*')), CHECK(match_kind <> 'counterparty' OR(length(match_value) BETWEEN 1 AND 128 AND match_value NOT GLOB('*[' || char(1) || '-' || char(31) || char(127) || '-' || char(159) || ']*'))));""",
  ),
  (
    'ix_rules_category',
    r"""CREATE INDEX ix_rules_category ON merchant_rules (category_id)""",
  ),
  (
    'budgets',
    r"""CREATE TABLE "budgets" ("id" TEXT NOT NULL PRIMARY KEY, "category_id" TEXT REFERENCES categories(id), "currency" TEXT NOT NULL CHECK (currency GLOB '[A-Z][A-Z][A-Z]'), "limit_minor" INTEGER NOT NULL CHECK (typeof(limit_minor) = 'integer' AND limit_minor BETWEEN 0 AND 9007199254740991), "period" TEXT NOT NULL CHECK (period IN ('cycle', 'annual')), "rollover" INTEGER NOT NULL DEFAULT 0 CHECK (rollover IN (0, 1)), "thresholds" TEXT NOT NULL DEFAULT '[80,100]' CHECK (CASE WHEN json_valid(thresholds) THEN json_type(thresholds) = 'array' ELSE 0 END), "created_at" INTEGER NOT NULL, UNIQUE(category_id, currency, period));""",
  ),
  (
    'ux_budgets_overall',
    r"""CREATE UNIQUE INDEX ux_budgets_overall ON budgets (currency, period) WHERE category_id IS NULL""",
  ),
  (
    'fired_alerts',
    r"""CREATE TABLE "fired_alerts" ("kind" TEXT NOT NULL CHECK (length(kind) BETWEEN 1 AND 64 AND kind NOT GLOB '*[^a-z0-9_]*'), "subject_id" TEXT NOT NULL CHECK (length(subject_id) BETWEEN 1 AND 128), "period_key" TEXT NOT NULL CHECK (length(period_key) BETWEEN 1 AND 64), "threshold" INTEGER NOT NULL DEFAULT 0 CHECK (typeof(threshold) = 'integer' AND threshold >= 0), "fired_at" INTEGER NOT NULL, PRIMARY KEY(kind, subject_id, period_key, threshold));""",
  ),
  (
    'cycle_summaries',
    r"""CREATE TABLE "cycle_summaries" ("cycle_start" TEXT NOT NULL CHECK (date(cycle_start) IS cycle_start), "currency" TEXT NOT NULL CHECK (currency GLOB '[A-Z][A-Z][A-Z]'), "account_filter" TEXT NOT NULL DEFAULT '*' CHECK (length(account_filter) BETWEEN 1 AND 1024), "income_minor" INTEGER NOT NULL CHECK (typeof(income_minor) = 'integer' AND income_minor BETWEEN -9007199254740991 AND 9007199254740991), "spend_minor" INTEGER NOT NULL CHECK (typeof(spend_minor) = 'integer' AND spend_minor BETWEEN -9007199254740991 AND 9007199254740991), "by_category" TEXT NOT NULL CHECK (CASE WHEN json_valid(by_category) THEN json_type(by_category) = 'object' ELSE 0 END), "computed_at" INTEGER NOT NULL, PRIMARY KEY(cycle_start, currency, account_filter));""",
  ),
  (
    'recurring_items',
    r"""CREATE TABLE "recurring_items" ("id" TEXT NOT NULL PRIMARY KEY, "kind" TEXT NOT NULL CHECK (kind IN ('subscription', 'installment', 'card_due', 'gameya', 'bill')), "status" TEXT NOT NULL CHECK (status IN ('suggested', 'active', 'dismissed', 'completed')), "name" TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 60), "merchant_norm" TEXT CHECK (merchant_norm IS NULL OR(length(merchant_norm) BETWEEN 1 AND 64 AND merchant_norm NOT GLOB '*[^a-z0-9 ]*' AND merchant_norm NOT GLOB ' *' AND merchant_norm NOT GLOB '* ' AND merchant_norm NOT GLOB '*  *')), "account_id" TEXT REFERENCES accounts(id), "amount_minor" INTEGER NOT NULL CHECK (typeof(amount_minor) = 'integer' AND amount_minor BETWEEN 0 AND 9007199254740991), "currency" TEXT NOT NULL CHECK (currency GLOB '[A-Z][A-Z][A-Z]'), "cadence" TEXT NOT NULL CHECK (cadence IN ('monthly', 'yearly', 'weekly', 'custom_days')), "cadence_days" INTEGER CHECK (cadence_days IS NULL OR cadence_days BETWEEN 1 AND 3660), "due_day" INTEGER CHECK (due_day IS NULL OR due_day BETWEEN 1 AND 31), "next_due_date" TEXT CHECK (next_due_date IS NULL OR date(next_due_date) IS next_due_date), "total_count" INTEGER CHECK (total_count IS NULL OR total_count >= 1), "paid_count" INTEGER NOT NULL DEFAULT 0 CHECK (paid_count >= 0 AND(total_count IS NULL OR paid_count <= total_count)), "reminder_days" INTEGER NOT NULL DEFAULT 3 CHECK (reminder_days BETWEEN 0 AND 60), "created_at" INTEGER NOT NULL, CHECK((cadence = 'custom_days')=(cadence_days IS NOT NULL)));""",
  ),
  (
    'ix_recurring_due',
    r"""CREATE INDEX ix_recurring_due ON recurring_items (next_due_date) WHERE status = 'active'""",
  ),
  (
    'ix_recurring_account',
    r"""CREATE INDEX ix_recurring_account ON recurring_items (account_id) WHERE account_id IS NOT NULL""",
  ),
  (
    'recurring_occurrences',
    r"""CREATE TABLE "recurring_occurrences" ("item_id" TEXT NOT NULL REFERENCES recurring_items(id)ON DELETE CASCADE, "due_date" TEXT NOT NULL CHECK (date(due_date) IS due_date), "txn_id" TEXT REFERENCES transactions(id)ON DELETE SET NULL, "paid_at" INTEGER, PRIMARY KEY(item_id, due_date));""",
  ),
  (
    'ix_recurring_occ_txn',
    r"""CREATE INDEX ix_recurring_occ_txn ON recurring_occurrences (txn_id) WHERE txn_id IS NOT NULL""",
  ),
  (
    'ix_offset_participant',
    r"""CREATE INDEX ix_offset_participant ON offset_links (participant_id) WHERE participant_id IS NOT NULL""",
  ),
  (
    'trg_split_participant_move',
    r"""CREATE TRIGGER trg_split_participant_move BEFORE UPDATE OF expense_txn_id ON split_participants WHEN new.expense_txn_id IS NOT old.expense_txn_id BEGIN SELECT RAISE (ABORT, 'OFFSET_PARTICIPANT_MISMATCH') WHERE EXISTS (SELECT 1 FROM offset_links WHERE participant_id = old.id);END""",
  ),
  (
    'trg_offset_links_bi',
    r"""CREATE TRIGGER trg_offset_links_bi BEFORE INSERT ON offset_links BEGIN SELECT RAISE (ABORT, 'OFFSET_CURRENCY_MISMATCH') WHERE (SELECT currency FROM transactions WHERE id = new.expense_txn_id) IS NOT (SELECT currency FROM transactions WHERE id = new.source_txn_id) AND EXISTS (SELECT 1 FROM transactions WHERE id = new.expense_txn_id) AND EXISTS (SELECT 1 FROM transactions WHERE id = new.source_txn_id);SELECT RAISE (ABORT, 'OFFSET_PARTICIPANT_MISMATCH') WHERE new.participant_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM split_participants WHERE id = new.participant_id AND expense_txn_id = new.expense_txn_id);SELECT RAISE (ABORT, 'OFFSET_EXCEEDS_EXPENSE') WHERE new.amount_minor + (SELECT coalesce(sum(amount_minor), 0) FROM offset_links WHERE expense_txn_id = new.expense_txn_id) > (SELECT amount_minor FROM transactions WHERE id = new.expense_txn_id);SELECT RAISE (ABORT, 'OFFSET_EXCEEDS_SOURCE') WHERE new.amount_minor + (SELECT coalesce(sum(amount_minor), 0) FROM offset_links WHERE source_txn_id = new.source_txn_id) > (SELECT amount_minor FROM transactions WHERE id = new.source_txn_id);END""",
  ),
  (
    'trg_offset_links_bu',
    r"""CREATE TRIGGER trg_offset_links_bu BEFORE UPDATE ON offset_links BEGIN SELECT RAISE (ABORT, 'OFFSET_CURRENCY_MISMATCH') WHERE (SELECT currency FROM transactions WHERE id = new.expense_txn_id) IS NOT (SELECT currency FROM transactions WHERE id = new.source_txn_id) AND EXISTS (SELECT 1 FROM transactions WHERE id = new.expense_txn_id) AND EXISTS (SELECT 1 FROM transactions WHERE id = new.source_txn_id);SELECT RAISE (ABORT, 'OFFSET_PARTICIPANT_MISMATCH') WHERE new.participant_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM split_participants WHERE id = new.participant_id AND expense_txn_id = new.expense_txn_id);SELECT RAISE (ABORT, 'OFFSET_EXCEEDS_EXPENSE') WHERE new.amount_minor + (SELECT coalesce(sum(amount_minor), 0) FROM offset_links WHERE expense_txn_id = new.expense_txn_id AND id <> old.id) > (SELECT amount_minor FROM transactions WHERE id = new.expense_txn_id);SELECT RAISE (ABORT, 'OFFSET_EXCEEDS_SOURCE') WHERE new.amount_minor + (SELECT coalesce(sum(amount_minor), 0) FROM offset_links WHERE source_txn_id = new.source_txn_id AND id <> old.id) > (SELECT amount_minor FROM transactions WHERE id = new.source_txn_id);END""",
  ),
];

/// FTS5 `secure-delete` on both transaction search tables (T-017 review
/// S-2): deleted tokens leave the index segments at once instead of at the
/// next merge. Persistent (stored in each table's `_config`).
const List<String> v3FtsOptions = [
  "INSERT INTO transactions_fts (transactions_fts, rank) VALUES ('secure-delete', 1)",
  "INSERT INTO transactions_fts_short (transactions_fts_short, rank) VALUES ('secure-delete', 1)",
];
