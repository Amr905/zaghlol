# Batch 57 review: follow-up sweep (5 lanes)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus), code + security for lanes 1 and 3 |
| Date | 2026-11-22 |
| Diff | `git diff origin/main...batch/2026-11-22-57` (53d8a984) |
| Verdict | CHANGES_REQUESTED (lanes 3 and 4: one major each); lanes 1, 2 and 5 APPROVED |

Test runs on this tree:
- `flutter test --exclude-tags golden test/qa test/features/{insights,accounts,wealth,salary,backup,share_cards}` plus `pigeon_notification_gateway_test.dart`: **+879 -1**. The one failure is real (lane 4, finding 4.1).
- `dotnet test Zaghlol.Infrastructure.Tests --filter OpenBao|DatabaseSettings`: **107 passed, 4 skipped** (live OpenBao), 0 failed.
- `python3 -m unittest discover backend/deploy/monsterasp/tests`: 7/7 OK.
- Swift/Kotlin unit tests not run here; the lane claims app-ci 45026684028.

Goldens not assessed (CI regenerates). Minors and nits go to **FU-285**.

---

## Lane 1: task/B57-backend (FU-274, FU-278, FU-281): APPROVED

| AC | Result | Evidence |
|----|--------|----------|
| FU-274: after a failed forced login, later callers wait out `ForcedLoginInterval` instead of logging in | PASS | `OpenBaoClient.TokenAsync` checks `forcedLoginFailedAt` under `loginGate`; `OpenBaoReloginRaceTests.AfterAFailedForcedLoginTheNextCallersWaitOutTheIntervalBeforeAnotherLogin` |
| No deadlock, waiters bounded | PASS | The forced login still runs on its own `loginTimeout` token; throttled callers throw `OpenBaoUnavailableException` at once instead of queueing a login; a success resets the mark. The forced path passes `forced: true`, so it is never blocked by its own mark |
| FU-278: TLS guard in Production and Staging | PASS | `DatabaseSettings.RequiresVerifiedTls` used by the options validator and `MigrateCommand`; `TheTlsGuardCoversProductionAndStagingOnly` |
| FU-281: pools 2/1/1 fit Aiven with an overlapped recycle | PASS | 2 x (2+1+1+1) + 2 migrator = 12 of 14; `test_template_pools_fit_two_overlapping_processes_in_the_aiven_budget`; vars allow-listed in `monsterasp_package.py` |

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1.1 | minor | `backend/src/Zaghlol.Infrastructure/Kms/OpenBaoClient.cs:466-478` | `forcedLoginFailedAt` is written in `ForcedLoginAsync`'s catch, after `TokenAsync`'s `finally` has already released `loginGate`. A caller waiting on the gate can get in during that window, read `long.MinValue` and log in once more, unthrottled. At most one extra login, so not a storm. | FU-285: set the mark inside `TokenAsync` (when `forced`, in a catch before the `finally`) so it is written before the gate opens. |
| 1.2 | minor | `backend/deploy/terraform/README.md:57`, `modules/database/outputs.tf:10` | The GCP terraform path still says connection strings use `SSL Mode=Require`. That has stopped Production from starting since T-205, and now it stops Staging too (`envs/staging` sets `aspnet_environment = "Staging"`). | FU-285: switch to `VerifyFull` with the Cloud SQL CA, or document `Database__AllowInsecureTransport=true` for the private-IP path. |

### Security
- No secrets, tokens or connection strings appear in the new messages. The error text change is wording only.
- The throttle fails closed (503 / `OpenBaoUnavailableException`) and never falls back to a stale token.
- The new web.config entries are public values and allow-listed. The rejection of private keys is unchanged.

---

## Lane 2: task/B57-core (FU-149b, FU-268): APPROVED

