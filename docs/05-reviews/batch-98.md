# Batch review: batch 98 (`batch/2026-11-27-98`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security, one pass) |
| Date | 2026-11-27 |
| Diff | `git diff 658535ac...55978f60`. 658535ac is the remote tip of batch 97 (`git ls-remote`); 55978f60 is the remote tip of batch 98. The first-parent merge 33ed3914 (origin/main: freeze hotfix, other lane) is excluded (reviewed in `hotfix-freeze.md` and its own batches) |
| Items | T-354 (C2/C3 backend, d5bb8f8f), T-364 (docs, 8e1328da), T-348 (device E2E Ask, 04d10c3d), T-363 (device E2E auto-category + `RemoteConfigService.watch()` + FU-450, 92f2dce8), Bug A (4d2e4970), Bug B (55978f60) |
| Verdicts | T-354 APPROVED · T-364 **CHANGES_REQUESTED** (1 major, privacy copy) · T-348 APPROVED · T-363 APPROVED · Bug A APPROVED · Bug B APPROVED (device proof still owed, B98-m4) |

## Checks run (cloud workspace)
- **Backend:** `dotnet build Zaghlol.sln -warnaserror`: 0 warnings, 0 errors. `Zaghlol.Application.Tests`: 1558 passed. `Zaghlol.Ops.Tests`: 131 passed, 6 failed, all `CliIntegrationTests` with `DockerUnavailableException` (Testcontainers; no Docker here). The Lead reports backend-ci green on `ci/T-354`.
- **App:** `flutter pub get --enforce-lockfile`, `flutter gen-l10n`, `dart analyze --fatal-infos`: clean. `flutter test test/features/insights test/features/home test/features/capture test/core/config test/privacy test/features/categorization/presentation test/integration_support --exclude-tags golden`: 999 passed, 0 failed.
- **`categorizer_seed_test` "3000-alias synthetic catalog: fuzzy stays within budget" (budget p95 < 11.5 ms):** run in alternation on the same idle 2-core machine. origin/main (1dcd4611): 12.0, 12.8, 13.9, 14.1 ms. Batch-97 tip (the base): 11.7, 13.4, 14.3, 15.0, 15.8, 17.6 ms. Batch 98: 13.4, 14.2, 14.3, 14.4, 14.6, 15.7, 17.1, 17.2 ms. All three trees fail, and the ranges overlap. Batch 98 changes no categorizer code (only `llm_cat_ui_providers.dart` under `features/categorization`). **Verdict: the workspace is slow, not a regression.** Follow-up: the bench is tagged `benchmark`, so keep it out of the local default run or scale the budget to the machine (FU, owner: app-core lane).

---

## T-354: operator review endpoints and `zaghlol-ops llmcat`. **APPROVED**

| AC | Result | Evidence |
|---|---|---|
| 1 Groups only, no hash | PASS | `LlmCatReviewStore.cs` selects no `install_hash` and no row id. The DTOs carry the group tuple, vote count and days only. |
| 2 `custom` promote → 400; draft only | PASS | Endpoint validation rejects `Promote` with `userCategory == custom` and `aiCategory == custom`. `UpsertDraftAsync` works through `CatalogAdminStore` under the catalog lock. Nothing calls publish. A merchant created inside the transaction rolls back on an alias failure. |
| 3 Confirmed at N distinct installs, hidden by an open correction | PASS | `ConfirmedQuerySql`: `HAVING count(*) >= @n` over `status = 'collecting'`. The unique key `(merchant_norm, install_hash)` makes the count distinct installs. `NOT EXISTS` an open correction is per merchant. The rule is checked again under the merchant lock at resolve time (409 if it changed). |
| 4 One audit row per resolve; 403 without the role | PASS (CI) | The audit is written in the same transaction, after `rows >= 1`. Group-level `RequireOperatorRole(CatalogEditor)`. Endpoint and operator tests run on backend-ci. |
| 5 CLI mirrors the endpoints, help text | PASS | Ops unit tests pass (131). The live CLI tests need Docker (CI). |
| FU-448 | PASS | `SyncStore.cs:72` compares a correction's day with the UTC day the cache row was written. |
| FU-452 | PASS (CI) | `ConfigAdminEndpointTests`. |

