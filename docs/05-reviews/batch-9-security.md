# Batch 9 — security and privacy review (T-040, T-184)

Reviewer: `security-privacy-reviewer` (Opus), 2026-11-12. Scope: the two sensitive tasks of `batch/2026-11-11-9` only (CLAUDE.md §6, C4: SMS ingestion; billing/entitlements). The batch code reviewer covers general correctness.

| Task | Diff reviewed | Verdict |
|---|---|---|
| T-040 SMS receiver | `origin/task/T-047-capture...origin/task/T-040-receiver` (head `9913bdd`) | **APPROVED** |
| T-184 Seat service | `origin/task/T-182-seat-proof...origin/task/T-184-seat-service` (head `b4b7bb7`) | **APPROVED** |

No High or Medium findings. No Low is marked "before merge". The Lows and Infos below become follow-ups under the review-round policy.

Checked by running code: `dotnet test Zaghlol.Application.Tests --filter Seats` passes 131/131 on the batch head. A negative proof of the capability IL scan: I added `new AppAttestVerified(...)` in namespace `Zaghlol.Application.Seats`, and `NoProductionCodeOutsideTheRestoreNamespaceConstructsTheCapability` went red. I then reverted the change. I did not run the Kotlin/Android tests or the Testcontainers seat tests in this workspace; those need the PC runner.

---

## T-040 — SMS receiver (multipart, Guard, spool, enqueue)

### What I checked, and the result

- **Spoofed broadcasts.** The receiver in `app/android/app/src/sms/AndroidManifest.xml` is `exported="true"`, which `SMS_RECEIVED` needs. It requires `android.permission.BROADCAST_SMS`. That permission is signature/privileged, and `SMS_RECEIVED` is a protected broadcast, so no app and no `am broadcast` can deliver it. The device script sends a spoofed `am broadcast` and checks that it is denied. The placement check (`.github/scripts/check-sms-spike-placement.sh`) requires exactly one `SMS_RECEIVED` receiver in each `*Sms` APK, protected by `BROADCAST_SMS`. It also requires that no `*NoSms` APK has the receiver or the `SmsReceiver` class. The receiver has no priority and never calls `abortBroadcast`/`setResultCode`, and a source-scan test enforces that. Not direct-boot aware. **OK.**
- **Malformed or oversized PDUs.** `getMessagesFromIntent` runs inside `try`, and a failure yields an empty list (`SmsReceiver.kt:35`). A null body becomes `""`, and an empty or null address is dropped (`SmsAssembler`). Concatenated SMS are limited by the telephony stack (≤ 255 parts) and by Binder. In the spool codec, `require(body ≤ 4 000 chars / 16 000 bytes)` (`SpoolRecord.kt:63`) throws. `CaptureIntake.kt:90` catches it, so the message counts as `failed`, nothing is written and nothing is enqueued. A Guard defect fails closed as `Drop(CONFIG_INVALID)` (`CaptureIntake.kt:120-123`). **OK.**
- **A personal SMS stays inert.** For any `Drop` except `rate_limited`, nothing is written: no file, no directory, no status write, no enqueue (`CaptureIntake.kt:72-75`). The JVM test checks that the whole temp root is byte-identical before and after. The device test compares the data-dir listing (path, size, mtime) before and after; only the test spool may change. On `rate_limited`, the status file gets a count and the earliest time, and nothing else. Staging/prod `*Sms` builds have no Guard base until T-036. There `readForBuild` (`BaseConfigSource.kt:41-45`) throws, the Guard mode is `INVALID`, and every SMS is dropped. The stagingSms device phase shows no spool entry, no Guard file and no WorkManager job. The spike base asset is packaged only in devSms, and the placement check asserts that. **OK.**
- **Raw SMS or amounts in logs, crash output, status or unencrypted storage.** None found:
  - No `Log`/`println`/`printStackTrace` in `platform/capture`, `platform/guard`, `platform/spool` or `src/sms` (app-ci grep extended, plus a JVM source scan).
  - `SmsPart`, `AssembledSms`, `CapturedMessage`, `ReceiveStamp` and `IntakeResult` redact their `toString`.
  - A scan forbids stringifying `SpoolEntry`/`SpoolRecord`.
  - The status file holds counters and times only.
  - Spool entries use the existing AES-GCM Keystore cipher (T-039) under `noBackupFilesDir`.
  - `IngestTrace` gets ULIDs and timestamps only, and its only implementation (the spike latency recorder) is devSms-only.
  - The canary test (`ZG_CANARY_7731` / `ZG_CANARY_SRC`, failing ciphers) and the device logcat scan (filtered by the app uid, with a check that the scan matched app lines) cover the rest. **OK.**
