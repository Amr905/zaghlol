# T-046 security and privacy review (IngestRawMessages)

Reviewer: security-privacy-reviewer (Opus). Branch `origin/task/T-046-ingest` @ 8e904fd, diff base `origin/task/T-046-design-note`.
Scope: the use case, its ports and Drift store, the cycle and spike wiring, the body hash, the parser change (FU-078) and the tests.
I ran `flutter test test/features/ingestion test/ingestion` locally (153 green). I also ran a throw-away probe test, not committed, to
confirm F1.

## Verdict: CHANGES_REQUESTED

Two Medium findings need a fix before merge. F1 is a confirmed silent loss of captured messages: after one Guard-invalid DB row, every
message from an always-capture or custom-template sender is dropped and acked. F2 is head-of-line blocking: one entry that fails in a way
that isn't transient stops the whole spool, and the spool fills up. Both fixes are small. Four Low and four Info items become follow-ups.
None of those is "before merge".

## What I checked and found sound

- **No body in any output.** `IncomingMessage`, outcomes, `IngestBatchResult`, `RawInsert`, `TxnInsert`, `TxnPatch`, `TxnCandidate`,
  `IgnoreRuleState`, `CaptureSenderState` and `BatchContext` override `toString` with a kind, a code or an id. `IngestBatchFailed` is a
  `SafeException` with fixed codes. The catch-all (`ingest_raw_messages.dart` l.145) maps to `INGEST_INTERNAL` and drops the original
  error. The cycle's catch-all returns the constant `DB_WRITE_FAILED` (`ingestion_cycle.dart` l.203-209). Diag gets fixed `ING_*`
  codes and counts only, with no ids. The drop reason is a Guard or parser wire enum. The app-ci no-logging grep now covers
  `features/ingestion/*/*.dart`. The canary test (`ingest_raw_messages_test.dart` l.873-937) drives `ZG_CANARY_7731` through these
  paths: unrecognized, OTP, generic, a canary sender, insert, merge, duplicate, a `StateError(canary)` hook and a constraint failure.
  It runs in a print-capturing zone and also checks review payloads, diag codes and FTS. A bug that only appeared through an unexpected
  error text would be caught.
- **OTPs are never stored.** For background origins, the Guard re-check (l.278-306) and parser stage 0 (l.309-317) both run before
  dedupe and before any write, so a dropped message leaves no raw row, review item, FTS row or diag field. User-confirmed input skips
  the Guard but still goes through parser stage 0, except over 4,000 characters (F4).
- **An invalid base Guard config.** `call` throws `CONFIG_INVALID` before the transaction whenever a background message is in the batch
  (l.113-116). Nothing is written or acked. The cycle treats this as not transient, the next drain returns the same ids, and the cycle
  ends `OK` with them counted as stuck (l.159-163, l.189-195). Nothing is deleted. The test "an invalid Guard base…" covers it. A
  user-confirmed-only batch is not blocked, which is correct.
- **Review payloads.** `possibleDuplicate` carries `reason` and `candidateTxnIds` only (l.709-712). The other payloads hold reason
  codes, confidence, `institutionCode`/`templateId` (registry codes), and typed `Money` for `new_sender` and `settledAmountDiffers`,
  which the design allows. No body, sender, last-4 or excerpt.
- **The sender in institution codes (Q3).** A generic account's `institution_code` is `g_` + 16 hex of
  `SHA-256("zg.gen.v1"‖0‖senderKey)` (l.1013-1016). No sender text ends up in a code column. The label holds the sender as received,
  inside the encrypted DB, and `_label` caps it at 30 runes (`drift_accounts_repository.dart`). See F6 for the reversibility of this
  hash.
- **Storage.** Bodies are only in `raw_messages.body`, in the SQLite3MultipleCiphers DB. FTS indexes merchant and counterparty only.
  Raw text in backups is required by A-46 and FR-BAK-06 and is covered by the backup AES-256-GCM. Raw rows have no retention limit,
  which matches the SRS (A-46 re-parse). Every SQL value is bound (`drift_ingest_store.dart`), and candidate reads are capped at 100.