Lock order: catalog lock, then the merchant advisory lock (`llmcat:` domain, the same one as the intake). The intake never takes the catalog lock, so no lock cycle is possible. Every query uses parameters. No merchant text reaches logs.

- **B98-m1, minor.** `SyncStore.cs:72`. With the day comparison, corrections made earlier on the same UTC day as a re-created cache row (for example the ones that deleted its predecessor) also count against the new row. If the model answers the same category again that day, the next sync that carries a correction deletes the new row again, and each later ask goes back to the model until the day ends. The cost is bounded (one day, and only for a category three installs already called wrong). **Change:** none now. Note this in `llm-categorise.md` next to FU-448.

---

## T-364: LLM docs, ADR-027 amendment, privacy policy and store drafts. **CHANGES_REQUESTED**

What I checked against the code:
- **What leaves the phone and who receives it:** matches the code. The Ask body is closed (`AskPlanRequest`). The provider adapters forward only the text (`OpenAiResponsesProvider.cs:49-50` sends `store: false` and no `user`/`metadata`; the Anthropic and Vertex adapters are the same).
- **Retention:** these rows match `RetentionStore.cs`: `llm_quota_counters` by month key (`:58`), `llm_spend_daily` 13 months (`:61`), confirmations at 365 days or once settled (`:65`), corrections 90/180 days (`:66`).
- **No "no server" claim:** the main text has none, apart from M1 below.
- **PENDING PO items:** OQ-ASK-10, OQ-ASK-11, FU-412/FU-441 and FU-421 are placeholder blocks with variants only. Nothing is decided.
- **Language:** the legal body is in Modern Standard Arabic. The colloquial line is only the `summary` box, the existing pattern of the policy.
- **Store drafts:** classifications that need legal are marked "legal to confirm".

- **B98-M1, major (privacy copy; CLAUDE.md §9 "never claim no server").**
  - **Where:** `site/privacy/index.html:92` («من غيرهم زغلول بيشتغل كله على موبايلك») and `:259` ("Without them, Zaghlol works entirely on your phone").
  - **Issue:** Without the two features the app still uses the server for Gold verification, catalog sync, prices and flags, as §2 of the same page says. The sentence is a "no server" claim and contradicts §2.
  - **Change:** reword both lines to the approved claim, e.g. "Without them, your financial data still never leaves your phone" / «من غيرهم بياناتك المالية برضه مش بتخرج من موبايلك».
- **B98-m2, minor (before the policy is published).** `site/privacy/index.html:83`, `:114`, `:250`, `:281` say the category cache is "kept 90 days". As built, nothing purges expired rows (`backend-schema.md` §4 says so; there is no `RetentionStore` rule). The rows hold no personal data, but the policy promises a retention period the code does not enforce. **Change:** add a purge rule for `llm_cat_answer_cache` with `expires_at < now` (backend lane FU) before publishing, or word the policy as "used for 90 days".
- **B98-m3, minor.** `site/privacy/index.html:41` and `:209` still list the server's services as "non-financial services only: Gold, catalog, prices, flags". The next paragraph adds the two LLM features, but the service list does not name them (forwarding questions and shop names to the AI provider). **Change:** add them to the list in both languages.

---

## T-348: device E2E, Ask with the online helper (green: run 45923025631). **APPROVED**

- **Keys:**
  - The P-256 key and the device-proof key are made at run time (`e2e-ask-llm-device.sh` Python block).
  - They are written to a `mktemp -d` file outside `$OUT`, so they are neither uploaded nor published to `device-shots`.
  - They reach the app only through `--dart-define-from-file`, and nothing echoes them.
  - The dev keys are accepted only in debug builds (`response_signature.dart` / `llm_attestation.dart`, unchanged here).
- **Fake backend:** `fake_llm_backend.dart:116,178` binds `InternetAddress.loopbackIPv4` inside the app process on the emulator. It is not reachable from outside.
- **Logs:** the leak check greps the test log and logcat for question fragments and fixture merchant names, and fails the job on a match.
- **Nothing test-only in `lib/`:** `ZAGHLOL_E2E_SIGN_D` and the fixtures are read only under `integration_test/`.
- **Workflow:** every pre-existing job's `if:` now skips on both `e2e_ask_llm_only` and `llm_cat_only`. The two new jobs skip on each other's flag. Push triggers are `ci/**` only.
- nit: `$KEYDIR` is not removed on the early `exit 1` paths (`:66`, `:112`, `:113`). The runner is ephemeral, so this is harmless. A `trap 'rm -rf "$KEYDIR"' EXIT` would be cleaner.

