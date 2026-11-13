# Batch 14 review (batch/2026-11-13-14)

Reviewer: one `code-reviewer` (Opus), code and security (CLAUDE.md §6 cost rules: production diff per task, AC→test maps, riskiest tests read, the rest run). Ran in `app/`: `flutter test test/features/backup test/features/gold test/features/security test/features/ingestion test/features/budget test/features/notifications` on the merged batch tree: **423 passed** ("All tests passed!"). Kotlin and Swift were not compiled here. The Lead reports app-ci and the iOS db-platform job green on `ci/T-103-b`.

## Verdicts

| Task | Class | Verdict |
|---|---|---|
| T-149 Backup snapshot and restore swap | C4 | APPROVED |
| T-144 Entitlement verification, trusted time | C4 | APPROVED |
| T-103 App lock (rework only) | C3 | APPROVED |
| T-076 Re-parse job | C3 | **CHANGES_REQUESTED** (1 major) |
| T-095 Budgets and threshold alerts | C2 | APPROVED |

---

## T-149 Backup snapshot and restore swap (C4, overwrites user data) — APPROVED

Traced: `snapshot_db.dart` (buildSnapshot, stageRestore, carryDeviceState, swapIntoLive), `backup_snapshot_service.dart`, `backup_contents.dart` (decoder), `snapshot_tables.dart`, `backup_cipher.dart` additions (`newFileId`, `fileId`, `storeRestoredKey`), `secure_state_key_slot_store.dart`, providers, `schema_shape.dart` (what `validateSchema` compares), docs. Read the crash/abort tests (`backup_restore_test.dart:395-488`).

Checked and sound:
- **Live DB is untouched until one transaction.** Before step 7, the only connections to `zaghlol.db` are read-only (`buildSnapshot`, and the `BEGIN … COMMIT` read in `carryDeviceState`). `swapIntoLive` is the only writer: the SQLite backup API holds the destination write lock from the first step to the end, and in WAL the whole copy is one commit frame (spilled frames without a commit marker are ignored on recovery). The test with a file copy taken mid-swap opens as the old DB, and the aborted swap rolls back. Page size and `user_version` are checked on both sides before the copy. No file rename, so the T-165 F4 exclusion flag on the sandbox root is safe.
- **Crash at every step:** the pre-swap steps write only into `<temp>/zaghlol_backup_work/`, which is swept under the in-process lock at the start and end of every operation. A crash after the commit leaves slot ≠ secret → `keyMismatch` → `recoverWithPassphrase`. Tested.
- **Encrypted work files only:** the snapshot body is SQLCipher pages under K_snap (a body that starts with the plaintext magic is refused before a byte is written). Stage is under K_db. `temp_store = 2` (memory), so VACUUM and sorter temp files never reach disk. Journals are encrypted by the codec; `-shm` holds only the WAL index. `settings.json` and the manifest stay in memory. The AC2 privacy scan runs after every step and every output chunk.
- **Newer schema is refused before the KDF** (`cipher.open(maxSchemaVersion:)`), and again by `user_version` inside the snapshot (defence in depth).
- **Restored-data validation:** `user_version` = authenticated header, `integrity_check` (CHECKs included), `foreign_key_check`, device tables empty, row counts = manifest, settings = `settings.json`. Then migration and `validateSchema: true`. `schemaShapeOf` includes triggers and views (the `default:` branch), so a foreign trigger or view fails the staged open. That happens before `carryDeviceState`, the first write that could fire a trigger. Checked once more after the migration.
- **Device state:** `secure_state` (entitlement, trusted time, tokens), outbox, diag log, `db_meta` and the catalog stay with the device. A restored backup can't carry Gold or keys. The `snapshot_tables_test` makes every new table pick a side.
- **Deviation (copy under this device's existing K_db instead of a fresh K_db): accepted.** The security goal of "fresh K_db" is that the source device's key never travels, and it doesn't (the snapshot is under K_snap, re-encrypted into stage under the target's key). A Keystore key swap and a file swap can't be made one atomic step, so the transactional page copy is the safer choice. On a new phone K_db is fresh anyway. security-model §5 states this. No re-key is needed for any threat in the model.
- Isolate path (`isolateRunner`) is exercised for both backup and restore in AC1. Errors are code-only. No logging, and the CI grep now covers `backup/application` and `backup/data`.