- **Integrity across two connections and crashes.** All dedupe and merge reads run inside drift's `BEGIN IMMEDIATE`, with one savepoint
  per message. `ux_raw_body_hash` is the backstop (`_RaceLost` → `duplicate`, `ING_DUP_RACE`). Per-message changes and diag counts are
  dropped when a savepoint rolls back (`local.clear()`). Events are published only after the commit, and the ack uses `result.ackable`
  only after `ingest` returned (`ingestion_cycle.dart` l.217). If the commit succeeds and the ack is then lost, re-delivery becomes
  `duplicate`. If the process dies before the commit, SQLite rolls back. Tests cover 50 two-isolate rounds, a barrier race, spool vs
  inbox scan, a lock held past the busy timeout and an isolate killed mid-transaction, plus the 200-seed property test. I found no path
  that loses or duplicates a committed financial record on a crash.
- **Merges never destroy data.** Only NULL fields are filled. User-verified and soft-deleted targets only get attached to. User-confirmed
  input is never auto-merged (it returns `possibleDuplicate` and writes nothing). `confirmed_count` is never changed.
- **The 50 s headless budget.** Parsing runs outside the transaction, each batch is at most 20 entries (the use case caps at 100), no
  batch starts with less than 5 s left, background bodies are at most 4,000 characters (spool decode, Guard and parser caps), and
  candidate reads are indexed and capped at 100. I found no unbounded loop or allocation on the background path.

## Findings

### F1 Medium, before merge: a single Guard-invalid DB row makes the drain drop and ack every always-capture and custom-template message

`ingest_raw_messages.dart` l.239-255 handles the case where `buildGuardUserConfig` fails by falling back to
`CaptureGuard(base)` with `baseOnly: true`. The base-only path then re-adds only the user's **ignore** rules (l.290-305). It does not
re-add the user's **keeps**: `capture_senders.always_capture` and the custom-template senders. The base Guard drops those senders as
`not_financial`/unknown (l.287-289). The outcome is `IngestDropped`, the delivery id is in `ackable`, and the cycle acks it, so the
spool entry is deleted (`ingestion_cycle.dart` l.217). The native Guard keeps the old user file in force when a rebuild fails
("never truncated", `guard_user_config.dart` l.64-65), so it keeps capturing these messages, and the drain destroys them.

The builder fails on any one invalid row or cap overrun. One trigger is reachable today. `ignore_rules.last4` accepts 2-4 digits
(`financial_c.drift` l.160-161), `CaptureControlsDao.addIgnoreRule` doesn't narrow that, and the builder accepts exactly 4
(`_last4Shape`). Other triggers are more than 1,000 ignore rules or more than 200 user senders.

My probe used an always-capture sender `COOPXYZ` with 3 confirmations, plus one rule `otherbank/12/sms` for an unrelated bank:
```
bad=false body="Coop: 50.00 deducted"              -> review
bad=true  body="Coop: 50.00 deducted"              -> dropped not_financial  ackable=[x20]
bad=true  body="You paid EGP 50.00 at Synth Cafe"  -> dropped not_financial  ackable=[…]
```
The user explicitly asked for these messages to be captured, and they are deleted without any review item. This breaks self-check
item 1 ("never destroy data on doubt"). The existing test (l.655-675) proves only the ignore half of the fallback.

**Required change:** in base-only mode, honour the user's keeps as well as the ignores. Either:
- build the user part from the sender rows alone and leave out the invalid ignore rows, which the per-message DB check covers already;
- or, when the base Guard drops a message whose `senderKeyOf(channel, source)` matches a `capture_senders.always_capture` row or a
  custom-template sender from `ctx`, treat it as a keep.

Add a test with the 2-digit rule plus an always-capture sender that asserts the message is stored and that the ignore rule still drops
its own card. Separately (FU, owner T-049/T-142 or whichever task writes ignore rules), refuse to create 2-3 digit `last4` ignore rules,
or let the builder accept 2-4 digits on both sides, so the fallback is rarely needed.

### F2 Medium, before merge: one entry that fails without a transient error blocks the whole spool for good