| AC | Result | Evidence |
|----|--------|----------|
| FU-149b: a unit snapshotted before that now has nothing gets a zero row, per unit, never summed | PASS | `snapshotRows(previousUnits:)` (domain, pure); repository reads `DISTINCT unit` and passes it in; `net_worth_test` + `net_worth_repository_test` "a unit that drops to nothing gets a zero point" |
| FU-268: a declined credit is re-offered once the "another income" row is gone | PASS | `_findReceived(declinedAlways:)`; the "another income" path still declines everything (`declinedAlways: true`); `salary_matching_test` FU-268 |

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 2.1 | nit | `packages/zaghlol_domain/lib/wealth/net_worth.dart:240-255` | Every unit ever snapshotted gets a zero row in every later snapshot, for ever. The table grows with the number of units, and the history line never ends. Acceptable, but nowhere documented as intended. | FU-285: note it in the schema doc, or stop after the first zero. |
| 2.2 | nit | `app/lib/features/salary/application/salary_service.dart:296-298` | `undoMerge` also adds to `declined` (`salary_matching.dart:142`). With FU-268, deleting the restored manual row re-offers the captured credit the user said was a second payment. Arguably right; flagging so the PO knows. | None (note only). |

---

## Lane 3: task/B57-native (FU-202d, FU-193e, FU-267, FU-168e), C4: CHANGES_REQUESTED

| AC | Result | Evidence |
|----|--------|----------|
| FU-202d: native clear keeps `wipe_pending` (Android + iOS) | PASS | `clearContents(keep)` / `clearContents(keeping:)` skip the name at the top level only; nested copies go; "ok" ignores the kept entry. `LocalDataWiperTest.theResumeMarkerSurvivesTheClearAtTopLevelOnly`, `BackupExclusionTests.testWipeKeepsTheResumeMarkerAtTopLevelOnly` |
| A resumed wipe can't leave user data behind; marker removed at the end | PASS | Only one top-level entry with that exact name survives. `.tmp`/`.reads` siblings are deleted. Dart `delete_everything.dart` clears the marker when `pending` is empty or at the last resume, and otherwise rewrites it. The marker is on the app-support root (`filesDir` on Android, Application Support on iOS), which is one of the native roots. |
| FU-193e: iOS headless engine registers only the secret store and capture host | PASS (by reading; device check pending) | `GeneratedPluginRegistrant` removed. The headless Dart (`ingestion_main.dart`, `ingest_store.dart`) uses path_provider (`path_provider_foundation` 2.6.0 is `dartPluginClass`/FFI, covered by `DartPluginRegistrant.ensureInitialized()` at `ingestion_main.dart:73`), `sqlite3` (build hooks, no plugin), the secret store and the capture/ingestion pigeons. `spike_metrics` has no native handler and tolerates that. Nothing needed is missing. |
| FU-267: `cancelScheduled` channel | PASS | Android cancels only the tracked alarm PendingIntents and clears the id file; iOS `removeAllPendingNotificationRequests` only. Gateway test "cancelScheduled goes to the platform and not cancelAll". The Dart caller (re-redact) is still open, as the status doc says. |
| FU-168e: wake-up runs no Dart; Gold schedules can't be cancelled by a background run | PASS | The Android `BackupWakeWorker` and iOS launch handler only create an empty `due` file. No engine, no data, no entitlement read, so nothing in the background can call `cancel()`. Wipe covers it (`cancelAllWork` / `cancelAllTaskRequests`, roots cleared). |
| FU-168e: App Store `processing` mode justified | **FAIL** | see 3.1 |

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 3.1 | **major** | `app/ios/Runner/Info.plist:56` (`processing`), `app/lib/features/backup/application/schedule_providers.dart:26-31`, `app/ios/Runner/Platform/BackupWorkHost.swift:93-99` | Nothing in `app/lib` calls `takeDue()`, `runScheduled()` or `reconcile()`; `implementation-status.md` FU-168e says so too. The build now declares the `processing` background mode and schedules real WorkManager / BGProcessingTask jobs whose only output, the `due` file, is never read. The iOS request is also one-shot: the handler does not re-submit, and the re-submit was left to Dart's `schedule` "after it runs the backup", which never happens. App Review checks background modes against actual use (guideline 2.5.4), and that use doesn't exist yet. On Android the device is woken for nothing. | Pick one before merge. (a) Wire the consumer: on cold start and resume (`resumeJobsProvider`), `if (await takeDue()) { await runScheduled(); await remindIfStale(); }`, plus `reconcile()` once the entitlement is verified (that re-submits the iOS request). Add a test that a due mark leads to `runScheduled`. Or (b) keep `backupWorkSchedulerProvider` on `_NoWorkScheduler` and leave `processing` out of Info.plist (and the plist test) until (a) lands; the native classes can stay. |
| 3.2 | minor | `LocalDataWiper.kt:36`, `IosCaptureHost.swift:307` | The marker name is kept at the top of **every** root (cache, noBackup, App Group), not just app support, and a directory with that name would also be kept along with its contents. No code writes that name anywhere else, so there is no leak today. | FU-285: keep it only in the marker's root, and only as a regular file. |
| 3.3 | nit | `BackupWork.kt:79-84` | `doWork` catches only `IOException`; a `SecurityException` from `createNewFile` fails the work instead of retrying. | FU-285. |

