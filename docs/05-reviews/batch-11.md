# Review — Batch 11 (T-181, T-183, T-048, T-049, T-119)

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer, also acting as security-privacy-reviewer and test-engineer (single combined reviewer, Opus) |
| Date | 2026-11-13 |
| Commit / diff | `batch/2026-11-13-11` @ `57daee1`; per task `git diff origin/main...origin/task/<branch>` |
| Verdicts | T-181 APPROVED · T-183 APPROVED · T-048 **CHANGES_REQUESTED** · T-049 **CHANGES_REQUESTED** · T-119 **CHANGES_REQUESTED** |

Test runs (review worktree, batch head):
- `flutter test test/features/capture test/features/gold test/features/ingestion`: **323 passed**, 0 failed.
- `dotnet test Zaghlol.Infrastructure.Tests --filter Attestation (without AttestationDatabaseTests)`: **55 passed**.
- `dotnet test Zaghlol.Application.Tests`: **1008 passed**.
- Docker tests (`AttestationDatabaseTests`) not run here; the Lead reports backend-ci incl. Testcontainers green on `ci/T-181`.

---

## T-181 — Backend attestation verifiers (Play Integrity, App Attest) — APPROVED

Design note (implementer-written, Opus) reviewed: placement, the Play client deviation (hand-written DTO instead of `Google.Apis.PlayIntegrity.v1`, so R2-7 holds by construction), rule order, registration/assertion semantics, root pinning and test vectors are sound and match backend-api §4.3 step 2 (updated in the same diff).

Checked in code:
- **Chain:** `X509Chain` with `CustomRootTrust`, the pinned root as the only anchor, offline, no revocation, verification time = now; exactly 3 elements, element 1 byte-equal to the supplied intermediate, element 2 SHA-256 = pinned (`AppAttestVerifier.cs:366-398`). Embedded root's SHA-256 independently recomputed: `1cb9823b…c932`, subject/serial/validity as stated.
- **Nonce / keyId / credentialId / RP ID / counter / AAGUID:** DER parse of the nonce extension, duplicate extension refused, fixed-time compares, `authData` length checked before every offset read (`:143-196`). Development AAGUID only with `AllowDevelopment`, which Production refuses at startup (`AttestationOptions.cs:114-117`); test root refused outside Development/Testing (`:120-125`).
- **Assertion:** this install's row `FOR UPDATE`, ECDSA P-256/SHA-256 over `SHA-256(authenticatorData ‖ clientDataHash)`, RP ID, strict counter increase, update in the caller's transaction (`:77-118`, `NpgsqlAppAttestKeyStore.cs`). Same-install re-registration keeps the counter; other-install keyId refused; concurrent insert loser refused.
- **Play:** only the checked members exist in the DTO, `UnmappedMemberHandling.Skip`, no `JsonExtensionData` (`PlayIntegrityVerifier.cs:21-71`); token in the body, never the URL; `400` → `chain`, other non-2xx/timeout/unreadable → `unavailable`; replay row only after every check, autocommit on its own connection.
- **Fail-closed startup:** root fingerprint, both option sets and "real verifiers only in Production" asserted by a hosted service (`AttestationServiceCollectionExtensions.cs:288-306`).
- **Logs:** reason code only; HttpClient loggers removed; sentinel tests over logs/activities for both providers.

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Play: one test per rule | PASS | `PlayIntegrityVerifierTests` (hash, package, 6-min, not recognized, basic, no label, replayed, future timestamp) |
| R2-7 sentinel | PASS | `OptionalVerdictsAreIgnoredAndNothingSensitiveIsLoggedOrTraced` |
| App Attest attestation rules | PASS | `AppAttestVerifierTests` (chain, nonce, RP ID, counter, AAGUID, other install, malformed), plus a real Apple production attestation under the pinned root |
| App Attest assertion rules | PASS | valid/raises counter, non-increasing counter, other install's key, different clientDataHash |
| R4-1(3) vector | PASS | `RestoreBindingVectorAssertionVerifiesAndReorderedSeatKeysFail` |
| Counter rollback in ambient transaction | PASS (CI) | `AttestationDatabaseTests.TheCounterUpdateRollsBackWithTheCallersTransaction` (Testcontainers, per Lead) |
| Upstream failure → `unavailable` (WireMock) | PASS | `AnUpstreamErrorIsUnavailableNeverAFailure`, `ATimeoutIsUnavailable` |
| Log/trace sentinel | PASS | `FailuresLogTheReasonCodeOnly`, Play sentinel test |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 181-1 | minor · Security Info (before launch, not before merge) | `AttestationOptions.cs:20`, `deployment.md` | The pinned root fingerprint was taken from two third-party copies, not from apple.com. Bytes and fingerprint are consistent with the published Apple root, but provenance is unconfirmed. | PO confirms the fingerprint against apple.com/certificateauthority before launch (already listed as T-181 PO question 1); track as FU. |
| 181-2 | nit | `AttestationOptions.cs:77` | `AttemptTimeout` default is 4 s; the design note says 3 s per attempt. | Align note or code. |

