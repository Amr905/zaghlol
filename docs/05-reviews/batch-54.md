# Batch 54 review

Branch `batch/2026-11-21-54`, five lanes. Reviewer: code-reviewer (Opus, code + security). Tests run: `flutter test --exclude-tags golden test/features/export_import test/features/gold test/features/transactions test/app test/privacy` -> 642 passed, 0 failed (DB tests opened the encrypted DB fine here). Analyze is left to CI. Golden diffs not reviewed.

## Lane 1: task/B54-fu-server (FU-275 server items) - APPROVED
- Workflow split is right: `packages: write` appears once (build job); the ssh `deploy` job has `contents: read`, gets the image ref via `needs.build.outputs.ref`, and uses the optional `GHCR_PULL_TOKEN` (empty = public package). The new `deploy-previous-test` job greps for both properties.
- `deploy.sh`: redeploying the running digest falls back to `BACKEND_IMAGE_PREVIOUS`, and blanks it if that is also equal. Test covers redeploy and normal deploy.
- `site-pages.yml`: placeholder preview is artifact-only (3-day retention); `deploy` is skipped with `allow_placeholders`.
- minor: a private GHCR package with no `GHCR_PULL_TOKEN` fails at pull on the server. Documented in deployment.md; nothing to change.

## Lane 2: task/B54-privacy-docs - APPROVED
Checked against code and docs: the `accounts.email` column and the `SignInService` upsert call (email stored until account deletion), no certificate pinning (security-model §6), contribution `institutionCode` (BR-SYNC-04), D-42 consented online recognizer, D-57(b) ticket wording, NFR-PRIV-06 retention. Resolutions match. `AppLinks.support` + `app_links_test.dart` fine. CLAUDE.md §1 now matches D-33 and CHARTS-FREE.
- minor: `privacy-consistency.md` row 8 still says "CLAUDE.md not edited (Lead/PO to apply)", but the edit is in this diff. Update the row.
- minor: paywall still lists `goldPaywallBenefitCharts` unconditionally (row 8 follow-up); keep as follow-up.
- minor (self-flagged): "the EF store writes the column" rests on the call site only. Accepted.

## Lane 3: task/B54-fu-app (FU-274/275 app items) - APPROVED
- `tokenMaxLifetimeSeconds` / `tokenMaxGraceSeconds` are single-source in both parse and cached-claims checks.
- Paywall `_retry`: the retry button only renders for `attestHelp` / `attestPlayServices`, and those messages come only from restore. `_buy` and `_restore` both guard `_busy`. `_lastAction == purchasing` is set only in `_buy`, and `_buy` never sets a retryable message. No double-charge or restore loop reachable. nit: `_lastAction` declared after its use; place it with the other fields.
- `AmountRepairEvents.discard` is wired through `onRollback` on any exception from the edit; test present. `UpsellCap` serialises via a promise chain, and an error in one check doesn't poison the chain. `flatBorder` swap is equivalent (same dark-only outline).
- nit: the `discard` comment says "drop the event" but it clears all pending. Fine since edits are serial.

## Lane 4: task/B54-fu240c (export screen, target Change, PDF password) - CHANGES_REQUESTED
- Export screen: Free gets a preview only (the service is called with `EntitlementState.free`, no bytes); Export for Free opens the paywall; Gold shows the "not encrypted" notice; the preview masks amounts with `kAmountMask` when hide-amounts is on; the save goes through the system dialog, and backing out leaves idle with nothing written. OK.
- PDF password: kept only in a local in `_pick`, passed per call, controller cleared and disposed, `obscureText` with IME learning off, `ImportFlowException.toString` prints only the kind. Never logged or stored. OK.
- **major** `import_ports.dart` (`CsvImportRunner.commit`) + `import_source_screen.dart:~116`: `targetCardId` is accepted and ignored by the only real runner, yet the summary "Change" action is offered (a card origin with more than one card) and the done screen then names the newly picked card (`target?.name`). For a CSV import the rows go where the file says, so the UI reports a card the rows were not filed under. Required change: either hide "Change" until a runner that honours `targetCardId` exists (pass `onTargetChanged` only then), or apply the target in the CSV path. Also show the done-screen card name only when it was applied. Add a test that fails without it.
- minor: `import_target_password_test` covers the dialog and sheet; there is no test that a picked target reaches `commit` with an id different from the default for a real runner. It would have caught the major above.
- minor: `ExportScreen` loads the preview once per screen; it does not refresh after returning from import. Harmless.

## Lane 5: task/B53-t193-ac5 (T-193 AC5 emulator run) - APPROVED
- `notification_taps.dart`: `_open` now waits for the root navigator (100 x 100 ms, bounded) and re-checks `mounted`; after the timeout it proceeds anyway, so the target handler deals with a missing context (the confirm path returns false when there is no context). Test `notification_tap_early_test.dart` covers wait-then-open and give-up. Fix is correct and minimal.
- `notification_taps_debug.dart`: every output is behind `kDebugMode` (`notifProbe` guard, and the call site `if (kDebugMode) unawaited(debugPostColdFixtures(ref))`). A compile-time constant, so tree-shaken in release. Probe lines carry only a target type name, booleans and fixed text; no route string, bill name or amount. Fixture titles are literal English synthetic strings, debug only. The `loggingAllowed` entry for that one file is an acceptable, narrowly scoped guard exception (path-exact, with reason). It does weaken the guard for that file only; the file is 56 lines, so I read it fully.
- minor: debug helper code sits in `lib/` and compiles in profile/debug sources; it reads `docs/sig/post_cold` from the app documents directory in debug builds only. Acceptable.
- Script and workflow: `NOTIF_ONLY` runs only on manual input or `ci/B53-t193*`; path filters added. The script greps logcat for `NOTIF_PROBE` lines only. CI proof: device-flows 44899843561, app-ci 44899843562. Result doc `T-193-device.md` is consistent with the diff.

## Verdicts
| Lane | Verdict |
|---|---|
| B54-fu-server | APPROVED |
| B54-privacy-docs | APPROVED |
| B54-fu-app | APPROVED |
| B54-fu240c | CHANGES_REQUESTED (1 major) |
| B53-t193-ac5 | APPROVED |

Minors and nits go to FU-276.

## Lead delta check (fix round)

- B54-fu240c major: CSV rows carry their own account, so `ImportRunner.supportsTargetCard` was added; `CsvImportRunner` returns false, "Change" is hidden for it and the done screen names the real card. Tests: CSV runner reports false; no "Change" when unsupported. **APPROVED.**
- FU-276 minors fixed in the same pass: paywall "all charts" line hidden while `GoldGate.chartsOpenToFree` (test, ar+en); `_lastAction` order; privacy-consistency row 8. No follow-up left open from this batch.
