// T-266: the v5 → v6 step, frozen. Additive, no rebuild: `accounts` gains
// the nullable `linked_account_id` (FK to accounts, CHECK: only a debit card,
// never itself) by `ALTER TABLE … ADD COLUMN` (SQLite accepts a REFERENCES
// column whose default is NULL, and tests the CHECK against the existing rows,
// which are all NULL), then the partial index of the linked cards. A failure
// of either statement aborts the step and the opener restores the
// byte-identical v5 file.
//
// Never edit: a later schema change is a new version with its own step. A
// test checks the statements against the committed v5 and v6 dumps.

// ignore_for_file: lines_longer_than_80_chars, prefer_single_quotes

/// The column v6 adds to `accounts`, as an `ALTER TABLE` statement.
const String v6AddLinkedAccountColumn =
    r"""ALTER TABLE "accounts" ADD COLUMN "linked_account_id" TEXT REFERENCES accounts(id) CHECK (linked_account_id IS NULL OR(linked_account_id <> id AND kind = 'debit'))""";

/// The names and statements of the objects v6 adds, in creation order.
const List<(String, String)> v6AddedObjects = [
  (
    'ix_accounts_linked',
    r"""CREATE INDEX ix_accounts_linked ON accounts (linked_account_id) WHERE linked_account_id IS NOT NULL""",
  ),
];