---

## T-183 — Dart request-binding library — APPROVED

Strict parser (`strict_json.dart`): duplicates rejected after unescaping at any depth; lone surrogates rejected raw and escaped, including a high surrogate at end of string; depth cap 64 and size cap 1 Mi enforced before recursion; NaN/Infinity rejected. Errors are `BindingException(enum)` with fixed text (`binding_exceptions.dart:268-273`), tested not to echo input. JCS: UTF-16 key order (`String.compareTo`), RFC 8785 escape set with lower-case `\u00xx`, ES `Number::toString` via shortest round-trip digits. Hash layouts match backend-api §4.3; installId refused (not normalised) unless lower-case hyphenated UUID. Vectors are read from `backend/tests/Zaghlol.Contract.Tests/vectors/` (not re-typed). No I/O, no logging.

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Every `valid` restore vector reproduced | PASS | group `AC1 valid restore vectors` |
| Every `invalid` vector rejected before hashing | PASS | group `AC2 / R3-8 …` (via `restoreBodyHashFromJson`) |
| `seatMessage` matches `seat-proof-v1` | PASS | group `AC3 …` |
| R2-1 / R4-1(3) | PASS | group `R2-1 / R4-1(3)` |
| JCS property test | PASS | `property: stable under key reordering and whitespace` |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 183-1 | minor · Security Low | `request_binding.dart:164` | `restoreBodyHash(installId, Map)` is public and hashes any map, so a caller (T-145) can skip the strict parse that R2-6/R3-8 depend on (e.g. hash a `jsonDecode` map, which silently keeps the last duplicate). | Make the map overload library-private or `@visibleForTesting`, leaving `restoreBodyHashFromJson` as the only public entry. Follow-up (T-145 owner). |

---

## T-048 — Historical inbox scan — CHANGES_REQUESTED