The native `drainSpool` returns the **oldest** pending entries first, and it returns them again after a batch that wasn't acked
(`SpoolHost.kt` l.67-88, same engine claim). The use case fails the **whole batch** on `INGEST_INTERNAL` (any exception outside the
message-level list, l.354-361, l.145) or `INGEST_MSG_UNSTORABLE`. The cycle keeps those entries and stops on "only seen ids"
(`ingestion_cycle.dart` l.159-163, l.189-195), and the worker does not re-enqueue. On every later cycle and app open, the same oldest
20 entries are drained first and fail again. So one poison entry blocks itself, the up to 19 good messages in its batch, and every
message behind it. The spool caps at 500 entries (`SpoolStore.MAX_ENTRIES`). After that, new SMS and notifications are refused
(`SPOOL_FULL`), and notifications have no inbox catch-up, so financial records are lost.

The trigger is a defect, for example a future post-persist hook (T-089 pairing/FX/settlement plugs in at l.1126-1136) or a categorizer
(T-075) throwing a `StateError`/`RangeError` on some message shape. The test "an unexpected error fails the whole batch" shows the
rollback, but no test drains past it. The spike stored such a message for review ("the parser never sees it twice"), so this is a
regression in resilience.

**Required change (cycle or use case, about 20 lines):** after a batch fails without a transient error and has more than one entry,
retry its entries one per call and ack the ones that commit. A single entry that still fails with `INGEST_INTERNAL` should be stored
as raw `review` + `unrecognized` (`reason: ingestFailed`, code only) in its own transaction, as §10 does for message-level errors, and
acked. Only `CONFIG_INVALID` should leave entries stuck. Add a cycle test: a poison entry at the head plus 25 good entries → 25 stored,
and the poison entry is either quarantined or the only stuck entry.

### F3 Low: a spoofed registry sender now has transaction, account and balance effects (extends FU-084)

