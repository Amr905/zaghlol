# Batch review — batch 15 (`batch/2026-11-13-15`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus), code and security in one pass (PO cost rule 4) |
| Date | 2026-11-13 |
| Diff | `git diff origin/main...origin/<task branch>` per task; merged tree `de04cdd` |
| Tests run | `flutter test test/features/backup test/features/categorization test/features/transactions test/features/recurring test/features/onboarding test/features/ingestion/data`: **357 passed**. `dart test` in `packages/zaghlol_domain`: **292 passed**. Plus one scratch probe of `matchPayment` (not committed), see T-096 F1. |

| Task | Class | Verdict |
|------|-------|---------|
| T-150 Google Drive appDataFolder backup backend | C4 | **APPROVED** |
| T-142 Merchant contribution opt-in and outbox | C4 | **APPROVED** |
| T-090 Refund matching and offset links | C3 | **APPROVED** |
| T-096 Subscriptions, installments, gameya, card dues | C3 | **CHANGES_REQUESTED** |
| T-097 Contextual setup suggestions | C2 | **APPROVED** |
| ci: db-platform iOS retry | Lead | **APPROVED** |

---

## T-150 — Google Drive appDataFolder backup backend (C4, deletes user data)

**Verdict: APPROVED**

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Android backup restores on iPhone via Drive | PASS (host) | `drive_backup_service_test` "AC1: Android backup uploaded to Drive restores on the other phone". The real Drive/iOS leg needs the OAuth clients (PO, design note §8b). |
| Partial upload never replaces the previous backup | PASS | store "AC2: Drive bytes differ (MD5)…", "AC2: interrupted upload creates nothing…", "rename that does not land…"; service "AC2: an interrupted upload…", "AC2: Drive stored different bytes…" |

### What was checked (production code read in full)
- **Prune only after a verified upload.** `backupNow` runs `prune` only after `upload` returned an entry whose create response and rename response both match local size + MD5 (`drive_store.dart:343-368`). Null `size`/`md5` from Drive count as a mismatch. The local MD5 is computed over the same single read that `verifyFile` decrypts, and `read != written` is refused (`drive_backup_service.dart:224-241`).
- **Never deletes the new / newest backup.** `planPrune` (`drive_store.dart:148-200`) returns null unless the listing holds exactly one row with `protect`'s id, name, size and MD5; keeps `protect`, the newest `keep` (≥ 1) by Drive's `createdTime`, and everything created at or after `protect`. Undated files are never deleted. Two phones with keep 1 end with the newest one (traced).
- **Foreign names.** Only `^zaghlol-backup-<d>-<d>\.zaghlol\.enc(\.partial)?$` from an `appDataFolder` listing are candidates; `delete` re-lists and requires id + name to match.
- **Listing errors.** Any page error → `PruneReport(skipped)`; repeated token or 20-page cap → `listTooLong` → skipped; a non-404 delete error stops pruning.
- **`.partial`.** Resumable create means a partial exists only once complete; swept only when its server `createdTime` is ≥ 24 h before `protect`'s (no device clock). A mismatched partial of our own is deleted at once.
- **Only ciphertext leaves.** The temp file holds the T-149 encrypted stream; the staging dir is wiped before and after every run.
- **Token.** `accessToken` is read from the authorization object and only returned; the `GoogleSignInClientAuthorization` is never interpolated. `BearerClient.toString`, `DriveFile.toString`, `DriveBackupEntry.toString` hide values; `DriveBackupException` carries a code only; server messages are dropped in `classifyDriveError`. No logging anywhere.
- **`seq`.** `max(stored, highest listed final label ≤ 2^40) + 1`, stored after the rename in device-only `secure_state`; a restored phone continues above the old phone's numbers. Equal `seq` from two phones at once can't collide on name (createdAtMs differs) and is harmless.
- **Scope.** Only `drive.appdata` requested; every adapter call pinned to `appDataFolder` (adapter tests check the request). Missing client IDs fail closed (`notConfigured`). No native files changed; app-ci green on `ci/T-150` per the Lead.
- **Lead-accepted residual:** count-based retention may remove an old-passphrase backup once a newer verified one exists (design note §8a).

