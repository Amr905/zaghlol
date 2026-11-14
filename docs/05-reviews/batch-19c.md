# Review: batch 19c (WIRE-NAV, WIRE-SVC)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus, code + security) |
| Date | 2026-11-14 |
| Diffs | WIRE-NAV: `git diff 790a36bc^1 790a36bc^2` (commit 4772ec28). WIRE-SVC: `git diff 790a36bc^1 5a014cc0^2` (commit e312ed34). Both cut from batch-19 at 0e5306a8 |
| Task files | None (wiring tasks, no `T-###.md`). Reviewed against the Lead brief |
| Tests run | `flutter test --exclude-tags benchmark,golden test/app test/ingestion test/features/{backup,capture,settings,ingestion/data,catalog_sync/application/sync_orchestrator_test.dart}`: 608 passed |

---

## WIRE-NAV (C3): app composition

**Verdict: APPROVED**

What I checked:
- **Gold gates.** Every opener goes to a screen that checks the gate itself, or goes to the paywall. Template builder: checked in `openCaptureSettings` and again inside `TemplateBuilderScreen:109`. Add asset: `AddAssetScreen:53`. Backup schedule/history: `BackupScreen:224`. Money tab assets: `onOpenAssetsPaywall`. Charts: the existing `insightsTabRoot`/`chart_gate`. Exports (`onExports`) are not wired, so they can't be reached. I found no screen that can be opened without its gate. The paywall trigger and the Gold sign-in opener push onto the root navigator.
- **Onboarding runs only on first launch.** The onboarding shows only when `setup_installed_on` is null (`onboarding_gate.dart:27-34`). A read error counts as "not needed", so the user can't get stuck in onboarding. The shell (and so Home, which also writes the marker) is not built while onboarding shows. `_finish` writes the marker on every exit path: Start on iOS, skip, done, scan results, restore. Installs from earlier builds already have the marker, because Home's `setupInstalledOnProvider` wrote it. So the onboarding can't loop and doesn't come back on an existing install.
- **Restore from Welcome.** Welcome shows only when the marker is absent. The confirm for a phone that already holds data is being added by the fix agent, so I note it and don't block on it. See m1 for the one case where this matters.

