# Batch 20c review (batch/2026-11-14-20)

Reviewer: `code-reviewer` (Opus; code and security in one pass, PO cost rule 4). Date: 2026-11-14.
Scope: T-064, T-171, T-173, WIRE-2, WIRE-3. These branches were cut from `927e37ff` (the batch head at that time), so each diff is `git diff 927e37ff...origin/task/<branch>`. T-166 is out of scope here (its fix agent is still reworking it).

Tests run on the merged tree (`ecddd8d0`):
- `flutter test --exclude-tags benchmark,golden test/privacy`: 21 pass, including the sign-out test that is no longer skipped.
- T-064 checker and provider tests, plus `test/features/gold/application/entitlement_test.dart`: 58 pass.
- `test/features/notifications`, `delete_everything_test`, `privacy_delete_test`, `test/features/transfers`, `test/features/widgets_bridge`, `test/features/ingestion/presentation`: 151 pass.
- `test/app`, `test/core/ui/shell`, `test/features/capture`, `test/features/home`, `test/features/settings`, `test/core/settings`: 438 pass.
- `flutter test --tags benchmark --concurrency=1` (app, serially, as the new `perf` job runs it): 9 pass in 4 min 43 s.
- **Planted leaks** (each one reverted afterwards): a `print("leak")` in `lib/app/app_config.dart`, a `UserDefaults(suiteName:)` in a new `ios/Runner/*.swift`, and `firebase_crashlytics` in `pubspec.yaml`. All three turned the matching privacy test red, with the right file:line or package name.
- Swift and Kotlin were read, not built.

**Merged pigeon (capture):** the batch tree has one `ShortcutSetupStatus` codec type (135), and `CaptureCapabilities` moved to 136. Dart, Swift and Kotlin agree. `IosCaptureHost` is the only `IosCaptureHostApi` implementer, and it has `getShortcutSetupStatus`. The `ShareImageHost.swift` build file is in the Runner Sources phase.

---

## T-064: Shortcut setup checker (C3): APPROVED

What was checked:
- **Only times cross the channel.** `ShortcutSetupStatus` holds two nullable epoch-ms ints and nothing else. `IosCaptureHost.getShortcutSetupStatus` reads T-063's encrypted `IntentRunLog` (`u8 v | i64 | i64`). With no container it throws a code-only `NOT_AVAILABLE`. The Dart port maps errors through `PlatformFailure.fromChannel(code)`, so no message is passed on.
- **Contract change.** `platform-channels.md` drops `keywordsSeen` (native records no content, so this is a privacy improvement) and `shortcutInstallUrl()` (now the Dart constant `AppLinks.shortcutInstall`). Both are documented in the doc and in the pigeon comment.
- **The 7-day rule is reused.** `deriveShortcutSetupReport` calls T-066's `deriveIosSetupStatus` once per automation. The baseline provider was moved out of the T-066 provider without changing its behaviour. No rule is duplicated.
- The AC "≤ 3 steps" and the real iCloud link are PO and device inputs (`AppLinks.shortcutInstall` is a `TODO` placeholder). This is acceptable for code-complete, but it must be tracked before release.

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 064-1 | minor | `app/lib/app/app_config.dart` (`shortcutInstall`) | The placeholder `https://www.icloud.com/shortcuts/TODO` will ship if nobody replaces it. | Add an FU (owner PO / T-066) with a release-checklist item, or a test that fails in release mode while the value ends in `TODO`. |
| 064-2 | minor | `app/ios/Runner/Capture/IntentRunLog.swift:48-52` (consumed by `ios_shortcut_checker.dart:72`) | If the file cannot be read (I/O, a bad decrypt) the read returns empty `Runs()`. The checker then reports "never ran" and, after 7 days from the baseline, flags both automations. The result is a false nudge, not a silent failure. | When the file exists but cannot be read, report it as unreadable and map it to `unknown`, not to null times. |
| 064-3 | minor | `app/lib/features/capture/domain/ios_shortcut_checker.dart` | A user with no Apple Pay never runs the Wallet automation, so the Wallet automation is flagged for good. | Product decision for the UI task: either flag Wallet only once it has run at least once, or let the user say "I don't use Apple Pay". |
| 064-4 | nit | — | `shortcutSetupReportProvider` has no consumer yet. The WIRE-3 nudge uses the overall `iosSetupStatusProvider`. | The UI task should name the flagged automation. |