### Security (C4)
- **Data deletion:** the change narrows deletion by exactly one top-level file name, which holds only `WipeMarkerState` (no user data). Every other entry, including nested `wipe_pending` copies, is still deleted. Resume safety (`_newerData`, `maxResumes`) is untouched. No path lets a resumed wipe keep user data.
- **Headless engine:** fewer native plugins in the headless engine means less attack surface (no sign-in or IAP channels reachable from the Shortcut/BG drain). The DB key path still goes through `SecretStoreRegistration`.
- **Backup wake-up:** the job carries no data, starts no engine and reads no entitlement. The `due` file is empty, sits in noBackup / Application Support, and is wiped. Periods are allow-listed (1/7/30) on both sides. Nothing is logged.
- **`cancelScheduled`:** native code rebuilds no text. Shown alerts keep their already-redacted public version.
- One cosmetic exception: the Pigeon-generated `wrapError` sends the stack trace to Dart. That is the generator default and carries no data.

---

## Lane 4: task/B57-ui (FU-284, FU-269 N1/N2, FU-205c): CHANGES_REQUESTED

| AC | Result | Evidence |
|----|--------|----------|
| FU-284: drill header names the baseline dates | PASS | `insightsChartsDrillTotalVs` (ar/en), `ChartPeriodText.range(before)`; `charts_redesign_test` |
| FU-284: route-scoped filter, root filter untouched | PASS | `ProviderScope` overriding `txnListFilterProvider` + `txnListProvider` inside the route; test reads the root container and finds it untouched. The filter sheets return values to the scoped notifier (`transactions_list_screen.dart:493`), so they don't write to the root. |
| FU-284: axis-step edge test | PASS | `chart_summary_test` "edge maxima around step boundaries" |
| FU-269 N1: month cue doesn't collide on 30th/31st starts | PASS (no test) | `chart_bodies.dart:135-141` |
| FU-269 N2: cash-flow subtitle says what the totals cover | **FAIL** (test) | see 4.1 |
| FU-205c: share that never answers times out and the staging file is deleted | PASS | `.timeout(onTimeout: () {})` + `finally` delete; `share_studio_test` FU-205c. `Future.timeout` keeps listening to the source, so a late error is not unhandled. |

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 4.1 | **major** | `app/lib/features/insights/presentation/charts/charts_screen.dart:281-298`; `app/test/features/insights/presentation/charts/charts_screen_test.dart:245` | The N2 change adds "Totals are for …" to the default subtitle, but the existing test still expects `'Last 6 months · this month is not over yet'`. `charts_screen_test` "default: six cycles, caption says so, three rods per bar" **fails** on this tree, so the CI gate will be red. | Update the expectation to the new subtitle and assert the totals note in both locales. Also check that the resulting three-part caption reads well in ar (`الإجماليات عن …` followed by the open-period note). |
| 4.2 | minor | `chart_drill.dart:81-82` | Only the filter is scoped. `txnSearchProvider`, `cardFilterProvider` and `txnSelectionProvider` are still shared with the Transactions tab: a search typed in the drill shows up in the tab, and the tab's search narrows the drill. This predates the batch but is not covered by the FU-284 fix. | FU-285: override those in the same scope (and `txnListProvider` already is). |
| 4.3 | minor | `chart_drill.dart:169-173` | The caption shows "vs <range>" even when there is no comparison (`old == null`, change none), and the a11y label (`insightsChartsDrillTotalA11y`) doesn't include the baseline range. | FU-285. |
| 4.4 | minor | `chart_bodies.dart:133-141` | The FU-269 N1 cue rule has no test (period starting on the 30th/31st). | FU-285: one widget/unit test. |
| 4.5 | minor | `share_providers.dart:36` | After 2 min the file is deleted even if the iOS sheet is still open and a target hasn't read it yet. This is privacy-positive and probably fine, but the share would fail silently. | FU-285: note it in platform-channels, or measure on a phone. |
| 4.6 | nit | `app_en.arb` / `app_ar.arb` `insightsChartsDrillTotal` | Now unused (dead key). | FU-285: remove. |