Before T-046, a spoofed SMS (an alphanumeric sender ID such as the bank's, sent through a grey-route gateway) produced only a raw row.
Now a body that matches a template:
- is auto-saved as a posted transaction, with no review item unless `needsReview` (l.662-692);
- creates an account for every attacker-chosen last-4, with no limit and no signal (l.630-641, T-045 `resolve`);
- overwrites the shown balance, because the newest `asOf` wins and the parser accepts a message date up to 3 days ahead
  (`parsing_pipeline.dart` l.366-369), so a spoof dated receipt + 3 days pins a fake balance for 3 days (l.1099-1124);
- can change a real pending transaction by up to 5 % and mark it posted (l.835-892);
- can move a real notification transaction to an attacker-named card account, and fill its merchant, counterparty and reference
  (l.744-805).

Nothing leaves the phone. The impact is on-device integrity and phishing credibility: a "you were charged EGP 50,000" smish shows up as
a real transaction and fires budget alerts. This is the accepted FU-084 residual class.

**Follow-up (FU-084, owners T-038/T-039/T-041, plus T-045/T-047 for the signal):** add the per-sender rate limit (FU-084 b). Mark an
account auto-created by background ingest as "new card found" in review. Cap auto-created accounts per institution per day. Consider
clamping a balance `asOf` to `min(occurred_at, received_at)`.

### F4 Low: user-confirmed bodies are not capped in the use case

The spool path is capped at 4,000 characters, but `userConfirmed` (share, paste, OCR, PDF, CSV text) is not, and the use case doesn't
cap it either:
- `ParsingPipeline.parse` returns `bodyTooLong` **before** stage 0 (`parsing_pipeline.dart` l.41-43, then l.53-62), so an over-long
  paste is stored whole in `raw_messages.body` as `review` with no OTP or drop-pattern check (l.429-445).
- `bodyHashV1` spreads the UTF-8 bytes into a growable `List<int>` (`body_hash.dart` l.82-88), which uses about 8 bytes per byte. A
  multi-MB PDF or CSV text costs tens to hundreds of MB on the UI isolate.

The input is user-initiated, so this is not a remote threat. The implementer noted it as a residual for the callers.

**Follow-up (owners T-049/T-052/T-076, plus T-046's own FU):** reject over-long user-confirmed bodies in the use case with a code
outcome and no raw row, or store only up to the cap after stage 0. Feed `sha256` through a chunked sink instead of building a list.

### F5 Low: the base-only Guard is rebuilt on every batch

In base-only mode a new `CaptureGuard(base)` is compiled on **every** batch (l.255; only the full guard is cached), and each kept
registry message needs an extra `isIgnored` query inside the write transaction. With a 5,000-entry base this repeats the regex compile
on every batch of the 50 s budget. **Follow-up:** cache the base-only guard for the life of the instance, like `_lastFullGuard`.

### F6 Low: the `g_` institution code is a reversible, unsalted 64-bit hash of the sender, and the server accepts its shape

Generic senders are often phone numbers (wallet agents, people). `g_<16 hex>` of `SHA-256("zg.gen.v1"‖0‖senderKey)` can be reversed by
enumerating Egyptian mobile numbers (about 10^10) in seconds. On the phone this doesn't matter, because the label already holds the
sender in clear inside the encrypted DB. But the backend `InstitutionCodePattern` `^[a-z0-9_]{2,32}$` (`SyncIntake.cs` l.30) accepts
`g_…`. If a contribution ever carried `accounts.institution_code` for a generic account, a phone number would leave the device in a
reversible form, against BR-SYNC-04.

**Follow-up (owner T-142):** the on-device contribution filter must send no institution for `g_` accounts, with a test. Optionally the
server could reject the `g_` prefix too.

### I-1 Info: `body_hash` is unsalted SHA-256

Templated bank messages can be enumerated (amount × last-4 × date and time is roughly 10^10-10^12). That is fine today, because the hash
only sits next to the body in the same encrypted DB and backup. If a later retention or dismiss task ever blanks bodies but keeps
hashes for dedupe, or the hash reaches diag or an export, switch to HMAC under a key derived from the DB key, with a re-hash migration
as database-schema §2.2 already requires.

### I-2 Info: candidate reads are capped at 100

`crossChannelCandidates` and `statusCandidates` use `LIMIT 100` (`drift_ingest_store.dart` l.24). More than 100 same-key rows within
±24 h, for example from a spoof flood, would silently shorten dedupe. Harmless today. The F3 rate limit covers it.

### I-3 Info: user-confirmed input bypasses ignore rules

This is by design (platform-channels §2.1). Copy for T-049 should not imply that ignore rules apply to shares.

### I-4 Info: a soft-deleted cross-channel target still gets the new balance recorded with `sourceTxnId` = the deleted id

This is acceptable, because the balance is real. T-047 should check that the balance view doesn't link to a deleted transaction.

## Follow-ups to file (Lead)

| Item | Severity | Owner suggestion |
|---|---|---|
| F1 2-4-digit `last4` parity between `ignore_rules` and the Guard builder | Low (after the F1 fix) | task that writes ignore rules / T-035 FU-097 |
| F3 spoof effects: new-card signal, account-creation cap, balance `asOf` clamp | Low | FU-084 (T-038/T-039/T-041, T-045/T-047) |
| F4 user-confirmed body cap and streaming hash | Low | T-049, T-052, T-076 |
| F5 cache the base-only guard | Low | T-046 FU |
| F6 contributions never carry `g_` institutions | Low | T-142 |
| I-1 to I-4 | Info | as noted |

---

## Re-review (delta) — 398fc8c..ff6aea7

Reviewer: security-privacy-reviewer (delta only; analyze clean, ingestion/categorization tests green on the merged tree).

- **F2 (poison blocks the spool): resolved.** Good messages behind a poison one are stored and acked. The poison one is stored for review with payload `{reason: ingestFailed, code: <fixed code>}` and acked. `_guarded` maps every error to a fixed `IngestBatchFailed` code and never carries error text. The diagnostics added are counters only (`ING_QUARANTINED`, `ING_KEPT`). Quarantine runs the Guard re-check, stage-0 drop and dedupe 1 first, so an OTP is never persisted by this path. An entry unstorable even alone is never deleted and never acked; it does not block others (residual cost: one failed batch per cycle until T-041 per-entry quarantine, which I accept as Low/Info). A transient failure returns RETRY with nothing acked, and committed messages are duplicates on redelivery.
- **F1 (Guard fallback dropped the user's keeps): resolved.** When the user part can't be built as a whole, the fallback drops only rows the builder rejects individually, still builds the Guard with the valid rules and senders, applies the database ignore check to every registry keep (`dbIgnoreCheck`), and keeps a user "always capture" sender in Dart when the base Guard says not financial. The probe passes, and ignore rules are still enforced. The Guard cache is keyed by the user-part bytes (content), so a rule change yields different bytes and cannot serve a stale guard.
- No new Medium or higher finding. No body, sender, amount or last-4 enters payloads, results or logs in the new code.

**Verdict: APPROVED**