---

## T-171: Privacy suite (C4 test): APPROVED

What was checked:
- **The BR-SYNC-03 allow-list matches the SRS and backend-api.** `support/br_sync_03.dart` was written by hand, not generated from the DTOs, and has closed schemas per platform. I checked it against SRS BR-SYNC-03 and D-45, D-48, D-55, D-62 (including v1.8 R5-9) and NFR-SEC-08, and against backend-api §4.3 and §4.6:
  - attestation on restore only (verify needs none, backend-api "Verify needs no attestation");
  - iOS `seatKeys`: at most 1 entry on verify (element 0), at most 5 inside `attestation` on restore, and at most 5 at the top level on sign-in. Android has no `seatKeys` anywhere;
  - `Zaghlol-Time-Nonce` on exactly the six anchoring requests;
  - contributions limited to `merchantNorm`, `institutionCode` and `categoryCode`, and bank requests to name, country and channel;
  - the D-48 cursors classed as versions;
  - every leaf scalar, no floats, https only, no query string.

  Every wire class is tied to a `ServerKnows` entry shown on that platform. Nothing device-related is on the list beyond the D-45/D-55/D-62 additions.
- **The scans fail on real plants,** not only in their own self-tests (see the planted leaks above). The flow tests run the production services and adapters. They cover a stale outbox row with an extra `amountMinor`, P2P and personal-data contributions, and canaries in the amount, card, merchant, message and IPA. Each request must stay inside the allow-list and carry no canary.
- **The source guards are not too loose.** `storageAllowed` is empty. `loggingAllowed` has two entries, both reasonable: the generated `GeneratedPluginRegistrant.java` (not committed) and the dev-flavour `SpikeLog.kt` (codes only). The guards cover all of `lib/` and every native root, and a folder-coverage test stops a new folder from being missed.
- **F1 sign-out fix (glance):** the token is read before the local delete and passed explicitly to `BackendClient.signOut`. The stored-token path is unchanged for other operations, and the fix has a unit test plus the flow test.

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 171-1 | minor | `app/lib/core/backend/transport.dart:82` | The allow-list checks the `BackendRequest` before `dart:io` sends it. `HttpClient` then adds `user-agent: Dart/<sdk> (dart:io)`, `accept-encoding` and `host`, which the suite never sees. The UA carries no device data, but `allowedHeaders` claims to be the complete header set. | Set `_client.userAgent = null` in `IoBackendTransport`. Add one transport test against a loopback `HttpServer` that asserts the wire header names are a subset of `allowedHeaders` plus `host`, `accept-encoding` and `content-length`. |
| 171-2 | minor | `app/test/privacy/source_guards_test.dart:58,82` | Ways around the guards: `print (x)` with a space before `(` is not matched. `code()` cuts a line at the first `//`, even inside a string literal (`'a//b'; print(x)`), which hides the rest of the line. `.m` and `.h` files are not scanned (only the bridging header exists today). | Allow `\s*` before `(`. Skip `//` inside string literals, or scan both the raw and the stripped line for logging calls. Add `.m`/`.mm` to the scanned extensions. |
| 171-3 | minor | T-171-F2 (`share_providers.dart`, WIRE-3 copies) | The share PNG is plaintext in the cache or tmp folder. This is a user-initiated export and is excluded from OS backups, but a crash leaves it on disk. | FU: sweep the `share_*` files and `cache/shared_images/` at startup (see WIRE-3 W3-1), and list the share PNG as a reviewed exception in security-model. |

---

## T-173: Performance (C2): APPROVED