---

## Lane 5: task/B57-qa-fixes (BUG-010…014): APPROVED

| AC | Result | Evidence |
|----|--------|----------|
| BUG-010: Money hero headline is the primary currency | PASS | `totals.orderedFor(primary)`; empty state falls back to the primary, not EGP. `bug_010_money_hero_currency_test`, `test/features/accounts/.../bug_010_money_hero_currency_test.dart` |
| BUG-011: export preview reads "amount hidden", not `****` | PASS | `Semantics(label: a11yAmounts(...), excludeSemantics: true)`; `bug_011_export_preview_a11y_test` |
| BUG-012: charts and Share studio open on the primary currency, primary first | PASS | `primaryFirst` in both screens; `bug_012_charts_default_currency_test` |
| BUG-013: a stepped period is announced by its range | PASS | `offset == 0 ? presetName : range`; `bug_013_period_a11y_preset_test` |
| BUG-014: net-worth explanation in major units | PASS | `MoneyFormat.format(Money(Currency.of(unit), minor))`; `bug_014_networth_explain_minor_units_test` (also covers hidden via the shared formatter) |

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 5.1 | minor | `app/lib/features/insights/presentation/chart_explain_l10n.dart:56` | `Currency.of(unit)` throws `UnknownCurrency` for a non-ISO unit. Today `netWorthChartProvider` is keyed by an ISO currency code, so it can't happen, but `UnitAmountArg` is typed as a generic "unit" (gold units are `XAU21_G`). | FU-285: `Currency.tryOf(unit)`, falling back to the old `'$minor $unit'` rendering (or assert at construction). |
| 5.2 | minor | `charts_screen.dart:85-89`, `share_studio_screen.dart:84-88` | While `primaryCurrencyProvider` loads (`.value == null`), the order is alphabetical, so the first frame can select AED and then jump to the primary. `roi_tips_screen.dart:66` / `roi_tips_providers.dart:85` still use the unordered list. | FU-285: wait for the primary currency (or apply `primaryFirst` inside `chartsCurrenciesProvider`), and cover ROI tips. |
| 5.3 | nit | `export_screen.dart:311-325` | The masked/unmasked string is built twice; hoist it into a local. | FU-285. |

---

## Docs

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| D.1 | nit | `docs/implementation-status.md:889` and `:893` | FU-284 appears twice (old OPEN row plus the new batch-57 row), probably a merge leftover. | Drop the old row. |
| D.2 | nit | `docs/implementation-status.md:998` vs `:867` | Line 998 says FU-267 "needs a native pending-list/cancel hook", but the native hook landed in this batch (line 867). | Reword line 998: the native hook exists; the Dart re-redact caller is open. |

## Fix round

- **Lane 3 (native/core):** 3.1. Either wire `takeDue` → `runScheduled`/`remindIfStale` on start/resume and `reconcile()` after verification (with a test), or keep the scheduler binding inert and drop `processing` from Info.plist until then.
- **Lane 4 (UI):** 4.1. Update `charts_screen_test` for the new cash-flow subtitle. This is small, so a Lead delta check is enough.
- Everything else → FU-285.
