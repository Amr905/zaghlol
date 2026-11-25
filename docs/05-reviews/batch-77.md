# Batch 77 review: T-266 (C4), T-269 (C3), T-270 (C4)

Batch `batch/2026-11-26-77` at `37e219b7`, compared with `main` at `89583b27`. One reviewer covered code, security and data (Opus), because the batch holds two C4 tasks.

Verdict: **CHANGES_REQUESTED**.
- T-266 has 1 major (M1).
- T-269 has 1 major (M2).
- T-270 is APPROVED.

## Checks run

| Check | Result |
|-------|--------|
| `flutter pub get --enforce-lockfile` | ok |
| `flutter analyze` (app) | No issues found |
| `flutter test -x golden test/core/db test/features/accounts test/features/wealth test/features/backup` | 1477 pass, 1 skipped (the existing skip), 0 fail |
| `flutter test -x golden test/features/export_import test/features/transfers test/features/ingestion test/ingestion` | 639 pass, 0 fail |
| `zaghlol_lints ../../app` | 558 files, 0 issues |
| Crypto diff (`app/lib/**/crypto/**`, `backup/data/*` except `drive_auth.dart`) | none |

---

## T-266: link a debit card to its bank account (C4: schema v5→v6 and ledger)

Verdict: **CHANGES_REQUESTED** (M1)

**What holds up.** I traced these paths:
- **Link / unlink.**
  - Link moves the card's `account_balances` rows and typed balances to the account, and the newer instant wins. Nothing of the card's is left to count twice, now or after an unlink.
  - The ledger reads `account_id IN (account, its linked cards)` strictly after the account's anchor:
    - Card transactions older than the anchor are not added. The anchor already includes them.
    - When the card's moved anchor is newer, it correctly drops account transactions between the two anchors, because a card message's balance is the account's balance.
  - Unlink re-anchors the account as a typed balance as of now, and only in currencies where the card's transactions counted after the anchor (`asOf` is the anchor's, `balance_rules.dart:306`). The account's figure does not move.
- **Net worth, Money tab, snapshots, `totalsByCurrency`.**
  - They all read one breakdown (`AccountLedger.lines`) or skip linked cards.
  - Card dues and the credit liability path are untouched, because a credit card cannot be linked (CHECK `kind = 'debit'` plus the repository guard).
  - Budgets, payday and the cash-cover CTE are transaction-based. A link adds no rows, so they are unchanged.
- **SMS balance.** `upsertBalanceIfNotOlder` resolves the target inside one statement, so it cannot race a link. It is the only writer of `account_balances` (`recordBalance` is its only caller).
- **Transfers.** A card leg and its account's leg map to one ledger id, so they never auto-pair, and a manual pair between them is refused. A pair that existed before the link nets to zero on the one ledger.
- **Never auto-link.** The only callers of `linkCard` are the two taps in `card_link_section.dart`. Merge only repoints or clears links.
- **Migration.**
  - The step is frozen and additive (`ALTER TABLE … ADD COLUMN` with FK and CHECK, plus a partial index), with `drift_schema_v6.json`.
  - `migration_v6_test.dart` covers: the v5 file through the opener, rows kept, shape equal to both the fresh schema and the dump, and the file restored byte for byte when the step fails.
  - The v4 and v5 chain tests were extended. A v5 backup restores through the same step, because backups carry the whole file and `snapshot_db` migrates an older schema.
- **Privacy.** No logging was added, and money in the diff is never a `double`.

**AC→test map.** Every criterion has a test:
- Migration: `migration_v6_test.dart`.
- Linked purchase lowers the account once, SMS balance lands on the account, unlink: `card_link_test.dart`, groups "ledger while linked" and "unlink".
- Widget tests in ar and en: `card_link_section_test.dart`, which loops `Locale('en')` and `Locale('ar')` with RTL.