What was checked:
- **Benchmark tag.** Every timing upper bound in `packages/zaghlol_parsing/test` and in the app's catalog and categorizer tests now carries `benchmark`. Where a test also checked behaviour (ask parser, voice parser, regex safety), it was split, so the behaviour assertion still runs untagged. Test files that were already tagged at file level (FTS, search, ingest, inbox scan, chart) are unchanged.
- **`perf` job.** It runs `dart test --tags benchmark -j 1` and `flutter test --tags benchmark --concurrency=1` with `pipefail`. The summary step is `if: always()` and cannot fail, because its last command is `|| true`. The static job now excludes `benchmark` for `zaghlol_parsing`. I ran the app half serially: green in under 5 minutes, all numbers well under their budgets (search p95 60 ms against 200 ms, chart medians ≤ 13 ms against 100 ms, categorizer p95 8.5 ms).

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 173-1 | minor | `.github/workflows/app-ci.yml:231-250` | The job **can still block on a flake**. Nothing retries a test or makes the job advisory, so one noisy-neighbour spike turns app-ci red and blocks the batch gate. Running serially lowers the risk but does not remove it. | Either add `retry: 2` in both `dart_test.yaml` files, or add `--retry 2` to the two commands, so only a repeated failure fails the job. Or mark the job `continue-on-error: true` until the budgets have run for a week. |
| 173-2 | minor | `app/test/features/backup/crypto/passphrase_test.dart:199` | `lessThan(50)` ms is an untagged timing assertion in the parallel run. | Tag it `benchmark`, or raise the bound to about 2 s: a 4 GiB Argon2 run would take far longer, so the test still proves the point. |
| 173-3 | nit | `.github/workflows/app-ci.yml:250` | `--tags benchmark` also runs the 50k-row FTS benchmark that db-platform already gates. That adds about 45 s and runs the same gate twice. | Add `--exclude-tags golden` and leave out `test/core/db`, or accept the duplicate run. |

---

## WIRE-2: Notifications, pair suggestions, widget copy, Delete everything (C3): CHANGES_REQUESTED

What was checked:
- **Duplicate-charge hook after commit.** `ProviderIngestStore.afterBatch` runs after `IngestRawMessages.call` has returned, so the batch is committed. It is wired only in the UI engine (the coordinator and the inbox scan). It swallows its own failure, so the ack never fails. After a manual add, `AlertingTransactionRepository.afterAdd` runs after the insert and swallows errors too. The query covers posted, non-internal expenses, one currency per row; no amounts are summed across currencies.
- **Weekly summary on resume.** It runs at start and on every resume. A 7-day interval is stored in settings, and the time is written only after a successful run. The summary is per currency (`WeeklySummaryAlert.run` loops over currencies, and a zero total is skipped). No conversion.
- **Reimbursement hook in ingest.** It runs inside the message savepoint and only for inserted rows. It catches its own failure, and Drift rolls back the nested savepoint first. It only opens a review item; it never links anything.
- **FX pair accept.** There is one candidate (from `transfer_pairing`), and `TransferPairingUseCase.link` changes no amount. No conversion.
- **Widget copy.** It now comes from ARB in both languages (`widgetOpenZaghlol` added). `widget.clear()` runs after the wipe, whether or not it finished, and it swallows `PlatformException`.
- **`WipeIncomplete`.** If the wipe still has failed steps after one retry, `WipeIncomplete` is thrown and the app does not restart. The marker is left for the next launch (the T-166 semantics belong to T-166).

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| W2-1 | **major (money)** | `app/lib/features/ingestion/presentation/review/review_providers.dart:94-106` | **Accept links a candidate the user never chose.** `suggestReimbursement` stores up to 5 candidates, ordered by `occurred_at DESC`, so "first" means "most recent", not "best". The card (`SuggestionCardModel`, `review_screen.dart:~272`) shows only the incoming transfer's amount and no candidate expense. A swipe-accept then assigns the whole remaining incoming amount to `candidates.first`. That changes the net spending of an expense the user never saw (FR-TXN reimbursements). The comment says "the card names no other choice", but that is the problem. | Accept must link only an expense the user picked. Either (a) show the candidate expenses on the card (amount, merchant, date) and pass the tapped id to `acceptReimbursement`, or (b) enable one-swipe accept only when `candidates.length == 1` and show that expense on the card; with more than one candidate, accept opens the transaction's manual link sheet instead. Test: a payload with 2 candidates. Accept must not create an `offset_links` row for `candidates.first` unless that id was chosen; with option (b) the card must offer no direct accept. |
| W2-2 | **major (Delete everything)** | `app/lib/features/settings/presentation/privacy_screen.dart:228` | **The failure path pops the wrong route.** The progress dialog is shown with `showDialog`, which uses the **root** navigator. PrivacyScreen is pushed onto the home branch's **nested** navigator (go_router `StatefulShellRoute`, via `pushScreen`, which calls `Navigator.of(context)`). So `Navigator.of(context).pop()` pops PrivacyScreen and leaves the progress dialog up. That dialog cannot be dismissed (`PopScope(canPop: false)`, `barrierDismissible: false`), so the user is stuck on a spinner after a partial wipe and has to kill the app. The widget test uses a single navigator and cannot catch this. | Use `Navigator.of(context, rootNavigator: true).pop()`, or keep the dialog's own `BuildContext` and pop that. Test: push PrivacyScreen inside a nested `Navigator` (or the real router) with a failing wipe. Expect the progress dialog to close, PrivacyScreen to stay, and the snackbar to show. |
| W2-3 | minor | `app/lib/features/ingestion/presentation/review/review_screen.dart:~272` | The reimbursement card shows the incoming transfer with `isIncome: false`, so it reads like spending. | Pass `isIncome: true` for `reimbursement_suggestion` (fold this into W2-1). |
| W2-4 | minor | `app/lib/features/notifications/application/notification_providers.dart:256` | The first launch runs the weekly summary at once (`last == null`), and then every 7 days from the first launch rather than on a fixed weekday. | FU: set `last` to now on the first run without notifying, or anchor the summary to the weekday the spec asks for. |
| W2-5 | minor | `notification_providers.dart:221-235` | Category names are read once when `weeklySummaryAlertProvider` is built. A renamed or new custom category shows the stale name, or nothing, until the provider is rebuilt. | Read the names inside `run`, or watch the categories. |
| W2-6 | minor | `app/lib/features/security/application/delete_everything_providers.dart` (`wipeEverythingOverride`) | If a debounced widget publish was pending from before the wipe, it can still fire after `widget.clear()` on the `WipeIncomplete` path, where nothing restarts. It would republish the old snapshot. | Cancel or invalidate `widgetBridgeWiringProvider` before `clear()`. |
| W2-7 | nit | `delete_everything_providers.dart` imports | The import order is mixed (widgets_bridge comes before gold). | — |