### Findings
| # | Severity | Security | File:line | Issue | Required change |
|---|----------|----------|-----------|-------|-----------------|
| F1 | minor | — | `app/lib/features/backup/data/drive_store.dart:424` | `download` only connects through `_Session.call`; a 401 on the media GET is not refreshed and retried as design note §7 says ("A 401 clears the token and retries the operation once"). A restore with a just-expired token fails with `authExpired` (an "internal" code) instead of retrying. | Follow-up: wrap the first-byte fetch in the refresh path, or map `authExpired` to `authorizationDenied` at the public boundary. Owner T-152 / FU-139. |
| F2 | minor | Info | `app/lib/features/backup/data/drive_auth.dart:29-34` | Cross-platform restore (AC1) works only if the Android, iOS and server OAuth clients are in **one** Google Cloud project: `appDataFolder` is per project. Also iOS needs the reversed-client-ID URL scheme before the define is set. | Add both to the PO setup note in §8b / the release checklist. No code change. |
| F3 | nit | — | `app/lib/features/backup/application/drive_backup_service.dart:89-111` | `list`, `upload` and `prune` take the store lock separately, so a settings `delete` can run between them. Safe today (prune re-lists and re-proves `protect`), just not the "one operation" the comment implies. | None required; reword the comment if touched. |

---

## T-142 — Merchant contribution opt-in and outbox (C4 privacy)

**Verdict: APPROVED**

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Payload contains no amount/date/card/phone/IPA/person name | PASS | Payload is built only from generated `ContributionInput.toJson()` = `{merchantNorm, institutionCode, categoryCode}` (`api_models.g.dart:609-613`); `contributions_test.dart` privacy-contract cases |
| Opt-out deletes queued rows | PASS | `setOptIn(false)` writes the setting and `deleteKind('contribution')` in one transaction; test checks other outbox kinds survive |

### What was checked
- Opt-in defaults to `false` (`settings_keys.dart:149`), checked before filtering and **again inside the enqueue transaction**; settings live in the same SQLCipher DB, so the re-check is transactional.
- Filters (`outbound_text_filter.dart`): `@`/`＠`/`﹫`, `+` then a digit, 5-digit runs in any script (`\p{Nd}\p{No}`, up to 3 non-letters between digits, `Cc/Cf/Mn/Me` stripped first); length 2..64; institution and category code regexes; person transfer; custom/unknown category (no `system_code` row); first-name / capitalized-words heuristic on both `merchantNorm` and `displayName`. `displayName` is never stored.
- Opt-out deletes only `kind = 'contribution'` rows. Nothing outside BR-SYNC-03/04 is added; no new API field, no schema change, no logging.

### Findings
| # | Severity | Security | File:line | Issue | Required change |
|---|----------|----------|-----------|-------|-----------------|
| F1 | minor | Low | `app/lib/core/settings/settings_providers.dart:41`; `app/lib/features/categorization/application/contributions.dart:257-262` | Nothing calls `ContributionQueue.offer` or `setOptIn` yet. The generic `contributionOptInProvider` (`settingProvider`) can write the key directly, and a Settings toggle built on it would turn the opt-in off **without** deleting the queue (EC-48). The sender must also re-check the opt-in before each send. | Follow-up (owner: the Settings task that adds the toggle, and T-143 for the sender): the toggle must go through `ContributionQueue.setOptIn`; the sender re-reads the opt-in and sends only `ContributionInput`. Wire `offer` from the "categorize unknown merchant" path. |
| F2 | nit | Info | `app/lib/features/ingestion/data/review_repository.dart:227` | "Request my bank" now uses the shared filter: letters now break a digit run (the old `\D{0,3}` did not), and `+digit` / fullwidth `@` are new refusals. This matches the server rule (security-model §3), but it is a small behaviour change to T-049 outside the listed component. | None; noted for the record. |

