// T-196: the v4 → v5 step, frozen (D-72). In order:
// 1. rebuild `recurring_items` (SQLite can't widen a CHECK): create
//    "recurring_items__v5" with the v5 dump's DDL (the cadence CHECK also
//    allows 'quarterly' and 'semi_annual'; the new nullable column
//    `auto_added_at` is NULL for every old row), copy every old column by
//    name, check the row counts, drop the old table, rename, re-create its
//    indexes. Foreign keys are off during the step (the opener), the child
//    table keeps its FK text, and the opener runs `PRAGMA foreign_key_check`
//    before commit;
// 2. create `recurring_dismissals`, the one object new in v5.
// A stored row can't break the wider CHECK, but a failure of any statement
// aborts the step and the opener restores the byte-identical v4 file.
//
// Never edit: a later schema change is a new version with its own step. A
// test checks the lists against the committed v4 and v5 dumps.

// ignore_for_file: lines_longer_than_80_chars, prefer_single_quotes

/// The one table rebuild of the v4 → v5 step.
final class V5Rebuild {
  const V5Rebuild({
    required this.table,
    required this.createTemp,
    required this.columns,
    required this.indexes,
  });

  final String table;

  /// The v5 DDL of [table], created as [temp].
  final String createTemp;

  /// The v4 columns, copied by name; v5's added columns take their default.
  final List<String> columns;

  /// `CREATE INDEX` statements of [table] in v5.
  final List<String> indexes;

  /// The name the new table has until the rename.
  String get temp => '${table}__v5';
}

const V5Rebuild v5RecurringRebuild = V5Rebuild(
  table: 'recurring_items',
  createTemp: r"""CREATE TABLE "recurring_items__v5" ("id" TEXT NOT NULL PRIMARY KEY, "kind" TEXT NOT NULL CHECK (kind IN ('subscription', 'installment', 'card_due', 'gameya', 'bill')), "status" TEXT NOT NULL CHECK (status IN ('suggested', 'active', 'dismissed', 'completed')), "name" TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 60 AND instr(CAST(name AS BLOB), X'00') = 0), "merchant_norm" TEXT CHECK (merchant_norm IS NULL OR(length(merchant_norm) BETWEEN 1 AND 64 AND merchant_norm NOT GLOB '*[^a-z0-9 ]*' AND merchant_norm NOT GLOB ' *' AND merchant_norm NOT GLOB '* ' AND merchant_norm NOT GLOB '*  *' AND instr(CAST(merchant_norm AS BLOB), X'00') = 0)), "account_id" TEXT REFERENCES accounts(id), "amount_minor" INTEGER NOT NULL CHECK (typeof(amount_minor) = 'integer' AND amount_minor BETWEEN 0 AND 9007199254740991), "currency" TEXT NOT NULL CHECK (currency GLOB '[A-Z][A-Z][A-Z]' AND instr(CAST(currency AS BLOB), X'00') = 0), "cadence" TEXT NOT NULL CHECK (cadence IN ('monthly', 'quarterly', 'semi_annual', 'yearly', 'weekly', 'custom_days')), "cadence_days" INTEGER CHECK (cadence_days IS NULL OR(typeof(cadence_days) = 'integer' AND cadence_days BETWEEN 1 AND 3660)), "due_day" INTEGER CHECK (due_day IS NULL OR(typeof(due_day) = 'integer' AND due_day BETWEEN 1 AND 31)), "next_due_date" TEXT CHECK (next_due_date IS NULL OR date(next_due_date) IS next_due_date), "total_count" INTEGER CHECK (total_count IS NULL OR(typeof(total_count) = 'integer' AND total_count >= 1)), "paid_count" INTEGER NOT NULL DEFAULT 0 CHECK (typeof(paid_count) = 'integer' AND paid_count >= 0 AND(total_count IS NULL OR paid_count <= total_count)), "reminder_days" INTEGER NOT NULL DEFAULT 3 CHECK (typeof(reminder_days) = 'integer' AND reminder_days BETWEEN 0 AND 60), "created_at" INTEGER NOT NULL CHECK (typeof(created_at) = 'integer'), "auto_added_at" INTEGER CHECK (auto_added_at IS NULL OR typeof(auto_added_at) = 'integer'), CHECK((cadence = 'custom_days')=(cadence_days IS NOT NULL)));""",
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
);

/// The names and statements of the objects v5 adds, in creation order.
const List<(String, String)> v5AddedObjects = [
  (
    'recurring_dismissals',
    r"""CREATE TABLE "recurring_dismissals" ("dismissal_key" TEXT NOT NULL PRIMARY KEY CHECK (length(dismissal_key) BETWEEN 3 AND 200 AND instr(CAST(dismissal_key AS BLOB), X'00') = 0), "dismissed_at" INTEGER NOT NULL CHECK (typeof(dismissed_at) = 'integer'));""",
  ),
];