---

## WIRE-3: Share handlers, Gold badge, iOS nudge, Account row (C3): APPROVED

What was checked:
- **Android FileProvider.** `exported="false"`, `grantUriPermissions="true"`, and the paths file has only `<cache-path name="shared_images" path="shared_images/"/>`. The handler accepts only a canonical path inside `cacheDir`, so `..` and symlinks are refused. It copies the PNG into `cache/shared_images/` and grants a read on that one URI through `ACTION_SEND`; `startActivity` moves the grant into the chooser's ClipData. Each call sweeps copies older than 1 hour. When a finishing activity tears down the engine, all copies are swept. The error detail is the exception class only, and the path is never logged.
- **iOS share host.** The PNG is copied to the app tmp folder with a UUID name, shown in `UIActivityViewController`, and the copy is removed in the completion handler. The iPad popover has an anchor. The registrar is registered in `AppDelegate` and the file is in the Runner Sources phase.
- **Gold badge and routing.** `AddSheet` shows the Gold chip and a11y suffix only for Free. `wiredAddSelected` sends Free to the paywall and Gold to S-44. `AddAssetScreen` also checks `isGold` itself (T-121), so Free cannot reach S-44 by any route.
- **iOS nudge snooze.** It is shown only when `iosSetupStatusProvider.shouldNudge`. Snoozing writes `now + 7 d` to the encrypted settings. Copy is in both ARBs, with an Arabic plural and the digits mode respected. Goldens exist for ar and en.
- **Settings Account row** opens S-69 through `AppScreens.account`.

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| W3-1 | minor | `ShareImageRegistration.kt:24,80` and `ShareImageHost.swift:37` | Copies are not swept at startup. On Android, after a crash or process kill, a plaintext PNG with spending figures stays in `cache/shared_images/` until the next share at least 1 hour later. On iOS, a tmp copy stays if the app is killed while the sheet is open. | FU (with 171-3): sweep `shared_images/` and tmp `share_*.png` once at engine start. |
| W3-2 | minor | `ShareImageHost.swift:56` | If `present` does not complete (for example, another controller is being dismissed), `result` is never called. The Dart future then hangs and the staging file is never deleted. | Call `result` once on every path. Return the result right after `present(...)` is called, or add a guard that the top VC is not already presenting. |
| W3-3 | minor | `docs/03-technical/platform-channels.md` | The `zaghlol/share` MethodChannel (`shareImage({path})`, error codes `bad-args`, `bad-path`, `share-failed`) is not documented (CLAUDE.md §8). | Add a short section. |
| W3-4 | minor | `app/lib/features/capture/application/ios_nudge_providers.dart:24` | The provider reads the clock but nothing recomputes it when time passes. A snooze that runs out while the app stays in the foreground does not bring the nudge back until another dependency changes. | Invalidate the provider on resume (it already runs `alertsResumeProvider`). |
| W3-5 | nit | `app/lib/core/ui/shell/add_sheet.dart:84` | The a11y suffix is joined with a Latin `', '`. In Arabic it should be `'، '`, or a localized pattern. | Use an ARB pattern such as `homeQuickAddAssetGoldA11y`. |
| W3-6 | nit | `app_navigation.dart` (`wiredAddSelected`) | Free users go to `screens.paywall` directly, not through `paywallTriggerProvider(GoldCapability.investmentAssets)`, so the paywall opens without its capability context. | Use the trigger, as `AddAssetScreen` does. |