## T-363: device E2E auto-category (green: run 45927300182), `watch()` race, FU-450. **APPROVED**

- **Keys:** made at run time and masked with `::add-mask::`. They are passed as `--dart-define` and never printed.
- **Fake backend:** `fake_cat_backend.dart:165` binds loopback only.
- **Logs:** the test prints only phase names, counts and `DIAG` booleans/lengths. The `DIAG row` query selects no names.
- **Synthetic data:** synthetic SMS only (invented shop names).
- **`RemoteConfigService.watch()`** (`remote_config_service.dart:57-70`): it now subscribes to `_changes` before it emits `current`, so a block applied in between is not lost. Covered by the new test in `remote_config_test.dart`.
- **FU-450:** a counted showing records `lastShown` (starting the 30-day pause, FR-LCAT-43). `dismissedDay` keeps the card up for the rest of that UTC day unless the user pressed "Not now". Tests cover 10 days (waits) and 31 days (back).

- **B98-m5, minor (security Low).** `.github/scripts/e2e-llm-cat-device.sh:119,146`.
  - **Issue:** the key-leak check is `grep -qE "$SIGN_D|$LLM_KEY|…"`. This has two problems:
    1. `$LLM_KEY` is standard base64, so its `+` is an ERE quantifier and a literal leak of the key may not match.
    2. `$SIGN_D` is base64url and starts with `-` in about 1 run of 64. grep then reads the pattern as an option and exits 2, and the `if` silently passes.
  - **Change:** `grep -qF -e "$SIGN_D" -e "$LLM_KEY" "$log" || grep -qE "QUIBLEXO|…" "$log"`. Apply the same at `:146`.
- nit: `remote_config_service.dart:57-70`: the returned controller is never closed when `_changes` closes. Close `out` in an `onDone` of `sub`.
- nit: `llm_cat_ui_providers.dart`: on the day the last allowed showing is counted (`shown` reaches `catCardMaxShown`), the card still disappears on the next rebuild that day. This is unchanged behaviour.

---

## Bug A: top merchants group hand-entered rows by read-time key. **APPROVED**

- **Grouping:** `chart_repository.dart:927-963` groups by `merchant_norm`, or by `merchant_raw` when the norm is NULL. It then merges in Dart by `merchantKey(raw)`, the same rule as `_merchantMatch` (`:718`), so the drill-down of a merged row finds the same rows.
- **Net-spend filter:** the `> 0` filter now runs after the merge (before, it ran per SQL group), which is more correct.
- **Money:** amounts are `int` minor units within the single `f.currency` filter of `_base`, and `Money.fromStorage` is used. No `double`.
- **"Other":** sums the same ranked list beyond `n`.
- **Test:** B98-A covers merge with the scanned merchant, the count, and "Other".
- nit: the display name stays "greatest `coalesce(raw, norm)`", which is case-sensitive: in the test, `hassan  barber shop` is shown over `Hassan Barber Shop`. This rule existed before. If it matters, choose the most frequent raw name instead (FU, UI lane).
- nit: `topMerchants` and `otherMerchants` each run the full unbounded query. They are memoized separately, so the work happens twice per screen. Fine for month periods.

## Bug B: Home follows rows the headless engine writes while the app is open. **APPROVED** (device proof owed)

- **No busy loop:**
  - `_externalWrites` is set only by a native `onSpoolChanged`, which needs a native spool write, and by `_scheduleTimer`.
  - The timer is bounded: 3 re-polls (5/15/45 s), then 3 retries (5 s/30 s/2 min), then parked.
  - Each cycle consumes the flag, so an idle app with an empty spool triggers nothing.
- **No new wakeups:** only an existing cycle or timer can call the hook.
- **Error handling:** `onBackgroundWrites` never throws.
- **`catEligibleCountProvider`:** watches the version, so the card follows.