Findings:
1. **minor / Low** `snapshot_db.dart:307-398` + `:412` (residual, design note §6(c)): device-table writes between the carry-over read and the swap commit are lost. That now includes T-144's `trusted_time` record (a `tampered = true` set in that window would be undone) and `outbox` rows. The impact is small (restore is modal and takes seconds; a lost `tampered` flag only matters if the clock was changed during the restore). Required (follow-up, owner T-150): the restore flow pauses the entitlement tick, sync and capture ingestion for the duration. Optionally, `carryDeviceState` could record `max(updated_at)` of `secure_state` and `swapIntoLive` could re-check it on the destination connection right before the copy.
2. **minor** `backup_snapshot_service.dart:304-308`: only `BackupCryptoException` from `storeRestoredKey` maps to `keyStored = false`. Any other throw after a successful swap (a platform error that escapes `_guardStore`) would surface as a restore *failure* even though the data was replaced. Required (follow-up): catch `Object` there, since after the commit the outcome must always be "restored".
3. **nit** `snapshot_db.dart:437-442`: a `swapFailed` thrown by the post-commit `user_version` check would also report failure after a successful commit. It can't happen given the pre-checks, but the comment should say it is post-commit.

Negative proofs (3, as listed in the task file) cover the EC-26 early refusal, swap atomicity and work-dir privacy. No more needed.

---

## T-144 Entitlement token verification, trusted time, offline bound (C4) — APPROVED

Traced: `entitlement.dart`, `trusted_time.dart`, `time_anchor.dart`, `gating.dart`, `response_signature.dart` (`verifyDetached`), diag codes. Checked against backend-api §4.3 *App rules* and *Trusted time*.

Checked and sound:
- **Only `applyVerified` reaches Gold.** `NotifierEntitlementSink` maps only `active`/`grace` to `applyVerified(verified: true)`. `applyNonGold` refuses Gold phases. `isGold` derives from the phase. `debugOverride` is gated by `kDebugMode`.
- **`verifyDetached`:** same P1363 primitive as `verify` (64-byte r‖s, range-checked). The kid must match the key-id pattern and the `e` prefix. Dev kids are refused unless `allowDevKeys`. Unknown kid, wrong purpose or a bad signature return false. The signed message is the exact `header.payload` ASCII.
- **JWS header whitelist** {alg=ES256, kid, typ}. `crit` or any other key is refused. Strict base64url (no padding, regex). 16 KiB cap. Payload is parsed only after the signature verifies. Claims are type-checked (`iss`, `v`, ints, `src` list) and the D-60 lifetime rule is checked for active/grace. Account tokens come from the same `e` ring, as backend-api §4.3 says. Tokens can't be confused across types (an entitlement token has no `iid`; an account token has no `status`/`plan`/`src`).
- **Binding:** `sub` == install ID (exact string), at store time *and* at every `evaluate`. Account `iid` == install ID. `acct` is honoured only with an unexpired, bound account token whose `sub == acct`. A mismatch increments only a diag code with no fields, and the token is not stored. With a failed binding, `bindingOk = false`, so even an own fresh echo only raises. AC tests for R5-1 are present.
- **Nonce (R4-2):** 16 bytes from `Random.secure()` (injectable). Kept in memory only. One outstanding, replaced by each `run`, which is serialized with `onResponse` inside the critical section. Fresh echo = same nonce + same boot + ≤ 60 s monotonic. Single use (`consume`). Re-registration clears it. Withheld, reused, older and Idempotency-replay echoes only raise.
- **Trusted time (R3-1/R4-3):** the three interval classes match the contract. The tamper test uses the uncharged `lb + lower − 10 min`. The 6 h charge goes to `hw` only. `lb = max(lb + lower, w)` unless the test failed. Compare-and-set with retries. An unreadable record counts as `tampered`. A `iat` more than 10 min ahead of `hw` after anchoring is dropped. An older `iat` never replaces a newer cached token.
- **Fail closed:** `releaseEntitlementKeys` is empty, so nothing verifies and the user stays Free. `entitlementServiceProvider` throws until T-143 wires it.
- **Builder's open point** (a wall clock that is still wrong after a fresh echo stays `tampered`): **acceptable.** This is exactly what the contract specifies ("forward jump, then an honest correction: expires early, recovers online", and the tamper test is against `w`). It fails closed, and the alternative (judging against a server offset) is a contract change. It is a UX gap, though. See finding 3.