---

## T-090 — Refund matching and offset links (C3)

**Verdict: APPROVED**

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Partial refund reduces net spend correctly | PASS | `refund_matching_test.dart` partial cases; `offsets_test.dart` |
| Refund larger than expense → remainder is income | PASS | linked = `min(refund, remaining)`, remainder not linked; EC-17 tests |

### What was checked
- **No over-offset / double count:** remaining = amount − all links, computed inside the same transaction; a refund with any link is skipped (idempotent); schema triggers cap both sides, and a trigger/UNIQUE clash returns `skipped` (rolled back). Same currency, account and non-empty merchant only; nothing converted.
- **Ambiguous → review:** equally recent candidates → `reimbursement_suggestion` item with `type: refund_ambiguous`, ids only; not linked. Opened at most once per refund.
- **Unlink remembered:** a resolved `unlinked` item blocks auto re-link.
- **`onRemoved`:** deletes links on both sides in one transaction, announces both sides' cycles (event computed before delete), resolves the removed row's open items, then lets freed refunds re-match.
- **Shared helper regression (bulk_edit):** `transactionsChangedFor` received the exact link query bulk_edit had; `withLinks` defaults to `true`, so existing callers are unchanged; bulk_edit passes its own flag and merges its extra `accountIds`. Transactions tests green.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| F1 | minor | `app/lib/features/transactions/application/refund_matching.dart` (whole file) | No provider and no caller: `onPersisted` / `onRemoved` are not hooked into ingest, manual save or delete, so no refund is matched in the app yet. | Follow-up: wire on persist/delete (owner T-091 or the ingest pipeline task). |
| F2 | minor | `packages/zaghlol_domain/lib/transfers/offsets.dart:131-139`; `refund_matching.dart:266` | The window is by local **day**, so an expense later on the same day as the refund (after it) can be chosen as its original; the pool also includes `pending` expenses although the note says posted. | Follow-up: require `occurredAt ≤ refund.occurredAt` and decide on pending expenses (T-091). |

---

## T-096 — Subscriptions, installments, gameya, card dues (C3)

**Verdict: CHANGES_REQUESTED**

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Netflix-like history yields one suggestion | PASS | repository detection tests; `recurring_rules_test.dart` |
| Matching payment marks installment paid | PASS | "installment: matching payment marks it paid and advances", "last payment completes a counted item" |

### What was checked
- Detection writes only `suggested` items plus a review item (ids only); confirm/dismiss are conditional on `suggested`; dismissed rows block re-suggestion.
- Auto-mark: `INSERT OR IGNORE` on the occurrence key gives one winner; a transaction pays at most one occurrence (`notExists` on `txn_id`); per currency (`currency = item.currency`, domain refuses cross-currency).
- Date math: Dec→Jan, month-end clamp, `nextDueOnOrAfter` correct (domain tests).
- **Judgement asked by the Lead:** a card due matched by an incoming transfer on the card account is right (a card payment lands on the card). Matching an amount-0 card due "by account only" is **not** safe as built, because the candidate set also includes the card's own purchases (F1).

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| F1 | **major** | `app/lib/features/recurring/data/recurring_repository.dart:405`; `packages/zaghlol_domain/lib/recurring/recurring_rules.dart:282-299` | For a `card_due` the candidates are `expense`, `transfer_out` **and** `transfer_in` on the card account, and `syncCardDues` always creates the item with amount 0, which skips the amount check. So any purchase made with the card (an `expense` on the credit account) within ±5 days of the due date marks the due **paid** and moves it a month on; the reminder is then suppressed and the user can miss the card payment. Confirmed with a probe: `matchPayment(DueItem(amount: 0 EGP, accountId: 'card1'), [PaymentCandidate(45.00 EGP coffee, accountId: 'card1')])` → matches. | For `card_due`, accept only `transfer_in` on the card account (a payment landing on it); never `expense` / `transfer_out` of the card itself. Make the domain rule enforce it too (e.g. a `DueItem` flag "incoming only" / candidate direction), so an amount-0 item can't match an outgoing charge. Add a test: a card purchase near the due date does not mark it paid; a payment to the card does. |
| F2 | minor | `app/lib/features/recurring/data/recurring_repository.dart:368-389` | An occurrence that is never matched (price changed > 2 %, paid in cash, card paid from an unlinked account) keeps `next_due_date` in the past for good: no manual mark-paid / skip exists, so reminders stop after the first miss. | Follow-up (owner T-105, recurring UI): manual "paid" / "skip" that advances the item; or roll past-due items forward with an overdue flag. |
| F3 | nit | `packages/zaghlol_domain/lib/recurring/recurring_rules.dart` (`detectSubscriptions`, `dueDay: last.date.day`) | The anchor day is taken from the latest charge, so a 31st-of-month subscription detected after a February charge anchors to 28 for good. | Follow-up: take the anchor from the most common / maximum day in the chain. |

