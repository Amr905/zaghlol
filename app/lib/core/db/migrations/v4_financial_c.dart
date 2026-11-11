// T-019: the v3 → v4 step (design note §1, §6), frozen. In order:
// 1. rebuild the four batch-B tables whose CHECKs v4 tightens (T-018 review
//    n-3, n-4; SQLite can't add a CHECK to an existing table): create
//    "<table>__v4" with the v4 dump's DDL, copy every row by column name,
//    drop the old table, rename, re-create the table's indexes. Foreign keys
//    are off during the step (the opener), children keep their FK text, and
//    the opener runs `PRAGMA foreign_key_check` before commit;
// 2. the exact CREATE statements of drift_schemas/app_database/
//    drift_schema_v4.json for every object new in v4, in the dump's order,
//    without `IF NOT EXISTS` (a stray object of the same name fails the step
//    and the opener restores the pre-migration copy).
// A row that breaks a new CHECK (only possible outside the typed DAOs, e.g.
// a REAL 1.5) fails the copy: the step aborts and the opener restores the
// byte-identical v3 file. Nothing is coerced or dropped.
//
// Never edit: a later schema change is a new version with its own step.
// Tests check both lists against the committed v3 and v4 dumps.

// ignore_for_file: lines_longer_than_80_chars, prefer_single_quotes

/// One table rebuild of the v3 → v4 step.
final class TableRebuild {
  const TableRebuild({
    required this.table,
    required this.createTemp,
    required this.columns,
    required this.indexes,
  });

  /// The table rebuilt (its v3 rows are copied).
  final String table;

  /// The v4 DDL of [table], created as [temp].
  final String createTemp;

  /// Every column, copied by name (the v3 and v4 columns are the same).
  final List<String> columns;

  /// `CREATE INDEX` statements of [table] in v4 (dropped with the old
  /// table).
  final List<String> indexes;

  /// The name the new table has until the rename.
  String get temp => '${table}__v4';
}