Findings:
1. **minor / Low** `trusted_time.dart:196,207` (`_initial` when the record is absent): a missing `trusted_time` record starts fresh at the wall clock, not `tampered`. In normal use the record always exists before a token is cached (`handleBody` advances first), so "token cached but no record" can only come from editing `secure_state` (rooted device with the DB key). Required (follow-up): in `EntitlementService.evaluate`, treat "cached token present and no trusted-time record" as `tampered` (or have `TrustedTime` take a `hasToken` hint), with one test.
2. **minor** `entitlement.dart:386-417`: `evaluate()` from the 60 s timer can interleave with `handleBody`'s `evaluate()`. The slower one publishes last, so a stale phase (for example `free` right after a new token was stored) can show for up to one tick. Required (follow-up, T-143 wiring): serialize `evaluate` (same `_serial` pattern) or drop results older than the last published one.
3. **minor (UX, follow-up for T-146)**: when `tampered` persists right after a fresh echo, the user is online and "connect to check Gold" is misleading. T-146 should show "set your phone's date and time to automatic" in that case. `EntitlementService` can expose "tampered despite a fresh echo in this session".
4. **nit** `entitlement.dart:556-560`: if `reanchor` loses the CAS four times, `consume()` still runs and the returned state is the other writer's. That is harmless (a nonce lost is only a missed re-anchor), but a comment would help.

---

## T-103 App lock — rework only (C3, security) — APPROVED

Scope: `git diff 45f1db8 origin/task/T-103-app-lock` (local_auth removed, Pigeon `authenticate`, `DeviceSecurityHost.kt/.swift`, `HostAppAuthenticator`, PrivacyCover scene notifications, `SceneDelegate` override removed). The rest stays as approved in batch-13.

Checked and sound:
- **No error becomes success.** Dart: only `NativeAuthOutcome.success` maps to `AuthOutcome.success`, and any exception maps to `failed`. Android: `SUCCESS` only from `onAuthenticationSucceeded`. `fromError` maps every code to cancelled/locked/notAvailable/failed. `canAuthenticate` ≠ SUCCESS maps to notAvailable. A `RuntimeException` in the host maps to `FAILED`. iOS: `.success` only when `ok == true`. Every `LAError` (and a non-LAError) maps to a non-success outcome.
- **Authenticators:** STRONG|DEVICE_CREDENTIAL on API 30+, WEAK|DEVICE_CREDENTIAL on 26–29 (the AndroidX-supported combination). No negative button with DEVICE_CREDENTIAL. iOS uses `.deviceOwnerAuthentication` (passcode fallback, A-08). The prompt never carries platform text back across the channel.
- **PrivacyCover:** observes `UIScene.willDeactivateNotification` / `didActivateNotification` on `.main` with weak self. Observers are added once and removed on disable. Flutter's own scene lifecycle forwarding is untouched (the likely cause of the simulator hang). The cover is shown before the switcher snapshot.
- `local_auth` and its platform interface are gone from pubspec and lock. `NSFaceIDUsageDescription` is present.

