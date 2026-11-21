# Batch 52 review — FU-165a, FU-266 N1, app follow-ups, security scans

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security for the C4 lanes) |
| Date | 2026-11-21 |
| Diff | `git diff origin/main...batch/2026-11-20-52` (c8634285) |
| Verdict | **APPROVED** (all four lanes); minors → FU-274 |

Tests run here: `flutter test` over gold, transfers, insights compare, transactions repair, export_import, voice, ask differential, account, sign-in gate: **509 passed**. `dotnet test Zaghlol.Infrastructure.Tests --filter OpenBao`: **86 passed, 4 skipped** (live OpenBao, Docker). `flutter analyze` not run (CI is the gate). Security-scan proof runs checked with `gh`: 44771712421 fails in the blocking `osv-release` job on `junit:junit 4.12` (GHSA-269g-pwp5-87pp) in `gradle-export/release.lockfile`; 44773542780 is green on all five jobs.

---

## Lane 1: FU-165a — verified purchase, no seat here (C4 billing) — APPROVED

| Check | Result | Evidence |
|-------|--------|----------|
| Can never grant Gold | PASS | `provesNoSeat` (`entitlement.dart:565`) only returns a bool, writes nothing; the branch in `purchase.dart:272` runs only after the `gold` branch failed, and emits `PurchaseVerifiedNoSeat`, which maps to a message card only. The token itself was already passed through `handleBody` by `anchored` (unchanged path). |
| Only for a locally verified token | PASS | signature against entitlement keys (`parseEntitlementToken`), `sub == installId`, lifetime rule (exp ≤ iat+3 d, exp ≤ grace ≤ exp+4 d), trusted time present and not tampered, `hw < graceUntil`, `iat ≤ hw + slack`. |
| Nonce echo | PASS | `_verifiedNoSeat` requires `r.timeNonce == sent`, where `sent` is captured from this request's `anchored` callback; the body is signature-verified by `anchored`. A replayed earlier body (old nonce) fails. |
| Status set | PASS | `moved`/`refunded`/`expired`/`none` only; `active`/`grace`/`paused` and unknown statuses fail closed (retry later), matching backend-api §4.3 line 356 and batch-18a 145-2. |
| Forged / other-install / stale / holder `paused` fail closed | PASS | `NEG FU-165a: an unverifiable no-seat token …` (3 variants: not completed, `PurchaseQueued`, no active/grace phase) and `NEG FU-165a: a holder token that does not evaluate to Gold …` (`paused`, not completed). |
| Final: completed, outbox empty, no re-verify | PASS | `FU-165a verified without a seat here: completed, final, no Gold, Restore offered`. |
| Paywall Restore card, both locales | PASS | `paywall_screen_test` per lang; `gold_messages` goldens regenerated (ar/en, light/dark); ARB strings in both files, Egyptian colloquial in ar. |

Findings: see FU-274 items 1–2.

## Lane 2: FU-266 N1 — OpenBao single-flight relogin (C4 keys) — APPROVED

| Check | Result | Evidence |
|-------|--------|----------|
| One forced login per refused token | PASS | `OpenBaoClient.cs:401-425`: under `renewLock`, a caller refused with the same token while `renewal.Login` is incomplete joins it; the first one (session still the refused token) clears the session and creates the TCS. `ForcedLoginInterval` check moved inside the lock (no CAS race). |
| Losers wait instead of a 503 | PASS | `ParallelCallersAfterARevocationShareOneLoginAndAllSucceed` (one login, all succeed). |
| Bounded wait, no deadlock | PASS | login started outside the lock on no caller's token, bounded by `loginTimeout` (= `policy.Timeout` in `OpenBaoKms.cs:144`); waiters use `WaitAsync(callerToken)`; continuations async. `AFailedLoginReleasesEveryWaiterWithTheUsualError` (fails / hangs) releases all within 5 s with one login attempt. |
| Policy denial still fails | PASS | `APolicyDenialStillFailsAfterTheSharedLogin`. |
| No secrets in logs/exceptions | PASS | every failure becomes the constant `OpenBaoUnavailableException`; no new logging; tokens never reach a message. Faulted shared task is observed (no unobserved-task exception). |

Findings: FU-274 item 3.

## Lane 3: app follow-ups (FU-273, FU-157b, FU-186a, FU-158a, FU-240b) — APPROVED

