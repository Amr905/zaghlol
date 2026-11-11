// T-018 (T-017 review S-2): FTS5 options of the current schema. They live
// in each FTS table's `_config` shadow table (data, not schema), so drift's
// `createAll` and the schema dumps don't carry them: [AppDatabase] runs
// these after `createAll` on a fresh database, and each migration step
// that changes them runs its own frozen copy (migrations/v3_financial_b.dart).

/// FTS5 `secure-delete` on both transaction search tables: the merchant,
/// counterparty and note tokens of a deleted row are removed from the index
/// segments at once, not left until the next segment merge. Persistent;
/// needs SQLite ≥ 3.44 (the bundled sqlite3mc is newer; a test checks).
/// `catalog_alias_fts` holds catalog data only and keeps the default.
const List<String> ftsOptionStatements = [
  'INSERT INTO transactions_fts (transactions_fts, rank) '
      "VALUES ('secure-delete', 1)",
  'INSERT INTO transactions_fts_short (transactions_fts_short, rank) '
      "VALUES ('secure-delete', 1)",
];