What holds: FU-109 rule is implemented as decided (phone-number user senders not queried unless `capture.scan_personal_senders`, then a separate query from `max(since, now − 3 months)`; origin `inboxScanPersonal` keeps the Guard's not-financial drop and drops unrecognized/generic/undirected as `personal_unparsed`). Native address matching is ASCII-case variants and Dart looks up by lower-case, so the personal origin is attributed reliably. The scanner only reads (`queryInbox`) and ingests; nothing deletes. Progress and failure values are counts and codes only (integration test `no body, address or amount…`). Catch-up `since` = `min(watermark, firstMissed, request) − 10 min`, clamped; null watermark with no request never scans (FU-085); request cleared only while unchanged.

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| First transactions < 10 s | PASS (design) | first page 100 rows, ingest per 100; `pages through the inbox…` |
| 10k SMS < 60 s | PASS (host) | `inbox_scan_benchmark_test.dart` (11.9 s on host; reference device not measured) |
| Integration test with seeded inbox | PASS | `inbox_scan_integration_test.dart` |
| FU-109 (PO) | PASS except finding 048-2 | `user-added senders (FU-109 M-1)` group, `personal opt-in…` |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 048-1 | **major** | `scan.dart:78-86`; `inbox_scan_service.dart:80-101` | `run()` returns the running scan's future to any second caller, whatever it asked for ("its request wins"). A `startFirstRun()` (6 months) or `rescanInstitution()` (FR-CAP-07) that arrives while a catch-up (since = watermark − 10 min) runs is silently dropped and reported as `done`. For first run this loses months of history for good: the watermark then sits at "now", so later catch-ups never reach back. Catch-ups run on every app start and after drains, so the overlap is realistic (live SMS arriving during onboarding, un-ignoring a card right after opening the app). | Single flight must not drop a different request. Either queue the new request and run it after the current scan (coalescing only when the running request covers it: `since` ≤, sender set ⊇, `includePersonal` ≥), or let first-run/re-scan cancel a running catch-up and run themselves. Add tests: first run during a catch-up scans the full depth; re-scan during a catch-up queries that institution. |
| 048-2 | minor · Security Low | `ingest_raw_messages.dart:496-509`, `:256-275` (`_storeFailed` / `_quarantine`) | A personal-origin message that parses cleanly but then fails at message level is stored as raw `review` + `unrecognized` item (`ingestFailed`), i.e. it enters the review queue, against FU-109 "never into review". Rare path, and the message already passed the financial Guard. | For `inboxScanPersonal`, return `IngestDropped('personal_unparsed')` instead of `_storeFailed` (the SMS stays in the inbox). Test. Follow-up allowed, or fix in the 048-1 round. |
| 048-3 | minor | `scan.dart:109-121`, `:199-201` | On an `INVALID_ARGUMENT` restart, `scanned` keeps counting from the aborted pass, so progress over-reports (rows read twice). `first` is also false after a restart, so the restarted first page is 500 rows. | Reset `scanned` (or track per pass) on restart. Follow-up. |
| 048-4 | nit | T-048.md deviation (3) | The PO decision also asks for a financial-looking filter on **live** capture of phone-number senders and a consent line when one is added; correctly scoped out, but no FU id is recorded. | Lead files an FU against T-040/T-047. |

---

## T-049 — Review queue repository — CHANGES_REQUESTED

One-winner holds: every action runs in one transaction that starts with the DAO's conditional `UPDATE … WHERE resolved_at IS NULL`; the loser gets `applied: false` and writes nothing; a failed check after the resolve throws and rolls it back. `requestMyBank` outbox payload is exactly `{institutionName, country, channel}` (FR-PAR-14, BR-SYNC-03), from an explicit user action, with a client filter at least as strict as BR-SYNC-04 (`@`, 6-digit runs, 2–64 chars); no message text, sender or amount. Errors are codes only.

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Dismissed raw message status updates | PASS | test at `review_repository_test.dart:47`, `a second dismiss is a no-op (one winner)` |
| Manual entry creates a verified transaction | PASS | test at `:89`, `manual entry twice creates one transaction` |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 049-1 | **major** | `review_repository.dart:109-153` | `resolveManually` accepts any item kind. On a `lowConfidence`/`possibleDuplicate`/generic item, which already has `txnId`, it inserts a second transaction for the same raw message, so the money is counted twice. `requestMyBank` checks the kind; this does not. | Allow only `unrecognized` / `newSender` items with `txnId == null`; otherwise throw `REVIEW_NOT_APPLICABLE` (before the resolve). Test for a lowConfidence item. |
| 049-2 | minor | `review_repository.dart:99-105` | `dismiss` sets the raw message to `dismissed` even when the item belongs to a stored transaction (lowConfidence, possible duplicate), leaving a `dismissed` raw behind a live transaction. | Only change the raw status when `item.txnId == null`. Follow-up. |
| 049-3 | minor | `review_repository.dart:127-150` | The insert duplicates `DriftTransactionRepository.add` without its checks: no merchant length cap/trim, no tz-offset range check, `direction` is an unvalidated `String`, and only the account's default currency is accepted (a USD spend on an EGP card can't be entered, against "any ISO currency"). | Reuse the transactions repository's validation (or `TxnDirection`), and decide the currency rule with T-052. Follow-up. |