**Major**
- **M1. Merges that end a link do not re-anchor, so counted amounts move or are lost.** `app/lib/features/accounts/data/drift_accounts_repository.dart:295-306`, plus `:307-326` for part (c). The merge picker offers every live account as a target (`merge_flow.dart:31`), so all three cases below can be reached:
  - **(a) A linked card C (on account A) merged into an unlinked card or account D other than A.** `setLinked(sourceId, null)` runs without `_unlinkIn`. C's transactions after A's anchor move to D and stop counting on A. Example: A was reported at 10,000 at t0, and C spent 500 at t1. A showed 9,500; after the merge A shows 10,000. The 500 is silently added back.
  - **(b) Account A with linked cards merged into a target that cannot hold cards** (a card, cash, BNPL). `repointLinked(sourceId, null)` unlinks the cards without a re-anchor. A's anchor moves to the target, but the cards' post-anchor transactions no longer count on it, so the target's figure is overstated by them. The design note says "the merged figures are already a new state", but they are not: the moved anchors are old instants, and the computed figure included the card spend.
  - **(c) Merging into a target that is itself a linked card.** The source's `account_balances` rows and typed balances move onto the linked card (`:307-326`). While the link holds they are invisible to the ledger. They are still read by Zakah `_baseLots` (`zakah_repository.dart:234`, which reads `account_balances` without the link rule; the Zakah flag is off). They reappear as the card's own figure after an unlink.
  - **Required:**
    - For (a) and (b), re-anchor exactly as `_unlinkIn` does (the account's current figure as a typed balance as of now), before the link is cleared or repointed to null.
    - For (c), send the source's balances to the target card's account (the newer instant wins), or refuse a merge into a linked card with `ACC_LINKED`.
    - Add a ledger test for each case that asserts the figure. The current merge tests only check `linked_account_id`.

**Minor (follow-up)**
- **FU-355.** `transfer_pairing.dart:435`. Card legs are now mapped to their account's id. When the account is `multi_currency`, a card leg can therefore become an `fxConversionCandidates` match: a card leg and an account leg treated as a conversion inside the account. This is unlikely, but excluding linked-card legs from the conversion candidates would avoid it.
- **FU-356.** The merge picker offers linked cards and card-holding accounts with no hint about what happens to the link. Add one line to the merge confirm. This pairs with the dedicated `ACC_LINKED` message the builder already listed.

**Security / data (C4)**
- FK and CHECK: correct. The CHECK applies to existing rows (all NULL) when the column is added. There is no hard delete of accounts, so the missing `ON DELETE` clause is fine.
- Migration safety: confirmed (see above).
- Backups: the column travels with the file, and old backups migrate.
- No new data leaves the phone, and nothing is logged.
- The only data-integrity issue is M1.

---

## T-269: bank statement import UI (C3)

Verdict: **CHANGES_REQUESTED** (M2)

**What holds up.**
- **Nothing is saved before Confirm.** Review runs `parse` plus a `dryRun`. The only write path is `_confirm`.
- **Flagged rows need an answer.** `_blocked` disables Confirm, and the use case still throws `reviewRequired`.
- **Duplicates are skipped by default.** The real `run` dedupes with `keepDuplicates` empty unless the user chose "Add anyway". This also holds for the "new account" path, where the dry run is skipped.
- **Direction and sign.** Amounts stay positive minor units in the statement currency. The direction comes only from `isExpense` or the user's explicit `asExpense` / `asIncome`. Nothing is converted, and the account list is filtered to the statement currency.
- **Password.** It is held in a local in `_pick` only.
- **Bytes.** Picked bytes are zeroed, and `FilePicker.clearTemporaryFiles` runs.
- **Image temp file.** It is deleted in `finally` after `sealImage`, which is the same contract as the receipt scan (`OcrEngine.sealImage` takes a plain temp path).
- **Errors.** No error carries text, paths or names.

**AC→test map.** Every criterion has a test in `statement_import_screen_test.dart`:
- happy path and "nothing saved until Confirm";
- year prompt;
- unknown direction;
- duplicate;
- failures: no table, no OCR, no text, unreadable, password, save failure.

Goldens `s67b_*` were regenerated by app-regen.

**Major**
- **M2. Statement dedupe misses transactions that are already counted, so confirming an import double counts.** T-269 makes the bank PDF sources reachable for the first time (`import_ports.dart`, `available: true`). The duplicate check comes from T-156:
  - **(a) Only the chosen account is searched.** `drift_csv_import_store.dart:67` (`accountIds: {accountId}`), called from `import_statement_pdf.dart:347`. A bank statement lists the debit-card purchases, but SMS put them on the card's account id. Importing the account's statement re-adds every card purchase. With a linked card (T-266), the ledger then subtracts each purchase twice from the account after its anchor, and spending totals count them twice in any case.
  - **(b) The key uses the exact direction.** `import_statement_pdf.dart:433`. Statement rows are only `expense` or `income`, but SMS store InstaPay and wallet moves as `transfer_out` / `transfer_in`, plus `fee` and `refund`. Those never match, so an imported period that SMS already covered adds every InstaPay transfer and fee again, as new spending.
  - **Required:**
    - Dedupe over `account_id IN (account, its live linked cards)`, using `linkedCardsOf`.
    - Compare by cash side: outflow = `expense` / `fee` / `transfer_out`, inflow = `income` / `refund` / `transfer_in`, plus amount and currency.
    - Add use-case tests for a linked-card purchase and for an SMS `transfer_out` against the same statement row.

**Minor (follow-up)**
- **FU-357.** `statement_import_screen.dart:385-394`. The new account is created (`resolve`) in its own transaction before `uc.run`. If the run fails (`storeFailed`), an empty account stays behind. Create it inside the import's write transaction, or remove it on failure.
- **FU-358.** `import_source_screen.dart:65` and `statement_import_screen.dart:386`. The new account's institution code is `ImportSourceId.name`, which is `misr` for Banque Misr, while the SMS registry uses `bm`. A Banque Misr statement account therefore never matches the SMS-made account, either in `resolve` or in the T-266 "same bank" suggestion. Map source ids to registry codes.
- **FU-359.** The day-window dedupe misses an SMS whose local time falls on the day before the statement's posting date (late-night purchase, next-day value date). Consider allowing ±1 day once (a) and (b) are fixed.

---

## T-270: backup fixes (C4)

Verdict: **APPROVED**

**What holds up.**
- `driveBackupSetupOf` mirrors the authorizer's own check. On S-66 the check runs before the passphrase step (`_backUp` returns early), so no KDF runs and no passphrase is asked when the build has no client ID. "Back up now" is disabled for Drive, and iCloud stays usable (A2).
- `DRIVE_NOT_CONFIGURED` now maps to its own kind on S-66 and S-04, without "Try again".
- The port change `backupNow → Future<bool>` returns true only for `backedUp`, and iCloud `unconfirmed` shows the pending banner instead of "done". Every implementer and fake of the port was updated, and analyze is clean.

**AC→test map.**
- Root causes are written in the task file.
- `drive_setup_test.dart` covers the flavour → wording map.
- `backup_screen_test.dart` covers: not configured with no passphrase asked, iCloud still offered, and pending.
- `restore_screen_test.dart` covers the not-configured path.
- `backup_restore_test.dart` covers the Free slot round trip.

**Security**
- The crypto, snapshot and Drive/iCloud stores have no diff (confirmed).
- The dev-build message names only the define *names*, never a value, and `googleServerClientId` is not a secret in any case. No logging was added.

**Nit (follow-up)**
- **FU-360.** `backup_ports.dart:430`. Any status other than `backedUp` (the `skipped*` values included) returns false, so S-66 would show the iCloud "still uploading" text. That cannot happen from today's screen, which always passes Drive or iCloud. Return a three-way result, or map only `unconfirmed` to pending.

---

## Follow-ups opened

FU-355 to FU-360 (above). Owners: T-266 lane (FU-355, FU-356), T-269 lane (FU-357 to FU-359), T-270 lane (FU-360).
