# Batch review: batch 92 (`batch/2026-11-26-92`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security, one pass) |
| Date | 2026-11-26 |
| Diff | `git diff origin/batch/2026-11-26-91...7e1a8f73` (batch 91 already reviewed) |
| Tasks | T-334 (C2), T-335 (C4), T-337 (C2), T-341 (C4, verified-only), T-325 (C1, spot-check) |
| Verdicts | T-334 APPROVED · T-335 **CHANGES_REQUESTED** · T-337 **CHANGES_REQUESTED** · T-341 APPROVED · T-325 OK (Lead spot-check) |

## Checks run (cloud workspace)
- `dotnet build -warnaserror`: 0 errors, 0 warnings. `dotnet format --verify-no-changes`: clean.
- Application tests: 1295 passed. Contract tests: 115 passed, 91 failed, **all with `DockerUnavailableException`**. Ops tests: 118 passed, 6 failed, all Docker. Api `SyncRequestValidation`: 9 passed. Infrastructure `RemoteConfigProviderSwitch|LlmGatewayConfiguration|LlmProvider`: 19 passed. The Postgres tests of T-334/T-335 were not run here (Lead: green on `ci/T-335`).
- App: `flutter analyze` clean on `core/config`, `core/flags`, `catalog_sync`. `flutter test` on `test/core/config`, `test/core/flags`, `test/privacy`, `test/features/catalog_sync`: 85 passed. `dart format` clean.
- T-325 lists: checked with a throwaway harness outside the repo (see T-325).

---

## T-334: LLM flags, `remote_config`, admin endpoint, ops CLI, sync `config` block (C2). **APPROVED**

| AC | Result | Evidence |
|----|--------|----------|
| 1 unknown key 404, bad value 400, audit + version | PASS | `ConfigAdminEndpoints.cs:58` (404 before the body is read), `RemoteConfigKeys.TryCanonicalize`, `RemoteConfigAdminStore.UpsertAsync` (upsert and audit in one transaction); `RemoteConfigTests` run green; Docker tests on CI |
| 2 block only when the version differs; signed | PASS | `SyncService.ConfigAsync`. The block sits inside the whole signed sync body, so no separate signature is needed |
| 3 server-only keys not sent | PASS | `SentToApp=false` for `llm.provider`, `llm.spend_cap_usd`, `cat.cache_min_confidence`, `cat.confirm_n`; `ToAppBlock` filters on it; `ConfigSpecTests` |
| 4 provider switch without restart | PASS | `RemoteConfigActiveLlmProviderId` reads the value on every call; an unregistered id fails closed in `Resolve` |
| 5 per-request flag evaluation | PASS | `LlmFeatureGate` reads `IFlagReader` on every call; `AskInvest` requires `ask_llm` |
| 6 build, format, OpenAPI | PASS | as run above |