---

## Fix list (blocking only)

| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| WIRE-2 | `app/lib/features/ingestion/presentation/review/review_providers.dart:94-106` (+ the `SuggestionCardModel` card in `review_screen.dart`) | Accept on a `reimbursement_suggestion` must link only an expense the user chose. Show the candidates and pass the tapped id, or allow one-swipe accept only when there is exactly one candidate, shown on the card; otherwise send the user to the manual link sheet. | A payload with 2 candidates: accept does not create an `offset_links` row for `candidates.first` unless the user chose it. With 1 candidate, the card shows that expense and accept links it. |
| WIRE-2 | `app/lib/features/settings/presentation/privacy_screen.dart:228` | Pop the progress dialog on the root navigator: `Navigator.of(context, rootNavigator: true).pop()`, or pop the dialog's own context. | PrivacyScreen pushed inside a nested `Navigator`, with a wipe that throws `WipeIncomplete`: the progress dialog is gone, PrivacyScreen is still shown, and the `privacyDeleteFailed` snackbar is visible. |

## Lead delta check (T-171 F1, sign-out reaches the server)

Commits f8d83d71 and 099ae177: `EntitlementService.signOut` reads the account token into memory before deleting the stored tokens, then passes it to `BackendClient.signOut(accountToken:)`, which sends it in the account header. Offline sign-out still drops the tokens first. The privacy flow test "sign-out reaches the server" is unskipped and fails without the change. Verdict: APPROVED.
## Delta re-review (WIRE-2 fixes)

Commit `48374ab9` against its parent.

1. Pair suggestions: **fixed.** `isPair` cards have `canAccept == false`, so there is no swipe-to-accept and no a11y accept action. Bare `accept()` returns without linking for pair items. The only link path is `_PairCard` Confirm, which calls `acceptCandidate(itemId, txnId)`. Confirm is disabled until a radio is chosen (pre-selected only when there is exactly one candidate). `acceptCandidate` refuses ids not in the payload `candidates`. Candidate amounts are the candidate's own `Money` (own currency). The ambiguous-refund path is unchanged. No keyboard shortcut path exists.
2. Failed-wipe dialog: **fixed.** `Navigator.of(context, rootNavigator: true).pop()`.

Tests: `flutter test --exclude-tags benchmark,golden test/features/ingestion test/features/settings test/features/transfers` gives 304 passed.

Minor (follow-up, not blocking): `_PairCard` shows the candidate with `merchantRaw` in the account-label slot.

**Verdict: APPROVED.**