/// The tables v4 rebuilds, in the v4 dump's order.
const List<TableRebuild> v4Rebuilds = [
  TableRebuild(
    table: 'catalog_merchants',
    createTemp: r"""CREATE TABLE "catalog_merchants__v4" ("id" INTEGER NOT NULL PRIMARY KEY CHECK (id >= 1), "canonical" TEXT NOT NULL CHECK (length(canonical) BETWEEN 1 AND 200 AND instr(CAST(canonical AS BLOB), X'00') = 0), "name_ar" TEXT CHECK (name_ar IS NULL OR instr(CAST(name_ar AS BLOB), X'00') = 0), "name_en" TEXT CHECK (name_en IS NULL OR instr(CAST(name_en AS BLOB), X'00') = 0), "category_code" TEXT NOT NULL CHECK (length(category_code) BETWEEN 2 AND 32 AND category_code GLOB '[a-z]*' AND category_code NOT GLOB '*[^a-z0-9_]*' AND instr(CAST(category_code AS BLOB), X'00') = 0), "logo_key" TEXT CHECK (logo_key IS NULL OR instr(CAST(logo_key AS BLOB), X'00') = 0), "version" INTEGER NOT NULL CHECK (typeof(version) = 'integer' AND version >= 0));""",
    columns: [
      'id',
      'canonical',
      'name_ar',
      'name_en',
      'category_code',
      'logo_key',
      'version',
    ],
    indexes: [],
  ),
  TableRebuild(
    table: 'catalog_keywords',
    createTemp: r"""CREATE TABLE "catalog_keywords__v4" ("keyword_norm" TEXT NOT NULL CHECK (length(keyword_norm) BETWEEN 1 AND 64 AND keyword_norm NOT GLOB('*[' || char(1) || '-' || char(31) || char(127) || '-' || char(159) || ']*')AND keyword_norm NOT GLOB ' *' AND keyword_norm NOT GLOB '* ' AND keyword_norm NOT GLOB '*  *' AND instr(CAST(keyword_norm AS BLOB), X'00') = 0), "lang" TEXT NOT NULL CHECK (lang GLOB '[a-z][a-z]' AND instr(CAST(lang AS BLOB), X'00') = 0), "category_code" TEXT NOT NULL CHECK (length(category_code) BETWEEN 2 AND 32 AND category_code GLOB '[a-z]*' AND category_code NOT GLOB '*[^a-z0-9_]*' AND instr(CAST(category_code AS BLOB), X'00') = 0), "weight" INTEGER NOT NULL CHECK (typeof(weight) = 'integer' AND weight BETWEEN 0 AND 100), PRIMARY KEY(keyword_norm, lang));""",
    columns: ['keyword_norm', 'lang', 'category_code', 'weight'],
    indexes: [],
  ),
  TableRebuild(
    table: 'merchant_rules',
    createTemp: r"""CREATE TABLE "merchant_rules__v4" ("id" TEXT NOT NULL PRIMARY KEY, "match_kind" TEXT NOT NULL CHECK (match_kind IN ('catalog_merchant', 'merchant_norm', 'counterparty')), "match_value" TEXT NOT NULL, "category_id" TEXT NOT NULL REFERENCES categories(id), "created_at" INTEGER NOT NULL CHECK (typeof(created_at) = 'integer'), "last_applied_at" INTEGER CHECK (last_applied_at IS NULL OR typeof(last_applied_at) = 'integer'), UNIQUE(match_kind, match_value), CHECK(instr(CAST(match_value AS BLOB), X'00') = 0), CHECK(match_kind <> 'merchant_norm' OR(length(match_value) BETWEEN 1 AND 64 AND match_value NOT GLOB '*[^a-z0-9 ]*' AND match_value NOT GLOB ' *' AND match_value NOT GLOB '* ' AND match_value NOT GLOB '*  *')), CHECK(match_kind <> 'catalog_merchant' OR(length(match_value) BETWEEN 1 AND 10 AND match_value GLOB '[1-9]*' AND match_value NOT GLOB '*[^0-9]*')), CHECK(match_kind <> 'counterparty' OR(length(match_value) BETWEEN 1 AND 128 AND match_value NOT GLOB('*[' || char(1) || '-' || char(31) || char(127) || '-' || char(159) || ']*'))));""",
    columns: [
      'id',
      'match_kind',
      'match_value',
      'category_id',
      'created_at',
      'last_applied_at',
    ],
    indexes: [
      r"""CREATE INDEX ix_rules_category ON merchant_rules (category_id)""",
    ],
  ),
  TableRebuild(
    table: 'recurring_items',
    createTemp: r"""CREATE TABLE "recurring_items__v4" ("id" TEXT NOT NULL PRIMARY KEY, "kind" TEXT NOT NULL CHECK (kind IN ('subscription', 'installment', 'card_due', 'gameya', 'bill')), "status" TEXT NOT NULL CHECK (status IN ('suggested', 'active', 'dismissed', 'completed')), "name" TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 60 AND instr(CAST(name AS BLOB), X'00') = 0), "merchant_norm" TEXT CHECK (merchant_norm IS NULL OR(length(merchant_norm) BETWEEN 1 AND 64 AND merchant_norm NOT GLOB '*[^a-z0-9 ]*' AND merchant_norm NOT GLOB ' *' AND merchant_norm NOT GLOB '* ' AND merchant_norm NOT GLOB '*  *' AND instr(CAST(merchant_norm AS BLOB), X'00') = 0)), "account_id" TEXT REFERENCES accounts(id), "amount_minor" INTEGER NOT NULL CHECK (typeof(amount_minor) = 'integer' AND amount_minor BETWEEN 0 AND 9007199254740991), "currency" TEXT NOT NULL CHECK (currency GLOB '[A-Z][A-Z][A-Z]' AND instr(CAST(currency AS BLOB), X'00') = 0), "cadence" TEXT NOT NULL CHECK (cadence IN ('monthly', 'yearly', 'weekly', 'custom_days')), "cadence_days" INTEGER CHECK (cadence_days IS NULL OR(typeof(cadence_days) = 'integer' AND cadence_days BETWEEN 1 AND 3660)), "due_day" INTEGER CHECK (due_day IS NULL OR(typeof(due_day) = 'integer' AND due_day BETWEEN 1 AND 31)), "next_due_date" TEXT CHECK (next_due_date IS NULL OR date(next_due_date) IS next_due_date), "total_count" INTEGER CHECK (total_count IS NULL OR(typeof(total_count) = 'integer' AND total_count >= 1)), "paid_count" INTEGER NOT NULL DEFAULT 0 CHECK (typeof(paid_count) = 'integer' AND paid_count >= 0 AND(total_count IS NULL OR paid_count <= total_count)), "reminder_days" INTEGER NOT NULL DEFAULT 3 CHECK (typeof(reminder_days) = 'integer' AND reminder_days BETWEEN 0 AND 60), "created_at" INTEGER NOT NULL CHECK (typeof(created_at) = 'integer'), CHECK((cadence = 'custom_days')=(cadence_days IS NOT NULL)));""",
    columns: [
      'id',
      'kind',
      'status',
      'name',
      'merchant_norm',
      'account_id',
      'amount_minor',
      'currency',
      'cadence',
      'cadence_days',
      'due_day',
      'next_due_date',
      'total_count',
      'paid_count',
      'reminder_days',
      'created_at',
    ],
    indexes: [
      r"""CREATE INDEX ix_recurring_due ON recurring_items (next_due_date) WHERE status = 'active'""",
      r"""CREATE INDEX ix_recurring_account ON recurring_items (account_id) WHERE account_id IS NOT NULL""",
    ],
  ),
];