---

## T-119 — Gold gate matrix — CHANGES_REQUESTED

Fail-closed holds: state is Free by default; `EntitlementState._` is private; the only producers of Gold are `applyVerified` and `debugOverride`, which is a no-op unless `kDebugMode` (constant false in profile/release, so tree-shaken). Plain `check()` denies quota capabilities, which are only reachable through their helpers. Reads are never blocked (BR-GOLD-04). Matrix matches SRS §5.2.

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Every Gold-only capability checked through the matrix | PARTIAL | matrix complete; existing Gold checks (`guard_config_writer.dart:59`, `ingest_raw_messages.dart:435/456/465`) still use hard-coded `goldActive: false` (fail closed); see 119-3 |
| Downgrade keeps data readable, not creatable | PASS | `downgrade keeps data readable but not creatable (BR-GOLD-04)` |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 119-1 | **major** | `gating.dart:144-148` | `applyVerified` grants Gold only for `status == 'active'`. backend-api §4.3 (line 353): the app grants Gold for `status ∈ {active, grace}`. A paying user in billing grace (`in_grace` → `grace`) is shown Free and loses Gold features. | Accept `active` and `grace` (still fail closed for everything else, including unknown strings); test both, plus `paused`, `moved`, `refunded`, `expired`, `none`, null. |
| 119-2 | minor · Security Low | `gating.dart:54-56` | `goldForTest` is a public constant; any production code can build Gold state with it (only an analyzer warning stops it). The brief's "no path to Gold except `applyVerified`" depends on that lint. | Make it library-private (`_gold`) and have tests reach Gold through `applyVerified(verified: true, status: 'active')`. Follow-up, or fix in the 119-1 round. |
| 119-3 | minor | `guard_config_writer.dart:59`, `ingest_raw_messages.dart:435` | `customSmsRegex` Gold checks aren't wired to `entitlementStateProvider` yet (hard-coded false). Safe (fails closed) but the AC "every Gold-only capability is checked through the matrix" is open. | FU for T-144 (when real entitlement arrives): wire `goldActive` to `GoldGate.check(..., GoldCapability.customSmsRegex)`. |
| 119-4 | nit | `gating.dart:19` | `foreignAssets` stands for "gold, CDs, real estate, stocks, multi-currency" (§5.2), not foreign assets. | Rename (e.g. `investmentAssets`). |

---

## Checklist (batch)
- [x] Tests added and passing (Flutter 323; backend 55 attestation + 1008 application)
- [x] RTL/LTR: no UI in this batch
- [x] No hard-coded user-facing strings
- [x] No `double` money (T-183's `double` holds only JSON numbers for JCS; no money passes through it)
- [x] No sensitive data in logs (sentinel tests in T-181; T-048 progress/codes count-only test; no logging in T-049/T-119/T-183)
- [x] Scope: changes stay within each task's listed components (T-181 also touched `PlayCredentials.cs`, `SeatPorts.cs`, `SeatStore.cs`; justified by the design note)

## Fix list (blockers / majors only)

| # | Task | Lane | Severity | Fix |
|---|------|------|----------|-----|
| 048-1 | T-048 | App core (flutter-core) | major | Single flight must not drop a different scan request; first run and re-scan must run their own request (queue or cancel the catch-up); tests |
| 049-1 | T-049 | App core (flutter-core) | major | `resolveManually` only for `unrecognized`/`newSender` items without `txnId`; test |
| 119-1 | T-119 | App core (flutter-core) | major | `applyVerified` grants Gold for `active` and `grace`; tests for every status |

All three are small; each qualifies for a Lead delta check (≤ ~30 lines with a failing-without-fix test). T-049 and T-119 are one-file fixes; T-048-1 is the largest. They are all in the same lane, so run them one after another, or as one agent working through the three tasks in turn.