Findings:
1. **minor** `DeviceSecurityHost.kt:130,154`: `prompting` is set before `prompt.authenticate(info)` and cleared only in the callbacks. If `authenticate` throws (the host maps it to FAILED), or if AndroidX returns silently without a callback (`FragmentManager` state already saved), `prompting` stays true, and every later unlock on that activity returns CANCELLED until the activity is recreated. Required (follow-up): wrap the construction and `authenticate` in try/catch and reset `prompting` on throw. Only call it while the activity is at least STARTED.
2. **minor** `DeviceSecurityHost.swift:51`: the `LAContext` is a temporary with no strong reference held for the duration of `evaluatePolicy`. In practice the framework keeps it alive, but Apple's samples keep the context in a property, and a deallocated context cancels its evaluation (`.systemCancel`/`.appCancel` → `cancelled` → the user can't unlock). Required (follow-up, verify on a device in the T-180 device list): keep the context in a property until the reply arrives.

---

## T-076 Re-parse job (C3) — CHANGES_REQUESTED

Traced: `reparse.dart`, `IngestRawMessages.reparse` / `_reparseOne`, the `existing` branch of `_insertRaw`, `DriftIngestStore.rawsToReparse/promoteRaw/txnOfRaw`, and the paths `_persist` reaches from a re-parse (`_parsed` dedupe 2, pending/settled, `_attach`, `_settle`).

Checked and sound:
- Selection: background channels only (share/paste/OCR/PDF/CSV never). `review`/`parsed` rows with an older `registry_version`, plus `reparse_pending`. Keyset paging, 5000 cap.
- Parsed-row path: writes only when the target transaction is live, not user-verified, not deleted, not paired/internal, and has the same direction, status and amount. Then the conditional stamp (`WHERE parse_status = ?`), then `_attach`. A lost condition throws `_RaceLost` inside the savepoint, so nothing is written.
- Review/pending path: the same raw row is promoted conditionally (resolving its open review items) before any transaction write, and any `_persist` outcome other than inserted/merged/balance rolls the savepoint back. Concurrency: two jobs convert once (test).
- No body in any output: `StoredRaw.toString`, the summary and the diag codes are fixed or count-only.

Findings:
1. **major** `ingest_raw_messages.dart:437` (`_reparseOne` → `_persist`) → `:987-1031` (pending/settled) → `_settle` `:1253-1268`: a `review`/`reparse_pending` row that now parses as a **settled** expense runs the normal pending/settled merge. `statusCandidates` doesn't exclude user-verified rows, so the re-parse:
   - changes the **status** of a **user-verified** pending transaction to `posted` and can add a `settledAmountDiffers` review item, which breaks the task's "never touch user-verified transactions" (AC2) and the "no review items from a re-parse" rule in the design note; and
   - **changes the amount** (and `dedupe_key`) of an unverified pending transaction, which breaks the Lead's rule that a re-parse never changes amounts.
   
   This is reachable in a realistic case: a pending card hold was captured, its settlement SMS used a new format (review), and an app update now recognises it. No test covers it (AC2 tests only cover the parsed-row path). Required:
   - for `MessageOrigin.reparse`, the pending/settled merge must not write a user-verified or deleted target and must never change an amount. The simplest fix is to skip the merge in re-parse mode: leave the row in review (stamp) whenever a pending/settled pick exists;
   - apply the same guard to the cross-channel branch (`_attach` already skips user-verified/deleted targets for field writes; keep that);
   - add tests: (a) a review settled message with a user-verified pending match leaves that transaction byte-identical and creates no review item; (b) an unverified pending match keeps its amount.