/// The names and statements of the objects v4 adds, in creation order.
const List<(String, String)> v4AddedObjects = [
  (
    'assets',
    r"""CREATE TABLE "assets" ("id" TEXT NOT NULL PRIMARY KEY, "type" TEXT NOT NULL CHECK (type IN ('gold', 'gold_coin', 'certificate', 'cash', 'stock_fund', 'real_estate', 'car', 'other')), "name" TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 60 AND name NOT GLOB('*[' || char(1) || '-' || char(31) || char(127) || '-' || char(159) || ']*')AND instr(CAST(name AS BLOB), X'00') = 0), "currency" TEXT CHECK (currency IS NULL OR(currency GLOB '[A-Z][A-Z][A-Z]' AND instr(CAST(currency AS BLOB), X'00') = 0)), "quantity_milli" INTEGER CHECK (quantity_milli IS NULL OR(typeof(quantity_milli) = 'integer' AND quantity_milli BETWEEN 1 AND 9007199254740991)), "karat" INTEGER CHECK (karat IS NULL OR(typeof(karat) = 'integer' AND karat IN (24, 22, 21, 18))), "principal_minor" INTEGER CHECK (principal_minor IS NULL OR(typeof(principal_minor) = 'integer' AND principal_minor BETWEEN 0 AND 9007199254740991)), "rate_bp" INTEGER CHECK (rate_bp IS NULL OR(typeof(rate_bp) = 'integer' AND rate_bp BETWEEN 0 AND 100000)), "payout" TEXT CHECK (payout IS NULL OR payout IN ('monthly', 'quarterly', 'semi_annual', 'annual', 'at_maturity')), "maturity_date" TEXT CHECK (maturity_date IS NULL OR date(maturity_date) IS maturity_date), "manual_value_minor" INTEGER CHECK (manual_value_minor IS NULL OR(typeof(manual_value_minor) = 'integer' AND manual_value_minor BETWEEN 0 AND 9007199254740991)), "acquired_at" TEXT CHECK (acquired_at IS NULL OR date(acquired_at) IS acquired_at), "purchase_price_minor" INTEGER CHECK (purchase_price_minor IS NULL OR(typeof(purchase_price_minor) = 'integer' AND purchase_price_minor BETWEEN 0 AND 9007199254740991)), "purchase_currency" TEXT CHECK (purchase_currency IS NULL OR(purchase_currency GLOB '[A-Z][A-Z][A-Z]' AND instr(CAST(purchase_currency AS BLOB), X'00') = 0)), "is_liability" INTEGER NOT NULL DEFAULT 0 CHECK (is_liability IN (0, 1)), "archived_at" INTEGER CHECK (archived_at IS NULL OR typeof(archived_at) = 'integer'), "created_at" INTEGER NOT NULL CHECK (typeof(created_at) = 'integer'), CHECK(principal_minor IS NULL OR currency IS NOT NULL), CHECK(manual_value_minor IS NULL OR currency IS NOT NULL), CHECK((purchase_price_minor IS NULL)=(purchase_currency IS NULL)), CHECK(karat IS NULL OR type IN ('gold', 'gold_coin')), CHECK(type <> 'gold' OR(quantity_milli IS NOT NULL AND karat IS NOT NULL)), CHECK(type = 'certificate' OR(rate_bp IS NULL AND payout IS NULL AND maturity_date IS NULL)));""",
  ),
  (
    'ix_assets_live',
    r"""CREATE INDEX ix_assets_live ON assets (type) WHERE archived_at IS NULL""",
  ),
  (
    'price_quotes',
    r"""CREATE TABLE "price_quotes" ("symbol" TEXT NOT NULL CHECK (length(symbol) BETWEEN 1 AND 16 AND symbol GLOB '[A-Z]*' AND symbol NOT GLOB '*[^A-Z0-9_]*' AND instr(CAST(symbol AS BLOB), X'00') = 0), "currency" TEXT NOT NULL CHECK (currency GLOB '[A-Z][A-Z][A-Z]' AND instr(CAST(currency AS BLOB), X'00') = 0), "price_minor" INTEGER NOT NULL CHECK (typeof(price_minor) = 'integer' AND price_minor BETWEEN 1 AND 9007199254740991), "per_unit" TEXT NOT NULL CHECK (length(per_unit) BETWEEN 1 AND 16 AND per_unit NOT GLOB '*[^a-z0-9_]*' AND instr(CAST(per_unit AS BLOB), X'00') = 0), "as_of" INTEGER NOT NULL CHECK (typeof(as_of) = 'integer'), "source" TEXT NOT NULL CHECK (source IN ('backend', 'manual')), PRIMARY KEY(symbol, currency, source));""",
  ),
  (
    'fx_rates',
    r"""CREATE TABLE "fx_rates" ("base" TEXT NOT NULL CHECK (base GLOB '[A-Z][A-Z][A-Z]' AND instr(CAST(base AS BLOB), X'00') = 0), "quote" TEXT NOT NULL CHECK (quote GLOB '[A-Z][A-Z][A-Z]' AND instr(CAST(quote AS BLOB), X'00') = 0), "rate_e9" INTEGER NOT NULL CHECK (typeof(rate_e9) = 'integer' AND rate_e9 BETWEEN 1 AND 9007199254740991), "as_of" INTEGER NOT NULL CHECK (typeof(as_of) = 'integer'), PRIMARY KEY(base, quote), CHECK(base <> quote));""",
  ),
  (
    'networth_snapshots',
    r"""CREATE TABLE "networth_snapshots" ("taken_on" TEXT NOT NULL CHECK (date(taken_on) IS taken_on), "unit" TEXT NOT NULL CHECK ((unit GLOB '[A-Z][A-Z][A-Z]' OR(length(unit) BETWEEN 4 AND 16 AND unit GLOB 'XAU*' AND unit NOT GLOB '*[^A-Z0-9_]*'))AND instr(CAST(unit AS BLOB), X'00') = 0), "assets_minor" INTEGER NOT NULL CHECK (typeof(assets_minor) = 'integer' AND assets_minor BETWEEN -9007199254740991 AND 9007199254740991), "liabilities_minor" INTEGER NOT NULL CHECK (typeof(liabilities_minor) = 'integer' AND liabilities_minor BETWEEN -9007199254740991 AND 9007199254740991), PRIMARY KEY(taken_on, unit));""",
  ),
  (
    'zakah_ledger',
    r"""CREATE TABLE "zakah_ledger" ("id" TEXT NOT NULL PRIMARY KEY, "asset_id" TEXT REFERENCES assets(id), "lot_start_hijri" TEXT NOT NULL CHECK (instr(CAST(lot_start_hijri AS BLOB), X'00') = 0 AND lot_start_hijri GLOB '[0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]' AND substr(lot_start_hijri, 6, 2) BETWEEN '01' AND '12' AND substr(lot_start_hijri, 9, 2) BETWEEN '01' AND '30'), "due_on" TEXT NOT NULL CHECK (date(due_on) IS due_on), "unit" TEXT NOT NULL CHECK ((unit GLOB '[A-Z][A-Z][A-Z]' OR(length(unit) BETWEEN 4 AND 16 AND unit GLOB 'XAU*' AND unit NOT GLOB '*[^A-Z0-9_]*'))AND instr(CAST(unit AS BLOB), X'00') = 0), "amount_minor" INTEGER NOT NULL CHECK (typeof(amount_minor) = 'integer' AND amount_minor BETWEEN 0 AND 9007199254740991), "status" TEXT NOT NULL CHECK (status IN ('pending', 'partial', 'paid')), "paid_minor" INTEGER NOT NULL DEFAULT 0 CHECK (typeof(paid_minor) = 'integer' AND paid_minor BETWEEN 0 AND 9007199254740991), CHECK(paid_minor <= amount_minor), CHECK(CASE status WHEN 'pending' THEN paid_minor = 0 WHEN 'partial' THEN paid_minor > 0 AND paid_minor < amount_minor ELSE paid_minor = amount_minor END));""",
  ),
  (
    'ix_zakah_asset',
    r"""CREATE INDEX ix_zakah_asset ON zakah_ledger (asset_id) WHERE asset_id IS NOT NULL""",
  ),
  (
    'ix_zakah_open',
    r"""CREATE INDEX ix_zakah_open ON zakah_ledger (due_on) WHERE status <> 'paid'""",
  ),
  (
    'ignore_rules',
    r"""CREATE TABLE "ignore_rules" ("id" TEXT NOT NULL PRIMARY KEY, "institution_code" TEXT NOT NULL CHECK (length(institution_code) BETWEEN 2 AND 32 AND institution_code NOT GLOB '*[^a-z0-9_]*' AND instr(CAST(institution_code AS BLOB), X'00') = 0), "last4" TEXT CHECK (last4 IS NULL OR(length(last4) BETWEEN 2 AND 4 AND last4 NOT GLOB '*[^0-9]*' AND instr(CAST(last4 AS BLOB), X'00') = 0)), "channel" TEXT NOT NULL CHECK (channel IN ('sms', 'notification', 'apple_pay')), "created_at" INTEGER NOT NULL CHECK (typeof(created_at) = 'integer'), UNIQUE(institution_code, last4, channel));""",
  ),
  (
    'ux_ignore_institution',
    r"""CREATE UNIQUE INDEX ux_ignore_institution ON ignore_rules (institution_code, channel) WHERE last4 IS NULL""",
  ),
  (
    'capture_senders',
    r"""CREATE TABLE "capture_senders" ("sender" TEXT NOT NULL PRIMARY KEY CHECK (length(sender) BETWEEN 1 AND 128 AND sender NOT GLOB('*[' || char(1) || '-' || char(31) || char(127) || '-' || char(159) || ']*')AND instr(CAST(sender AS BLOB), X'00') = 0), "channel" TEXT NOT NULL CHECK (channel IN ('sms', 'notification', 'shortcut_message')), "confirmed_count" INTEGER NOT NULL DEFAULT 0 CHECK (typeof(confirmed_count) = 'integer' AND confirmed_count >= 0), "always_capture" INTEGER NOT NULL DEFAULT 0 CHECK (always_capture IN (0, 1)), "created_at" INTEGER NOT NULL CHECK (typeof(created_at) = 'integer'));""",
  ),
  (
    'custom_templates',
    r"""CREATE TABLE "custom_templates" ("id" TEXT NOT NULL PRIMARY KEY, "sender" TEXT NOT NULL CHECK (length(sender) BETWEEN 1 AND 128 AND sender NOT GLOB('*[' || char(1) || '-' || char(31) || char(127) || '-' || char(159) || ']*')AND instr(CAST(sender AS BLOB), X'00') = 0), "channel" TEXT NOT NULL CHECK (channel IN ('sms', 'notification', 'shortcut_message')), "template_json" TEXT NOT NULL CHECK (length(CAST(template_json AS BLOB)) <= 65536 AND instr(CAST(template_json AS BLOB), X'00') = 0 AND CASE WHEN json_valid(template_json) THEN json_type(template_json) = 'object' ELSE 0 END), "sample_hash" TEXT NOT NULL CHECK (length(sample_hash) = 64 AND sample_hash NOT GLOB '*[^0-9a-f]*' AND instr(CAST(sample_hash AS BLOB), X'00') = 0), "created_at" INTEGER NOT NULL CHECK (typeof(created_at) = 'integer'));""",
  ),
  (
    'ix_templates_sender',
    r"""CREATE INDEX ix_templates_sender ON custom_templates (sender, channel)""",
  ),
  (
    'review_items',
    r"""CREATE TABLE "review_items" ("id" TEXT NOT NULL PRIMARY KEY, "kind" TEXT NOT NULL CHECK (kind IN ('unrecognized', 'low_confidence', 'new_sender', 'needs_category', 'transfer_ambiguous', 'reimbursement_suggestion', 'subscription_suggestion', 'fx_pair_suggestion', 'payday_suggestion')), "raw_message_id" TEXT REFERENCES raw_messages(id)ON DELETE CASCADE, "txn_id" TEXT REFERENCES transactions(id)ON DELETE CASCADE, "payload" TEXT CHECK (payload IS NULL OR(length(CAST(payload AS BLOB)) <= 65536 AND instr(CAST(payload AS BLOB), X'00') = 0 AND CASE WHEN json_valid(payload) THEN json_type(payload) = 'object' ELSE 0 END)), "created_at" INTEGER NOT NULL CHECK (typeof(created_at) = 'integer'), "resolved_at" INTEGER CHECK (resolved_at IS NULL OR typeof(resolved_at) = 'integer'), "resolution" TEXT CHECK (resolution IS NULL OR(length(resolution) BETWEEN 1 AND 64 AND resolution NOT GLOB '*[^a-z0-9_]*' AND instr(CAST(resolution AS BLOB), X'00') = 0)), CHECK(resolution IS NULL OR resolved_at IS NOT NULL));""",
  ),
  (
    'ix_review_open',
    r"""CREATE INDEX ix_review_open ON review_items (kind, created_at) WHERE resolved_at IS NULL""",
  ),
  (
    'ix_review_raw',
    r"""CREATE INDEX ix_review_raw ON review_items (raw_message_id) WHERE raw_message_id IS NOT NULL""",
  ),
  (
    'ix_review_txn',
    r"""CREATE INDEX ix_review_txn ON review_items (txn_id) WHERE txn_id IS NOT NULL""",
  ),
  (
    'settings',
    r"""CREATE TABLE "settings" ("key" TEXT NOT NULL PRIMARY KEY CHECK (length("key") BETWEEN 1 AND 64 AND "key" NOT GLOB '*[^a-z0-9_.]*' AND instr(CAST("key" AS BLOB), X'00') = 0), "value" TEXT NOT NULL CHECK (typeof(value) = 'text' AND length(CAST(value AS BLOB)) <= 16384 AND instr(CAST(value AS BLOB), X'00') = 0), "updated_at" INTEGER NOT NULL CHECK (typeof(updated_at) = 'integer'));""",
  ),
  (
    'secure_state',
    r"""CREATE TABLE "secure_state" ("key" TEXT NOT NULL PRIMARY KEY CHECK (length("key") BETWEEN 1 AND 64 AND "key" NOT GLOB '*[^a-z0-9_.]*' AND instr(CAST("key" AS BLOB), X'00') = 0), "value" BLOB NOT NULL CHECK (typeof(value) = 'blob' AND length(value) BETWEEN 1 AND 65536), "updated_at" INTEGER NOT NULL CHECK (typeof(updated_at) = 'integer'));""",
  ),
  (
    'outbox',
    r"""CREATE TABLE "outbox" ("id" TEXT NOT NULL PRIMARY KEY, "kind" TEXT NOT NULL CHECK (kind IN ('contribution', 'bank_request', 'purchase_verify')), "payload" TEXT NOT NULL CHECK (length(CAST(payload AS BLOB)) <= 65536 AND instr(CAST(payload AS BLOB), X'00') = 0 AND CASE WHEN json_valid(payload) THEN json_type(payload) = 'object' ELSE 0 END), "created_at" INTEGER NOT NULL CHECK (typeof(created_at) = 'integer'), "attempts" INTEGER NOT NULL DEFAULT 0 CHECK (typeof(attempts) = 'integer' AND attempts >= 0), "next_attempt_at" INTEGER CHECK (next_attempt_at IS NULL OR typeof(next_attempt_at) = 'integer'));""",
  ),
  (
    'ix_outbox_kind',
    r"""CREATE INDEX ix_outbox_kind ON outbox (kind, created_at)""",
  ),
  (
    'voice_usage',
    r"""CREATE TABLE "voice_usage" ("month" TEXT NOT NULL PRIMARY KEY CHECK (length(month) = 7 AND date(month || '-01') IS month || '-01'), "count" INTEGER NOT NULL CHECK (typeof(count) = 'integer' AND count >= 0));""",
  ),
  (
    'undo_batches',
    r"""CREATE TABLE "undo_batches" ("id" TEXT NOT NULL PRIMARY KEY, "created_at" INTEGER NOT NULL CHECK (typeof(created_at) = 'integer'), "description_key" TEXT NOT NULL CHECK (length(description_key) BETWEEN 1 AND 64 AND description_key NOT GLOB '*[^A-Za-z0-9_.]*' AND instr(CAST(description_key AS BLOB), X'00') = 0), "before_json" TEXT NOT NULL CHECK (length(CAST(before_json AS BLOB)) <= 8388608 AND instr(CAST(before_json AS BLOB), X'00') = 0 AND json_valid(before_json)));""",
  ),
  (
    'ix_undo_created',
    r"""CREATE INDEX ix_undo_created ON undo_batches (created_at)""",
  ),
  (
    'diag_log',
    r"""CREATE TABLE "diag_log" ("id" INTEGER NOT NULL PRIMARY KEY, "at" INTEGER NOT NULL CHECK (typeof(at) = 'integer'), "level" TEXT NOT NULL CHECK (level IN ('debug', 'info', 'warn', 'error')), "code" TEXT NOT NULL CHECK (length(code) BETWEEN 1 AND 64 AND code NOT GLOB '*[^A-Za-z0-9_.:-]*' AND instr(CAST(code AS BLOB), X'00') = 0), "fields" TEXT CHECK (fields IS NULL OR(length(CAST(fields AS BLOB)) <= 2048 AND instr(CAST(fields AS BLOB), X'00') = 0 AND CASE WHEN json_valid(fields) THEN json_type(fields) = 'object' ELSE 0 END)));""",
  ),
  ('ix_diag_at', r"""CREATE INDEX ix_diag_at ON diag_log (at)"""),
];