- **FU-273:** `googleSignInGateProvider` replaces the static singleton; sign-in (`id_token_source.dart`), Drive auth (`drive_auth.dart`) and delete-everything sign-out (`delete_everything_providers.dart:57`) all use the one provider instance. No remaining `GoogleSignInGate.instance`. Rollback tests added for budget saver and split save. Voice: `_counted` is set before `countOne`, so a throw can't double-count (it can under-count one session, the user-favouring side; acceptable). The PO item (Gold sign-out stops Drive backups) stays open, correctly.
- **FU-157b:** differential test only, no production change; donut total == cycle spend across links, pending, internal, fee, refund.
- **FU-186a:** `compareCardTotal` adds `coveredEarlier` back; same currency (donut and split share the `ChartFilter` currency). Integer `Money` only.
- **FU-158a:** `AmountRepairEvents` holds the EC-40 event and the after-commit hook flushes it. See FU-274 item 4.
- **FU-240b:** `ImportSummary` gains `autoCategorised`/`needCategory`/`topCategories`; top categories are expense-only, single currency (the one with most rows), integer sums, deterministic tie-break. Done screen resolves names by id via `txnLookupsProvider` (no DB access from the widget). See FU-274 item 5.

## Lane 4: security scans (FU-272 scan items) — APPROVED

| Check | Result | Evidence |
|-------|--------|----------|
| Release scan blocking and covers the release runtime classpath | PASS | `osv-release` has no `continue-on-error`; lockfile built from `:app:dependencies --configuration` for `prodSmsReleaseRuntimeClasspath` and `prodNoSmsReleaseRuntimeClasspath` (the only prod flavours: env × sms in `build.gradle.kts:51-77`); plugin-project children are kept (only `project :` lines skipped). Log of 44771712421: release.lockfile 142 packages, failed on the planted dep. |
| Ignores hide nothing real | PASS | `osv-scanner.toml` (52 ids: netty, guava, bouncycastle, junit, httpclient, commons-lang3) is used only by the non-blocking `osv-full-graph` job; `osv-scanner-release.toml` has no ignores, so any of those packages reaching the release classpath fails the blocking job. All entries expire 2027-02-20. |
| gitleaks | PASS | pinned 8.30.1 binary, `sha256sum -c`, `gitleaks git` over `fetch-depth: 0`, blocking, `--redact`, `persist-credentials: false`, no license secret needed. |
| Converter BOM fix | PASS | `parse_line` keeps `g:a -> v`; self-test (9 cases incl. range/strictly/substitution) runs first in the export job. |
| Compose digests | PASS | postgres, alpine, otel pinned by digest with tag comment; dependabot `docker-compose` entry added. |

Findings: FU-274 item 6.

---

## Findings (all minor/nit → FU-274; no blocker or major)

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | nit | `app/lib/features/gold/application/entitlement.dart:573-575` | Token lifetime rule (`3 * 86400`, `4 * 86400`) duplicated from line 171. | Extract one helper/constant used by both. |
| 2 | nit | `app/lib/features/gold/presentation/paywall_screen.dart:230-234` | `onRetry` and `onRestore` both call `_restore`; fine today, but the card can show two buttons with the same effect if a future kind enables both. | Leave a comment or pass only the one the kind uses. |
| 3 | minor | `backend/src/Zaghlol.Infrastructure/Kms/OpenBaoClient.cs:409-413` | After a **failed** forced login the session is null, so the next refused caller takes the normal `TokenAsync` login path without the `ForcedLoginInterval` throttle. `loginGate` still single-flights it, so no storm, but the throttle's intent (one forced login per 5 s) is not enforced in that path. | Document as intended or apply the interval to the post-failure path; add a test either way. |
| 4 | minor | `app/lib/features/transactions/data/amount_repair_events.dart:14-21` | If the edit's transaction rolls back after the repair ran, the held event stays in `_pending` and is published on the next unrelated commit (stale but harmless refresh). | Clear `_pending` on rollback (or flush only from the same edit's commit hook). |
| 5 | nit | `app/lib/features/export_import/presentation/import_done_screen.dart:224-227` | Top-category title is `''` while `txnLookupsProvider` is loading (one frame of blank rows). | Fall back to a localized "other/uncategorised" label or hide the row until loaded. |
| 6 | nit | `osv-scanner.toml:3-4`, `docs/implementation-status.md` FU-272 row | Says the release scan found "140 packages"; run logs show 142. | Drop the count or update it. |

## Checklist
- [x] Tests added and passing (509 Flutter in affected dirs; 86 .NET OpenBao/Kms)
- [ ] `flutter analyze` — not run locally; batch CI is the gate
- [x] RTL + LTR: paywall test and gold_messages goldens in ar and en
- [x] No hard-coded strings (new ARB keys in both locales)
- [x] No `double` money, explicit currency (compare total, import top categories)
- [x] No sensitive data in logs (gold: no logging; OpenBao: constant exception)
- [x] Scope: each lane touches only its listed files plus status docs

## Notes for the Lead
- No fix round needed. File **FU-274** with items 1–6 above (owners: gold lane 1–2, backend 3, app core 4–5, CI 6).
