// T-149 (design note §2): which tables a backup carries (FR-BAK-06) and which
// stay with the device (FR-BAK-07). Every table of the schema must be in
// exactly one list; a test fails on any table that is in neither, so a new
// table can't silently ship in (or drop out of) backups.

/// Device tables, in the order restore writes them into the staged database
/// (parents before children). Emptied in every snapshot; on restore the
/// live device's rows are carried over.
const List<String> deviceTables = [
  'db_meta', // facts about this file (restore notice, follow-ups)
  'secure_state', // install id/token, entitlement, flags, backup key slot
  'outbox', // pending network sends of this install
  'diag_log', // this device's diagnostics
  'catalog_meta', // the downloaded merchant catalog (re-synced, FR-BAK-07)
  'catalog_merchants',
  'catalog_aliases', // catalog_alias_fts follows through its triggers
  'catalog_keywords',
];

/// Tables carried by the backup (FR-BAK-06). FTS5 shadow tables and the
/// FTS source table travel with the pages; they are listed by their owner.
const List<String> backedUpTables = [
  'categories',
  'accounts',
  'account_balances',
  'raw_messages',
  'transactions',
  'transfer_pairs',
  'split_participants',
  'offset_links',
  'transactions_fts_src',
  'merchant_rules',
  'budgets',
  'fired_alerts',
  'cycle_summaries',
  'recurring_items',
  'recurring_occurrences',
  'assets',
  'price_quotes',
  'fx_rates',
  'networth_snapshots',
  'zakah_ledger',
  'ignore_rules',
  'capture_senders',
  'custom_templates',
  'review_items',
  'settings',
  'voice_usage',
  'undo_batches',
];

/// FTS5 virtual tables: `transactions_fts*` index backed-up data and travel
/// with it; `catalog_alias_fts` indexes `catalog_aliases` (device).
const List<String> ftsTables = [
  'transactions_fts',
  'transactions_fts_short',
  'catalog_alias_fts',
];

/// The FTS5 shadow-table suffixes (`<fts>_data`, …).
const List<String> ftsShadowSuffixes = [
  '_data',
  '_idx',
  '_content',
  '_docsize',
  '_config',
];

/// `db_meta` keys written by a restore for the app to act on once.
/// FR-BAK-07: prompt once to re-grant capture permissions.
const String restoreRegrantDueKey = 'restore_regrant_due';

/// FR-BAK-07: re-sync the merchant catalog after a restore.
const String restoreCatalogResyncDueKey = 'restore_catalog_resync_due';