**Security part (the Lead asked for one).** Admin routes are a `RequireOperatorRole(FlagsAdmin)` group. Every write is audited in the same transaction (`config_update`; the value is canonical and pattern-checked, so it can't contain `@` or free text). Values are range-checked on write (`SetAsync`) and again on read (`RemoteConfigService.Build` canonicalises every row and falls back to the default). The sync block holds only the `SentToApp` keys. Nothing new is logged: sync telemetry records only the exception type name. All three flags default OFF (`FlagKeys.Known`, no row means OFF). Leftover check: no doc or task file still says a dev LLM fake is allowed. `ask-llm.md:199` and T-336 mention `Fake` only as the **attestation** mode, and `LlmServiceCollectionExtensions.cs:83` says "the fake can never serve users".

**BR-SYNC-03 amendment (`requirements.md:732`), for the PO.**
- `configVersion` is a server-issued version cursor, classified under D-48 like `flagsVersion`. It is non-financial and needs nothing more.
- `llmCatFeedback` uses `{merchantNorm, verdict, aiCategory, userCategory, source}`, which matches FR-LCAT-31 and llm-categorise tech §5. It is not D-96's approved text: the SRS line is a paraphrase, so the Lead should take these to the PO:
  1. **The approved D-96 text (and D-90's text for the ask question) are still not in BR-SYNC-03.** They cover categorise-request merchant names plus language (via `/v1/categorise`, not sync), the "never people's names, phones, IBANs, handles, digit runs ≥ 6" constraint, "system category or `custom`", "never custom category names" and "kept without install ID at rest". The new line covers sync feedback only and leaves out those constraints. Recommendation: paste the D-90 and D-96 texts in verbatim.
  2. **`source`** (`llm|cache|catalog`) is not in D-96's wording. It is in FR-LCAT-31, which was approved as part of the plan. Low risk, but the PO should confirm it explicitly.
  3. **Linkability in transit.** Feedback travels in the install-authenticated sync, so the backend sees install ID ↔ merchant names in transit. D-96 only promises no install ID *at rest*. This is the same pattern D-62 accepted for seat keys, but D-96 doesn't say it. It needs explicit PO/legal acceptance, together with the store labels D-96 already defers to legal.
  4. The SRS still marks D-94…D-96 "draft / awaiting PO approval" (`requirements.md:37`, `:129`), while `PO_DECISIONS.md` row LLM-CATEGORISE says the whole plan was approved at 03:08. This is doc drift.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| B92-m1 | minor | `backend/src/Zaghlol.Api/Endpoints/V1/SyncEndpoints.cs:118` | `llmCatFeedback` is only shape-checked. `userCategory` accepts any code-shaped string, not "system code or `custom`", and `merchantNorm` accepts digits, `@` and phone shapes. That's harmless today because nothing is stored. | T-353: check `aiCategory`/`userCategory` against the system set (+ `custom`), re-run `ContributionPrivacy` on `merchantNorm` before storing (FR-LCAT-31), and add a test. |
| B92-m2 | minor | `backend/src/Zaghlol.Application/Config/RemoteConfigService.cs:243` | `PUT llm.provider` accepts any id that matches the pattern, including one with no registered provider. Every LLM call then fails closed with no hint. | Reject (400) an id that isn't in `LlmRegisteredProviders` when the API host knows the list, or have the startup/health check report it. Owner T-349. |
| B92-m3 | minor | `docs/01-requirements/requirements.md:732`, `:37`, `:129` | The BR-SYNC-03 text is a paraphrase (see items 1–4 above). | PO decision, then the Lead updates the SRS. |
| B92-n1 | nit | `backend/src/Zaghlol.Application/Sync/SyncService.cs:26` | `IRemoteConfigService? remoteConfig = null`: if the service isn't registered, the block silently disappears. | Make it a required dependency (test doubles can pass a stub). |

---

## T-335: LLM quota store (C4). **CHANGES_REQUESTED**

| AC | Result | Evidence |
|----|--------|----------|
| 1 Cairo month, DST, `resetsAt` | PASS | `CairoMonth` uses `ConvertTime` with the IANA zone; tests cover 30 Nov 23:50 / 1 Dec 00:05, summer/winter and every month boundary 2024–2032 (run green) |
| 2 tiers, paused = Free, account uses the install's limit, either counter at the limit → Exhausted | PASS | `EntitlementQuotaTier` uses `EntitlementRules.Build` over stored, backend-verified facts (active/grace only); `LlmQuotaStore.PreCheckAsync` takes `Max(used)` |
| 3 trim to the lower remaining | PASS | `effective = min(n, limit - max(used))`; SQL `LEAST(@n, @limit - c.used)` |
| 4 neg. proof 1: parallel, same requestId | PASS (CI) | `IS DISTINCT FROM @h` in the `ON CONFLICT … WHERE` is re-evaluated after the winner commits; `ParallelCommitsWithTheSameRequestIdCountOnce` (8×10 rounds, new and existing row) |
| 5 neg. proof 2: delete flows and purge | PASS (CI) | `InstallStore`/`NpgsqlAccountStore` delete inside their existing transactions; retention `month_key < PreviousKey(now)` |
| 6 ask/cat independent | PASS | `feature` is part of the PK |

**Over-grant analysis.**
- Race on commit: closed. The statement never takes a row past `@limit`, and a same-hash twin is a no-op. Different request ids can still overshoot through precheck/commit, by at most the burst; this is documented (OQ 7).
- Month rollover: `month` is computed separately in precheck and commit. A request that straddles midnight is checked against November and counted in December. That is not an over-grant.
- DST: `MonthKey` converts an instant (always correct). `ResetsAt` handles an invalid local midnight. Egypt's switches never fall on the 1st at 00:00.
- Tier downgrade mid-month: Gold `used=30` against Free limit 5 gives Exhausted. Correct.
- Account vs install: the stricter counter decides. Correct.
- Limits: the read path `NumberStyles.None` rejects negatives (falls back to the default). The write path caps at 0..100000. See m4 for the read path.
- Erasure: install and account deletes remove their rows, and the month purge removes the rest.
- Fail closed: DB, config or entitlement errors throw (never Allowed), and a Cairo self-check failure gives `Unavailable`.
- **Replayed requestId: open (M1).**

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| **B92-M1** | **major** (security Medium; before T-349 merges) | `backend/src/Zaghlol.Application/Llm/Quota/LlmQuotaStore.cs:98-101` (and `:121`) | **Quota bypass by replaying a requestId.** A row whose `last_request_hash` equals SHA-256(requestId) passes the precheck *even at the limit*, and by spec a retry calls the provider again. At the limit the commit's `WHERE c.used < @limit` fails, so `last_request_hash` stays frozen on the request that reached the limit. A client that keeps that requestId and changes the question gets unlimited free answers. Only the 20/day rate limit and the global spend cap limit it: about 600/month instead of 5. One abuser can also drain the shared $10 cap and pause the feature for everyone. A match on the **account** row also lets a different install of the same account through. The requestId is client-chosen, and attestation binds the body but not freshness. | Accept a retry only (a) on the **install** row, and (b) within a short window of that row's `updated_at` (read it in `ReadAsync`; e.g. ≤ 10 min, constant agreed with the architect). Alternatively, the endpoint can require the ULID timestamp of `requestId` to be within that window. Add a test: at the limit, the same requestId after the window → Exhausted; from another install of the account → Exhausted. Record the window in ask-llm §4.2. About 20 lines. |
| B92-m4 | minor | `backend/src/Zaghlol.Infrastructure/Llm/Quota/LlmQuotaRepository.cs:60-71` | `RemoteConfigQuotaLimits` duplicates the key catalogue. Its own parse has no range check on read (any int up to 2³¹ is used if a row is edited by SQL), while T-334's `RemoteConfigService` re-validates. | Read limits through `IRemoteConfigService` (`GetInt(RemoteConfigKeys.AskQuotaFree)` …), which canonicalises and range-checks. Owner T-349 (it wires the store). |
| B92-m5 | minor | `LlmQuotaStore.cs:134-138` | The install and account statements are not in one transaction. A crash between them counts the install but not the account. A retry then sees the install hash and returns `IsRetry`, so the account counter is never charged (under-count by `n`). | Run both statements in one transaction (one connection), or document it as an accepted bound next to OQ 7. |
| B92-m6 | minor | `backend/src/Zaghlol.Infrastructure/Retention/RetentionStore.cs` (TombstonedInstalls / InactiveInstalls rules) | Installs removed by the retention purger (not `DELETE /v1/installs/me`) leave their counter rows, keyed by install UUID, until the month purge (up to about 2 months). | Delete `llm_quota_counters` for the install in those rules' statements, like the idempotency rows. |
| B92-n2 | nit | `CairoMonth.cs:22-23` | The self-check requires UTC+3 in July, which ties the LLM module to Egypt keeping DST. A future tzdata where Egypt drops DST would disable the feature. | Check only that the zone resolves and the January offset is +2. The month tests already cover DST. |

---

## T-337: app LLM flags and remote config store (C2). **CHANGES_REQUESTED**

| AC | Result | Evidence |
|----|--------|----------|
| 1 valid block stored; bad block ignored | PASS | The transport verifies the sync signature; `_parse` plus the version check keep the previous values. Tests green |
| 2 missing/stale → defaults, flags OFF | PASS (as tested) / **FAIL in use**, see M2 | `current` falls back after 14 days; the three `FeatureFlag`s fail closed through `FlagsService` |
| 3 send `configVersion` | **NOT DONE** | See below |
| 4 typed parsing, per-key fallback | PASS | `RemoteConfig.fromValues` tests |
| 5 cleared by Delete everything | PASS (by design, no test) | Stored in `secure_state` inside the SQLCipher DB. `DeleteEverything` deletes the DB file set and restarts the container, so the in-memory copy goes too. Confirmed in `delete_everything_providers.dart` |

Encrypted storage: yes (`SecureStateDao`, encrypted DB, ≤ 8 KB). No logging. No clash with the BR-SYNC-03 allow-list today, because `configVersion` isn't sent.

**What remains for AC3** (the SRS now lists `configVersion`):
1. `sync_orchestrator.dart:446-454`: add `configVersion: _config?.version` (send null or omit when 0).
2. `app/test/privacy/support/br_sync_03.dart:160`: add `'configVersion': Leaf(WireClass.versions)`.
3. The M2 fix (without it, AC3 makes staleness certain).
4. Tests: the request carries the stored version; an "unchanged" response keeps the config fresh.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| **B92-M2** | **major** | `app/lib/core/config/remote_config_service.dart:84` (with `:42-46`) | **Config silently reverts to defaults 14 days after the last server-side change, even for a phone that syncs daily.** Freshness (`_atMs`) moves only when a *newer* version is applied. Today the app doesn't send `configVersion`, so the server resends the same block every sync, and `p.version <= _version` rejects it without refreshing `_atMs`. Once AC3 is done, the server sends no block at all when nothing changed. Either way, ops changes (`cat.batch_max` lowered, `cat.min_confidence`, invest thresholds, quota display) revert after 14 days. With a lowered `cat.batch_max` the app then sends larger batches and gets a 400 on every categorise call. | On a verified sync where the request carried the stored version and the response has no `config` block (or an equal-version one), persist a new `at` (a `touch()`). Do the AC3 items above in the same change. Test: apply v3, advance 13 days, unchanged sync, advance 2 more days → still the v3 values. |
| B92-m7 | minor | `app/lib/core/config/remote_config.dart:87-97` | `ask.invest_gold_karat` 22 is valid on the server (`Allowed: [18,21,22,24]`) but falls back to 21 on the app. The app ranges also differ from the server's: `ask.quota_*` app max 1000/10000 vs server 100000, `cat.batch_max` 50 vs 20. | Use the same ranges as `RemoteConfigKeys`, and add a shared vector or a contract test listing key → range. |
| B92-m8 | minor | `remote_config.dart:33,71,99` | `llmProvider` is parsed from `llm.provider`, which the server never sends (server-only, T-334 AC3), so the field is always `''`. The consent body needs `consent.provider` (ask-llm §4.1). The app's only source for it is the 409 `LLM_CONSENT_REQUIRED.providerId`, so a first question would always go through a 409. | Remove the dead field, and decide (architect) whether the block should carry the provider **id** (not secret) for the consent sheet. Owner T-340. |
| B92-m9 | minor | `remote_config.dart` | `ask.s1_pct`, `ask.s4_share_pct` and `ask.s4_saving_pct` are sent by the server (defaults 15/20/25, ask-llm §4.5 as built in this batch) but not exposed by the app. | Add them when T-342/T-340 needs them. |
| B92-n3 | nit | `remote_config_service.dart:102-107` | In-memory state is updated inside the sync's drift transaction. If the commit fails, memory and the DB disagree until restart (flags have `_reloadFlags`; config has no equivalent). | Reload config in the orchestrator's `on Object` path. |

**Pre-existing, not charged to this batch (please verify):** the flags pipeline seems to have the same freshness gap. `FlagsService._apply` refreshes `fetchedAtMs` only when the server sends a flags block, and `SyncComposer.SendFlags` sends one only when `flagsVersion` differs. After going stale, `current.version` still carries the old version, so the server never resends. The result would be every flag (Zakah, ROI and now the LLM flags) reading OFF 14 days after the last flag edit, for good, until an operator edits a flag. It belongs with FU-103 (T-025). The M2 `touch()` should be applied to flags too.

---

## T-341: attestation over a caller hash (C4, closed as verified). **APPROVED**

The claim holds:
- **AC1:** Kotlin `AttestationHostTest` has the 5 named tests (`requestHash` is unpadded b64u of the exact input, shared vectors, one re-prepare on `INTEGRITY_TOKEN_PROVIDER_INVALID`, a second one is transient with no loop, the provider is prepared once and cached).
- **AC2:** Swift `AttestationTests` has the 4 named tests. `attestationObject` is returned only for a new key (first use, `forceNewKey`, `invalidKey`).
- **AC3:** no logging call in `platform/attestation/*.kt` or `AttestationHost.swift`. The only `Log.` is in Pigeon's generated `wrapError`, which goes into the error details and not to logcat. The Dart test "nothing secret is printed or put into errors" exists.
- **AC4:** a one-line `platform-channels.md` §4a pointer. The Dart contract test exists.
- **AC5:** applies.

The channel takes exactly 32 caller bytes, never sees an install ID or the question, and reuses the one Keychain key, with no new key material, permission or entitlement. The ask prefix `zaghlol-ask-attest-v1` keeps ask assertions separate from restore assertions.

**Note for T-336:** restore and ask share one App Attest key and its counter. The verifier must accept the counter rising across both flows (any stored counter per key works, because the counter is monotonic per key). It must also accept first-use `attestationObject` registration through the ask path for installs that never restored. No findings for T-341.

---

## T-325: name, honorific and business-word lists (C1). Spot-check **OK**
- `eg_given_names.txt` 2120, `eg_business_words.txt` 149, `eg_honorifics.txt` 12. All are byte-sorted (`LC_ALL=C sort -c`) and deduplicated. No empty lines, no digits (ASCII or Arabic-Indic), no trailing spaces, no multi-word entries (so no full names of real people). No business word appears in the names list. Every line is a fixed point of `foldKey` (0 of 2281 changed, checked against `packages/zaghlol_parsing`). Nothing offensive found.
- Plausible for masking: the lists are conservative, so a false positive only leaves a shop uncategorised (FR-LCAT-05). The Arabic script coverage is thinner (543 Arabic, 1577 Latin, roughly 3 transliterations per name), which suits Latin POS descriptors. Legal and UX review before the flag goes on is already noted in the README (OQ-LCAT-05).

| # | Sev | File | Issue | Required change |
|---|-----|------|-------|-----------------|
| B92-m10 | minor | (missing) `app/test/assets/data_lists_test.dart` | The AC1 loader test was not added (counts, no duplicates, no empty lines, `foldKey` no-op) and the AC2 checks have no test. They pass today (above) but nothing guards future edits. | Add the test (about 30 lines), or fold it into T-355. |
| B92-n4 | nit | `eg_given_names.txt` | `الدين` is a compound fragment, not a given name. A few entries (`israel`, `victoria`, `edward`, `murtaza`) are not typical Egyptian names. Harmless (they only block), but worth a look in the OQ-LCAT-05 UX/legal pass. | Review in OQ-LCAT-05. |

---

## CLAUDE.md §2 non-negotiables
- **No financial data leaves the phone:** satisfied. The config block is server → app. `configVersion` is a cursor. `llmCatFeedback` is the D-96 class (PO items above), and the app doesn't send it yet.
- **Encryption:** satisfied. Config is stored in the SQLCipher DB, and the attestation key stays in the Keychain.
- **Gold:** satisfied. The quota tier comes only from backend-verified entitlement facts.
- **Money:** satisfied. `llm.spend_cap_usd` and `ask.invest_min_egp` are decimal strings on the backend (`decimal`) and integer piasters on the app (`investMinEgpMinor`). There is no `double`.
- **Logging:** satisfied. Nothing new beyond a fixed time-zone message and the telemetry exception type.
- **Hard-coded strings / RTL:** not applicable (no UI in this batch).

## Triage summary for the Lead
- **Fix round:** B92-M1 (T-335, security, backend lane), about 20 lines plus a test. B92-M2 together with AC3 (T-337, app lane), about 30 lines plus 2 tests and the allow-list entry.
- **Follow-ups:** B92-m1…m10, n1…n4.
- **PO:** BR-SYNC-03 items 1–4 under T-334.
- **Verify:** the pre-existing flags freshness gap (FU-103 family).

---

## Fix round — T-335

**B92-M1 (major): fixed.** A replayed `requestId` no longer passes free.
- Retry rule (`LlmQuotaStore.IsRetry`): only the **calling install's own row**, with a matching `SHA-256(requestId)` and `now - updated_at <= RetryWindow`. The account row never exempts a request (another install of the same account is refused at the limit). Anything else is a new request; failure to read is an exception, never Allowed.
- Window: `LlmQuotaStore.RetryWindow` = 2 minutes, a constant (not remote config). Source: ask-llm §3 (one client retry on connection failure, total budget 9 s, client waits 12 s).
- Commit SQL guard is now `used < @limit AND (last_request_hash IS DISTINCT FROM @h OR updated_at <= @cutoff)`: parallel twins inside the window still count once (negative proof 1 unchanged), and an old matching hash below the limit counts again instead of being free forever (same bypass below the limit, found while fixing). The account statement runs only when the install statement applied and uses a future cutoff, so the account is charged even when the id matches its row.
- Interface: `LlmQuotaRow` gains `UpdatedAt`; `ILlmQuotaRepository.CommitAsync` gains `retryCutoff`. No migration (column `updated_at` already exists).
- **Not done (needs a schema change):** binding a retry to the same body. The row stores no body hash, so inside the 2-minute window a client can still replay the id with a different question once per rate-limit slot; bounded by the window, the 3/min burst and the 20/day bucket. Proposed follow-up for the architect: a `last_body_hash` column (SHA-256 of the canonical question, never the text).
- Tests (fail without the fix): `ReusingTheLimitHittingRequestIdAfterTheWindowIsRefused`, `ReusingTheRequestIdFromAnotherInstallOfTheSameAccountIsRefused`, `AGenuineRetryInsideTheWindowIsAllowedWithoutASecondCount`, `AnOldRequestIdBelowTheLimitCountsAgain` (Application, in memory); `AReplayedRequestIdCountsAgainAfterTheRetryWindowButNotInsideIt` (Postgres). Both existing negative proofs kept (`ParallelCommitsWithTheSameRequestIdCountOnce`, `DeleteFlowsAndThePurgeLeaveNoStaleCounterRows`).
- Doc: ask-llm §4.2 Idempotency records the window.

**Minors.** m6 fixed (retention install deletes now also delete the install's counter rows; assertion added to `AnInstallInactiveForOverTwelveMonths...`). n2 fixed (self-check now needs the zone to resolve and the January offset to be +2; no DST dependency). Not fixed: m4 (read limits through `IRemoteConfigService`, owner T-349, wires the store), m5 (install and account statements in one transaction; larger than 10 lines; with this change the account statement only runs after the install one applied, so a crash between them still under-counts the account by `n`, accepted bound next to OQ 7 until a follow-up).

**Local checks:** `dotnet build -warnaserror` clean, `dotnet format --verify-no-changes` clean, Application quota tests 17/17. Postgres tests (ci/b92-quota, backend-ci run 45858875526): Infrastructure 1584 passed, 0 failed (includes all quota and retention tests), Application 1299, Contract 206, Ops 124, Workers 39 all green. Two Api tests fail and are not from this change: `OperatorEndpointTests.EveryAdminWriteLeavesExactlyOneAuditRowNamingTheOperator` (expected list lacks `PUT /admin/v1/config/{key}`, from T-334) and `HostStartupTests.EveryTestClassThatCanBootAHostIsInTheApiHostGroup` (`SyncRequestValidationTests` not in the ApiHost group); both need a batch-lead fix.