2. **minor** `ingest_raw_messages.dart:1108-…` (step 12): a review row converted through `_parsed` → `IngestInserted` can still create `possibleDuplicate` / `needsReview` review items. So "a re-parse never creates review items" (the design note and the `reparse` doc comment) is not true. FU-109's personal-origin concern doesn't apply (personal unparsed messages are never stored as review), so the behaviour is acceptable. Required: fix the doc comment and the design note (self-check §6), or suppress step 12 in re-parse mode. Fixing it together with #1 is fine.
3. **minor** `ingest_raw_messages.dart:1193` (`_attach`, parsed path): `accountId: moveTo` moves the transaction to the card account when the target has no last4. That is the attach rule, but it is more than "only NULL fields filled" and changes which account's totals the transaction counts in. Required: state it in the design note, or skip the account move in re-parse mode (Lead's call).
4. **minor** `reparse.dart` / `_reparseOne`: review rows whose `_persist` result is rolled back (`_RaceLost` for a non-convert outcome) are never stamped, so they are parsed again on every start until the next registry bump. That costs CPU, not correctness. Follow-up: stamp them in a separate statement after the rollback.

---

## T-095 Budgets and threshold alerts (C2) — APPROVED

Traced: `budget_progress.dart`, `budget_alert_service.dart`, `budget_mapper.dart`, `FiredAlertsDao.unmarkFired`, `NotificationService.notify` (FU-133).

Checked and sound:
- **Per currency, never summed:** `budgetSpent` reads only `totals[spec.limit.currency]`. Rollover uses `Money +`, which refuses mixed currencies. Integer percent (`~/`). There is no `double`. "EGP budget ignores GBP spend" is tested.
- **One alert per threshold per cycle:** the dedupe claim is the unique insert in `fired_alerts`. When several thresholds are crossed at once, the lower ones are claimed silently and only the top one alerts. "80 % crossed twice alerts once" is tested. Zero or negative effective limit gives no percent and no alert (EC-24).
- **FU-133:** the claim is released only after the gateway throws, and the error is rethrown. Only the call that won the claim can reach the release (a loser returns before the gateway), so the unconditional delete by key can't remove someone else's live claim. A concurrent caller during the failed attempt is deduped (it isn't lost forever: the next evaluation re-alerts). Tested.
- Redaction (Q-33): the service passes the caller's redacted title and body. Category name yes, amounts no, as the caller's l10n supplies them (same contract as T-094, nit 3 there).

Findings:
1. **minor** `budget_progress.dart:26` / `budget_alert_service.dart:43-80`: `BudgetSpec.annual` is never read. `run` applies one `cycle.key` to every spec, so an annual budget (FR-BUD-06) passed with a monthly cycle would alert once per month and count monthly totals. Required (follow-up, owner T-098 or whichever task wires the job): `run` skips specs whose `annual` flag doesn't match the cycle kind (or the caller splits them), with one test.
2. **minor** `budget_mapper.dart:12`: `Money.fromStorage` throws on a corrupt row, so one bad budget stops the whole alert run. Follow-up: use `Money.tryFromStorage` and skip the row (T-012 F6 rule).
3. **nit** `notification_service.dart:91`: if `unmarkFired` itself throws, its error replaces the gateway's. That's acceptable, but a comment would help.

---

## Fix list (blockers and majors only)

| Task | Lane | Severity | Finding |
|---|---|---|---|
| T-076 | A — App core/data (flutter-core) | major | Re-parse of a review/pending row runs the pending/settled merge: it writes status to user-verified pending transactions (plus a review item) and changes amounts of unverified ones (`ingest_raw_messages.dart:437` → `:987-1031` → `_settle :1253`). Skip or guard the merge in re-parse mode, plus 2 tests. Fix minor #2 (doc) in the same pass. |

Follow-ups to record in `docs/implementation-status.md` (non-blocking): T-149 #1 (T-150 pauses tick/sync/capture during restore), #2 (catch-all after commit); T-144 #1 (absent record + cached token → tampered), #2 (serialize evaluate, T-143), #3 (clock copy, T-146); T-103 #1 (`prompting` reset), #2 (retain `LAContext`, device check); T-076 #3, #4; T-095 #1 (annual vs cycle), #2 (`tryFromStorage`).