- **Typed Guard channel (FU-101 L-1).** `GuardRuntime.decide(AndroidGuardChannel, …)` is the only entry point. `share`/`apple_pay`/`shortcut_message` (fail-open generic keeps) cannot reach it, and a test pins the enum's wire values. **OK.**
- **Flood resistance.** A spoofed over-the-air SMS flood is bounded by four limits: the per-sender rate limiter, the generic budget and rate, the 80 % SMS share (`SpoolStore.kt:282`, which leaves 20 % for notifications that can't be recovered), and coalesced status writes (`CaptureStatusStore.kt:179-181`). Coalescing writes the first occurrence of each fact at once, then at most one write per 10 s. In memory, a deferred delta holds counts only. `LiveEnqueueGate` limits the queue to one waiting live run, so a burst can't use up the expedited quota. On an unknown state it fails towards enqueueing. **OK.**
- **Play policy.** Only `*Sms` builds carry `RECEIVE_SMS`/`READ_SMS` and the receiver (ADR-004). No `READ_PHONE_STATE`: the SIM slot comes from intent extras or `SubscriptionManager.getSlotIndex`, which needs no permission on API 29+. The text the implementation notes suggest for the T-176 declaration is accurate: SMS are processed in memory and dropped without a write. **OK.**

### Findings

| # | Severity | Where | Finding | Required change |
|---|---|---|---|---|
| T040-L1 | Low | `app/android/app/src/main/kotlin/app/zaghlol/platform/capture/SmsCapture.kt:45-58` | `installForTest` is a public hook in the **main** source set. It sends every live SMS to any `SmsIntake` passed in, so it ships in release builds. Only code in the app's own process can call it, and that code could already read the spool. So it can't be exploited from outside, but a stray call from a plugin or a later refactor would send real bank SMS to another sink. | Follow-up: move the hook to a debug/`androidTest`-only seam, or make it a no-op unless `BuildConfig.DEBUG`. R8 alone is not a guarantee. Add it to the source scan. |
| T040-I1 | Info | `SpoolRecord.kt:63`, `CaptureIntake.kt:90` | A kept SMS longer than 4 000 chars counts as `failed` and leaves no status fact (`firstMissedSmsAtMs` is not set). This is fail-safe for privacy, but nothing shows the loss. The inbox catch-up's watermark − 10 min recovers it only if the catch-up runs. | Optional: call `status.recordMissed("sms", wallMs)` on a write failure (codes only), in T-043 or a follow-up. |
| T040-I2 | Info | Implementation notes, negative proofs 6b and 14 | Both results are **pending** because the runner stalled. 6a already proves the first-alert-at-once path that 6b shares (`addsFactTo`). 14 is about correctness, not security. | The Lead should confirm the `task/T-040-negproof-c`/`-d` runs when the runner reports. This does not block merge. |
| T040-I3 | Info | PC runner | `android-unit` is green on `2faad0f`/`76680a0`. The last two commits (the AC2 on-disk assertion and docs) have no PC-runner status yet. | Covered by the batch CI run. |

---

## T-184 — Seat service (bind / move / rebind / claimants / reclaim / support move)

### What I checked, and the result

- **Stealing a seat or moving it past the cooldown or caps.**
  - Every channel goes through `SeatRules.Decide`, which follows the documented table. The cooldown is checked against the stored `next_move_at` with `now < next` (M2 negative proof). `next_move_at = CeilHour(now + 30 d)`.
  - A rebind needs a `RegisteredSeatKey`, which only registration can issue (internal constructor). Its element 0 must match the install's set-once `seat_key_hash`. A match only counts at **position ≥ 1** (`SeatService.cs:377-387`).
  - The 2-per-30-days cap is computed from the pruned `recent_rebinds`. Successor inheritance copies `recent_rebinds`, so a plan upgrade can't reset the cap.
  - An over-cap rebind at sign-in needs `device_key_trusted`, which is the **holder's** flag. Otherwise it is an ordinary move under the cooldown.
  - The reclaim is single-use: a conditional `UPDATE … WHERE attach_reclaim_used_at IS NULL` (`SeatStore.cs:67-69`). If it affects no row, it throws, so the transaction rolls back.
  - The verify, restore and sign-in channels check the account rule first. **OK.**
- **Forging trust (`AppAttestVerified`).** It is a sealed class with an internal constructor and no factory. The Application assembly's `InternalsVisibleTo` names only test assemblies. An IL scan limits construction to `Zaghlol.Application.Purchases.Restore`; I confirmed above that the scan fails on a forged construction. Registration also requires the capability to name the same install, cover the same seat-keys digest (fixed-time compare) and come with `Op = Restore` (`SeatService.cs:26-31`). Otherwise it throws. Trust only goes false → true (`TrustSql`/`RegisterSql`: `seat_key_trusted OR @trusted`). **OK.**
- **T-182 L-1 fix.** `SeatKeyHashAsync` refuses `Position ≠ 0`. Holder and claimant hashes go only through `SeatKeyHashForHolderAsync`, which hashes element 0. `MatchSeatAsync` alone uses the internal any-position path. A relayed key at position ≥ 1 can match, but it is never stored on the seat (R4-1(1) test, M5/M10 negative proofs). **Sound.**
- **Lock order.** Install (registration only), then purchase `FOR UPDATE`, then seat `FOR UPDATE`; the Google predecessor is read `FOR SHARE` afterwards. Chains point backwards only, so there is no cycle. The install-delete trigger goes install → seat and never takes the purchase lock, so it can't form a cycle with the seat service either. The purchase lock serializes the creation of a seat row, and under READ COMMITTED the separate seat `SELECT … FOR UPDATE` sees the committed row after the wait. Key hashing runs before any lock, so KMS latency never holds locks during registration; the rebind match runs under the lock (at most 4 calls in parallel, as designed). The 20-way concurrency tests and the M1 negative proof cover this. **Sound.**
- **Event rows, telemetry and logs.** `purchase_events` rows hold the purchase id, state (`from = to`), a fixed cause and the time: no install id, key hash or account (`SeatStore.cs:89-92`). Metric tags are `channel`/`kind` with fixed words. The over-cap alert carries only the purchase UUID. The seat code has no logger, and its exception messages are constant. `RegisteredSeatKey`/`AppAttestVerified` redact their `ToString`. **Nothing leaks.**
- **DB privilege.** The support path uses the Admin login and never writes `recent_rebinds` (no grant). The tests run it on that login. **OK.**

### Findings

| # | Severity | Where | Finding | Required change |
|---|---|---|---|---|
| T184-L1 | Low | `backend/src/Zaghlol.Application/Seats/SeatService.cs:193`, `:202`; `SeatModels.cs:199` | `SupportMoveAsync` accepts `MoveBack = true` as proof of eligibility **for any target**. P1 ("neither an unexpired claimant nor the move-back target") is enforced only for claimants. Event rows carry no holder, so the primitive cannot check that the target was the previous holder. **Exploit path:** a T-186 defect, or a support operator with a hijacked session, calls the primitive with `MoveBack = true` and an arbitrary install. That moves a paid seat to an install that never claimed it, past the cooldown, and leaves no claimant trail. It is limited to the MFA-protected Admin login, and no endpoint exists yet. | Follow-up owned by **T-186**: derive the move-back target only from T-186's own audit row (the holder before the last `seat_move:support`), and refuse anything else. Add a test showing that `MoveBack` to a non-previous holder is refused. Better: replace the `bool` with a capability type that only T-186's audit lookup can issue, like `AppAttestVerified`. |
| T184-I1 | Info | `SeatService.cs:77-101`, `SeatStore.cs:37-44` | `PredecessorPurchaseId`, `PresentedAccountId`, `AccountId`, `AttachedNow` and `IsNewPayment` are asserted by the caller. Inheritance copies the predecessor's holder, window and `account_id`. A caller-chosen predecessor would let a buyer adopt another purchase's account link and seat holder. | Consumer contract for T-130/T-132/T-135/T-185: take the predecessor only from the verified Play `linkedPurchaseToken` (same package), and take account ids only from verified account tokens. Never take any of them from the request body. Each consumer's review should check this. |
| T184-I2 | Info | `SeatService.cs:206` | The support move reads the target's `seat_key_trusted` without a row lock. This is safe: the flag only goes false → true, so a stale read can only give `false`. | None. |
| T184-I3 | Info | consumer (T-185) | A restore with several items locks one purchase after another. Two concurrent restores that share purchases in a different order can deadlock. Postgres aborts one, which gives a 5xx with no damage to integrity. | T-185: lock items in a stable order (sorted purchase id). |
| T184-I4 | Info | PC runner | Only the design-note commit `7201577` has a PC-runner result (green). The Testcontainers seat suite was run on a local PostgreSQL 16 with a switch that was not committed. | The batch CI run (PostgreSQL 17, Testcontainers) must be green before merge. That is already part of the batch process. |

---

## Verdicts

- **T-040: APPROVED.** Follow-ups: T040-L1, plus Infos T040-I1 to I3.
- **T-184: APPROVED.** Follow-up T184-L1 goes to T-186. T184-I1 and I3 are consumer-contract notes for T-130/T-132/T-135/T-185.