---

## T-097 — Contextual setup suggestions (C2)

**Verdict: APPROVED**

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Salary on day 25 → «ده ميعاد قبضك؟» once | PASS (logic) | `contextual_test.dart`; rendering is T-104 (`messageKey` only, no strings here) |

Checked: one suggestion at a time in fixed order (payday, budget, backup); each offered once via `setup_suggestions_handled` (marked on show or dismiss); payday 29–31 → 28 (`contextual.dart:89`); no hard-coded user-facing text.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| F1 | minor | `app/lib/features/onboarding/application/contextual.dart:103` | FR-ONB-10 says "free backup after 7 days **of data**"; the code counts 7 days since install, so a user with no transactions yet is still nudged. | Follow-up (T-104): pass the first-data date (or require data) instead of `installedOn`. |
| F2 | minor | `contextual.dart` (`SetupContext.latestSalaryCredit`) | No producer for "salary-like credit": the caller must detect it, and nothing does yet. | Follow-up (T-104): feed it from the ingest salary template event / income heuristic. |

---

## ci: db-platform iOS retry (Lead)

**Verdict: APPROVED**

Checked `.github/workflows/db-platform.yml:264-284`: `perl -e 'alarm shift; exec @ARGV' 1500 …` keeps the alarm across `exec`, so a hang ends the script with 142 (128 + SIGALRM); only 142 triggers the single retry, after `pkill` of the flutter tool and a simulator reboot; any other exit (a real failure) is passed through unchanged; a second 142 fails the job with an error annotation. `set +e` is needed under GitHub's `bash -e`. The device script writes `device.log` with `tee` (truncating), so the key-scan step reads the second attempt's log. Job timeout 75 min covers two 25-min attempts plus setup.

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| F1 | nit | `.github/workflows/db-platform.yml:272` | SIGALRM kills only the outer `bash`; `xcodebuild`/simulator children of the first attempt may linger until the reboot. `pkill` + reboot covers the known hang. | None. |

---

## Fix list (blockers and majors only)

| # | Task | Lane | Severity | Finding |
|---|------|------|----------|---------|
| 1 | T-096 | A — App core/data (flutter-core) | major | F1: card dues (amount 0) are auto-marked paid by the card's own purchases; restrict card-due matching to incoming payments on the card (repository candidate directions + domain rule) and add the negative test. |

All other findings are minors/nits: follow-ups (`FU-###`) with the owners named above; none is "before merge".

## Lead delta check (5f6c572)

T-096 major fixed. Card dues now select only `transfer_in` candidates, and the domain rule skips any candidate whose direction doesn't fit (`item.cardDue != c.inbound`) before the amount-0 shortcut. A card's own purchase can therefore never pay its due, while subscriptions and installments still match outbound payments only. About 12 production lines. The new repository test ("a 45 EGP purchase on the card does not mark the due paid") fails without the fix, and the domain test pins the API. Recurring tests (15) and domain tests (293) pass on the merged head. Verdict for T-096: **APPROVED**.