- **B98-m6, minor (race with the headless isolate; 1-line fix, worth taking in the fix round).**
  - **Where:** `cycle_app_wiring.dart:102`.
  - **Issue:**
    - The sweep starts from `_lastSweepMs`, the wall time of the previous sweep. The headless engine stamps `updated_at` inside a one-transaction batch (`ingest_store.dart:39`) and commits later.
    - A UI sweep that runs between the stamp and the commit records `now > updated_at`. The next sweep starts after the row's stamp and never drops that cycle, so the totals stay stale until the next app resume.
    - This is likely: right after `onSpoolChanged` the UI drain often finds the spool claimed by the headless engine and refreshes at once, while the headless engine is still writing.
  - **Change:** always sweep from `_lastForegroundMs` (or from the persisted value). The sweep is a full scan anyway, and dropping a few extra cycles costs nothing. Alternatively, subtract a margin of at least the 60 s claim window.
- **B98-m7, minor (battery/CPU).**
  - **Where:** `spool_orchestrator.dart:94`, `capture_providers.dart:192-197`, `main.dart:231`.
  - **Issue:** on every resume, `orchestrator.onResumed()` → `onTablesUpdated` → `onBackgroundWrites()` runs a second full sweep and bump, concurrently with `CycleResumeHandler.onResume()`. Home then recomputes 2–3 times per resume.
  - **Change:** call `markIngestionTablesUpdated` only from `onResumed` (split the callback), or let `onBackgroundWrites` return early while `onResume` runs.
- **B98-m4, minor (evidence; required before Bug B is marked done, no code change).**
  - **Issue:** the B98-B host tests prove the two halves (orchestrator flag → callback; handler → Home). Nothing proves the wiring in `captureCoordinatorProvider`. The device test still works around the bug (`e2e_llm_cat_device_test.dart:224-226` invalidates the providers when the card is missing).
  - **Is an end-to-end host test needed?** Not as a gate. The real proof is the device:
    1. Re-run `e2e-llm-cat` (`llm_cat_only`) on the batch tip and confirm the log has no `NOTE card needed a provider refresh` line.
    2. Then turn that branch into a test failure (FU, owner T-363 lane).
  - A small provider-level host test is a cheap guard against a later refactor dropping the hook (FU): build `captureCoordinatorProvider` with a fake host, fire `onSpoolChanged`, and expect a `cycleDataVersionProvider` bump.

---

## Summary for triage
- **Fix round:** B98-M1 (T-364, two lines of copy). Recommended in the same pass because each is a few lines: B98-m5 (grep) and B98-m6 (sweep start).
- **Lead check, no code:** B98-m4 (one device run on the batch tip, NOTE line absent).
- **Follow-ups:** B98-m1, m2 (purge rule, before the policy is published), m3, m7, the benchmark budget, and the nits.

---

## Fix round (task/b98-fix)

- **B98-M1:** `site/privacy/index.html` Arabic (standard Arabic) and English summaries now say that without the two features your financial data never leaves your phone, and that the app still uses our server for non-financial services only (Gold verification, catalog, prices, feature flags; §2). No other "entirely on your phone" / "no server" claims in `site/` or `docs/06-release/` (the two hits there are rules that forbid it).
- **B98-m2:** new `RetentionPurger` rule `llm_cat_answer_cache` (`expires_at < now`; rows are written with `expires_at` = +90 days, so the policy's "kept 90 days" holds). Test `RetentionStoreTests.CategoryAnswerCacheGoesAtExpiry` (Testcontainers, CI). `backend-schema.md` §4 updated. `worker_rw` already had DELETE.
- **B98-m5:** `e2e-llm-cat-device.sh` leak checks use `grep -qF -e "$SIGN_D" -e "$LLM_KEY"` plus a separate `-E` check for the fixed names; the script exits with an error if either key is empty. `e2e-ask-llm-device.sh` greps fixed phrases only, so it needs no change.
- **B98-m6:** `onBackgroundWrites` always sweeps from `_lastForegroundMs` (or the persisted value); `_lastSweepMs` removed. Test `B98-m6: a row stamped before a sweep but committed after it…` fails without the fix.
- **B98-m4:** the provider-refresh workaround in `e2e_llm_cat_device_test.dart` is gone; a missing card now goes straight to the DIAG + `fail` path.
- Local checks: dotnet build -warnaserror, format, Application tests (1558); app format, `dart analyze --fatal-infos`, home+capture tests (449), zaghlol_lints 0 issues.