Findings:

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| m1 | minor | `app/lib/app/onboarding_gate.dart:49-57` | If writing the marker fails, `_finished` is set only in memory. The next launch shows Welcome again on a phone that may already have captured data (the setup granted SMS), and "I already use Zaghlol" would restore over it. The pending restore confirm covers this. | Make sure the fix agent's confirm counts existing transactions/raw rows, not the marker. |
| m2 | minor | `app/lib/app/app_config.dart:22-25` | `externalUrlOpenerProvider` does nothing. Terms, Privacy and Manage subscription on the paywall, and "Update app" on the restore screen, do nothing when tapped. Store review requires working terms and privacy links in the subscription flow. | Follow-up: add `url_launcher` and override the opener before store submission. |
| m3 | minor | `app/lib/app/app_navigation.dart:281-289` together with `features/onboarding/presentation/android_setup.dart:525-526` | In the degraded variant, "Continue" calls both `onSkipped` and `onDone`. From Finish setup, that runs `maybePop` twice and also pops the screen underneath (Settings or Home's pushed route). During onboarding it pushes scan results onto a Navigator that is being torn down. | Pop once (for example, let `onDone` pop and make `onSkipped` only record the skip). |
| m4 | minor | `app/lib/app/app_navigation.dart:140-150, 194-198` | The budget category drill-down and "All card transactions" change the shared `txnListFilterProvider` / `cardFilterProvider`. The Transactions tab and Home keep those filters after the user goes back. | Follow-up: scope the filter to the pushed route, or reset it on pop. |
| n1 | nit | `app/lib/app/onboarding_gate.dart:107-113` | Skipping one step ends the whole onboarding, with no scan results. This matches the `AndroidSetupScreen.onSkipped` doc, so I'm only noting it. | None. |

---

## WIRE-SVC (C4, data safety): service wiring

**Verdict: APPROVED**

What I checked:
- **Pause gate (`ingestion/ingestion_pause_gate.dart`).** `guard` checks `_paused` and increments `_active` with no await in between, so a write can't slip in after `pause` has returned. `pause` waits only for writes already running, and gives up after 30 s (`IngestionBusyException`). So the wait is bounded and it can't hang.
- **Deadlocks.** The restore's own writes don't go through either gate. The sync gate and the ingestion gate are separate objects, and no guarded write waits on a gate. A cycle that is between batches sees `_active == 0`. Its next batch is refused as `DB_WRITE_FAILED` (transient), so `ingestion_cycle.dart:212-216` returns `retry` without an ack and the spool keeps the entries. The inbox scan ends as failed. While the UI engine is attached, Android never starts the headless engine (`CaptureRuntime.kt:89`), so the headless store needs no gate.
- **A failed restore always reopens the gates.** `DbRestoreSideEffects.pause` resumes both gates if pausing throws. `restore_flow.dart:183-188` calls `effects.resume()` in `finally`. `resyncCatalog` reopens the sync gate before its forced run. After the swap the gate providers survive the database invalidation, and the rebuilt coordinator re-registers its `onResume` drain.
- **Custom templates in the registry.** A row that doesn't decode, doesn't parse or doesn't compile (`compilePattern(...)!` / `fromWire(...)!` throw) is skipped inside the `try`. If the table can't be read, the base registry is returned. Nothing is logged. The built-in institutions come first, and `registryVersion` doesn't change.
- **T-076 re-parse hook (`custom_template_reparse.dart:26-31`).** It resets `registry_version` only where `parse_status = 'review'` and the sender and channel match a template. A review the user resolved has raw status `parsed` or `dismissed` (`review_repository.dart:104,157,217`), so a confirmed transaction is never reset. `ReparseJob` then only converts review rows into new transactions, closes the review item as `reparsed`, and never rewrites an amount, status or user-verified row (T-076 guards, `ingest_raw_messages.dart:392-410`). Rows are stamped afterwards, so a second run does nothing (tested).
- App version, iCloud adapter and settings ports: the build defines (`kClientAppVersion`/`kClientAppBuild`) feed the backup header, About and the sync. iCloud is used on iOS only, and `uploaded == false` is not counted as a confirmed backup.

Findings:

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| m5 | minor | `app/lib/features/capture/application/custom_template_reparse.dart:23-46` | The re-parse writes to the database outside `ingestionPauseGateProvider`. If the user saves a template and starts a restore while up to 5000 rows are still being re-parsed, the writes go to the database being replaced. They are lost or fail, but those tables are overwritten by the restore anyway, so there is no data loss. | Follow-up: run each `_ingest.reparse` under the gate, or skip the hook while the gate is paused. |
| m6 | minor | `app/lib/features/capture/application/template_builder.dart:294` | `save()` awaits the whole re-parse before it returns, so the builder's caller waits for up to 5000 message transactions. | Follow-up: `unawaited` the hook (it is best effort already). |
| m7 | minor | `app/lib/features/capture/application/custom_template_reparse.dart:35-44` | No `onPersisted` (T-089 transfer pairing) is passed. A transfer leg that the re-parse converts isn't paired until its next trigger. | Follow-up: pass the pairing hook, as the T-076 job does. |
| m8 | minor | `app/lib/ingestion/ingestion_pause_gate.dart:56-61` | After a timeout the gate reopens without calling the resume listeners. The drain refused during the 30 s wait runs only on the next native trigger. Also, a timeout during a second, concurrent `pause` reopens the gate under the first caller. | Follow-up: call `resume()` on timeout, and count the pausers. |
| m9 | minor | `app/lib/features/settings/presentation/settings_ports.dart:40` | Catalog and prices show the same time (the last successful run of any kind). | Accept for v1, or record the two separately. |
| n2 | nit | `capture_providers.dart` / `sync_providers.dart` | The sync gate is an `IngestionPauseGate`. | Rename it to `PauseGate` when convenient. |
| n3 | nit | `custom_template_reparse.dart`, `template_builder.dart:9`, `sync_orchestrator.dart:20`, `sync_providers.dart:10` | The imports are out of order (a relative import sits above `dart:` / `package:`). | Run import sorting. |

Security: no content, sender, template text or id is logged or put into an error. Nothing new goes off the device.

---

## Fix list (blocking only)

| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| None | | | |

Nothing blocks. The Welcome restore confirm, which another agent is adding now, is tracked outside this report. m1 depends on it.
