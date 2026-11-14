# Batch 18a review (batch/2026-11-14-18)

Reviewer: `code-reviewer` (Opus; code and security in one pass, PO cost rule 4). Date: 2026-11-13.
Scope: T-145, T-151, T-152, FU-121, T-009. Each task was reviewed on its own commits only, because the task branches build on each other:
T-145 `bb8fbc1b`, T-151 `82a6aa1d..a3707e35`, T-152 `10495e92`, FU-121 `fe943e7a..73cfcff5`, T-009 `f83074ce..24c2d5a3`.

Tests run on the merged tree:
- `flutter test --exclude-tags benchmark,golden test/features/gold test/features/backup test/ingestion test/core/settings`: 435 pass, 1 fail (see the merged-tree note).
- `dart test test/guard` in `packages/zaghlol_parsing`: 447 pass.
- Kotlin, Swift and on-device checks were not run here (they need the PC runner, GitHub or a device).

**Merged-tree note (not one of my tasks, but it is red):** `test/core/settings/settings_repository_test.dart` "every key is in the allKeys table" fails with 38 declared keys against 37 in the table. T-152 added its 5 keys to the table correctly. Another task in the batch added `Settings.setupInstalledOn` (T-056, by the look of it) without adding a table row. The Lead should send this to that task's fix agent.

---

## T-145: in-app purchase, verify, retry, restore (C4) — CHANGES_REQUESTED

What was checked: Gold comes only through `EntitlementService.handleBody`, which checks the signature, the install binding and trusted time. The service never calls `applyVerified`, and an `active` answer without a verified Gold phase fails closed. Completion happens only after an `active` answer. The `Idempotency-Key` and the iOS seat proof are stored in the encrypted `secure_state` outbox and reused on every retry, so the body stays byte-identical. On restore, the strict parser runs before any hash is made. The iOS seat signatures come before `clientDataHash`, which comes before `attest`. `SEAT_KEY_MISMATCH` gets one retry without seat keys and sets the R5-6 flag only after that retry succeeds. `DEVICE_ATTESTATION_FAILED` gets one retry (iOS with a forced new key, and only when no `attestationObject` was sent). `MOVE_COOLDOWN` is stored and never retried. A restore is never sent without a proof. Nothing logs, and every `toString` hides its values.

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 145-1 | **major** (money) | `app/lib/features/gold/application/gold_store.dart:149-153`, `:112-124`; `purchase.dart:283-288` | **A purchase verified after an app restart is never acknowledged on Android, so Play refunds it after 3 days.** `in_app_purchase_android` 0.5.5 does not send unacknowledged purchases to `purchaseStream` at start; only `onPurchasesUpdated` and `restorePurchases()` feed it (`in_app_purchase_android_platform.dart:45,246`). `GoldStore.start()` only listens. The flow breaks like this: the backend is down at purchase, the user closes the app, and on the next start `retryDue()` verifies the outbox entry and calls `_verified(e, live: null)`. `complete()` finds no `_live` handle and returns without doing anything (`if (live == null) return;`). The service treats that as done and **removes the entry**. Nothing is acknowledged, the purchase is auto-refunded and Gold is revoked. This is exactly the AC "backend down at purchase → Gold after it returns". On iOS the same early return races with StoreKit's redelivery: the entry is removed, then the redelivered transaction creates a new entry with a **new Idempotency-Key and a second seat signature**. That breaks "idempotent retry" and "seat proof signed once". The test fake (`gold_test_support.dart:45`) completes any purchase, so the tests can't see this. | (a) `GoldStore.complete` must report whether it actually acknowledged or finished the purchase (return `bool`, or throw when there is no live handle). On "not completed", `PurchaseService` keeps the entry at `verified` and does not remove it. (b) On Android, `start()` must call `queryPastPurchases()` and emit the Gold purchases that are **not yet acknowledged** (`!billingClientPurchase.isAcknowledged`) as `purchased`, so `_onPaid` finds the `queued`/`verified` entry and completes it without a second verify. Acknowledged purchases must not be emitted, or every start re-verifies them. (c) Change the fake store so `complete()` fails (or returns false) for a purchase it never delivered. |
| 145-2 | minor | `purchase.dart:257` | Backend-api §4.3 (line 355) defines a final answer for a re-verify from a non-holder or on a vacant seat: `active`, `seatHeldElsewhere:false`, and a token **without** the purchase. The service treats that as "retry later" for 14 days (back-off up to every 6 h) and never finishes the iOS transaction. | Follow-up: map that answer (an authenticated `active` that has a token, but the phase isn't Gold) to a typed outcome. Complete the purchase, because the backend has verified it, and offer Restore. |
| 145-3 | minor | `purchase.dart:84`, `:163`, `:174-181` | `unawaited(_serial(...))` has no error handler. A `PlatformException` from `_store.complete` (the `verified` branch) or from `_seats.prove` becomes an uncaught zone error, and the rest of that update batch is skipped. | Catch inside `_onUpdates`/`_attempt` and leave the entry in its stage. |
| 145-4 | minor | `restore.dart:216`, `:235` | `proof.token!` / `proof.keyId!` / `proof.assertion!` throw a `TypeError` if the host returns an incomplete proof. That escapes `restore()` as an untyped error. | Treat it as `AttestationException(unavailable)` and return `RestoreAttestationHelp`. |
| 145-5 | minor | task deviation 1 | There is no native wake-up, so AC1 ("within Google's 3-day window") holds only if the user opens the app within 3 days. | Lead: file FU `purchase-retry-worker` and get a PO decision, as the builder asked. |
| 145-6 | nit | `app/lib/main.dart` import | `gold_providers.dart` is imported before `catalog_sync` (not alphabetical). | — |

On-device items still open (builder deviation 2; recorded, not blocking): the StoreKit-config test of `hasStoreKitTransactionFor`, the release-build user-CA check, and sandbox purchases. These have to be done before T-145 can be marked DONE.

---

## T-151: iCloud backup host (C4) — APPROVED

What was checked:
- **Verify-then-prune.** The upload goes to a `.partial` created with `O_EXCL`, with the MD5 taken from the source. The partial is read back and compared, moved with `moveItem` (which never replaces a file), and the final file is read back. Dart then checks the size and MD5 against its own local file. Pruning needs the protected backup to appear exactly once in the listing, with the same size, `isUploaded`, no upload or quota error and a creation date. If anything is in doubt, nothing is deleted. Deletes stop at the first error other than `NOT_FOUND`. The protected backup and every file dated at or after it are always kept.
- **No foreign names.** Strict `\A…\z` patterns on both sides. Native refuses any other name for upload, download and delete (`INVALID_ARGUMENT`). The listing returns only our names, filtered to `Documents/Backups`.
- **Only ciphertext leaves.** The source is the staged file, written by `_snapshot.write` and checked with `verifyFile`. The download copy is ciphertext and is deleted in `finally`.
- **Per-flavour containers.** Entitlements and `ZaghlolICloudContainer` are both `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`, which gives `app.zaghlol`, `.dev` and `.staging`. An unexpanded or missing value makes iCloud unavailable (fails closed).
- Errors are code-only. Nothing logs, and the iCloud Swift files are added to the CI no-logging check.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 151-1 | minor | `icloud_backup_service.dart` (`backupNow`, quota check) | If any one of our files carries a quota error, every later backup is blocked, including the case where only an old, already-superseded file is stuck. | Follow-up: only block when the newest file, or the file from the last run, has a quota error. |
| 151-2 | minor | design note §5 | Prune order uses the creating phone's clock (accepted residual). The own just-uploaded backup is always kept, so this is acceptable. | — |
| 151-3 | minor | task | The manual device test (steps 1–6) has not been run, and the PO portal setup is pending. | Do both before DONE, as the builder recorded. |

---

## T-152: backup schedules (C2/C3) — APPROVED

What was checked: `schedule.dart` never deletes anything. `keep = backupKeepFor(state)` comes from `GoldGate.backupVersionsKept` and is clamped to at least 1. Pruning stays in the destination's verify-then-prune code. A destination answer of `confirmed:false` (iCloud not uploaded yet) is not counted as a success. The schedule is Gold-only and is forced off on Free. `cancelAll()` is there for EC-29. The settings keys are in the encrypted settings store. Both ACs have tests ("Free twice → one file", "Gold keeps 5").

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 152-1 | minor (data-safety, before the job binding lands) | `schedule.dart:333`, `:252-256` | `keep` and the Gold check read `entitlementStateProvider` synchronously. It starts as `EntitlementState.free` until `SyncLifecycle` evaluates. So a manual "Back up now" before that evaluation prunes a Gold user's 5 versions down to 1. Worse, a headless scheduled run (the future WorkManager/BGTask engine never evaluates) would see Free and **cancel its own job**. The only good backup is never lost, so this is not blocking. | Before the native job task: `await EntitlementService.evaluate()` (or a "loaded" flag) before deciding `keep` and the Gold check. If the tier is unknown, don't prune below the current count and don't cancel the job. Add a test. |
| 152-2 | minor | `schedule_providers.dart:41` | `icloudBackupDestinationProvider` is still `null`, although T-151's `ICloudBackupService` is on this branch. Choosing iCloud fails with `BACKUP_DESTINATION_UNAVAILABLE`. | Follow-up: an `ICloudBackupDestination` that maps `uploaded` to `confirmed`. |
| 152-3 | minor | `schedule_providers.dart:35` | `backupAppVersionProvider` writes `'0.0.0'` into backup headers. | Bind it to the real app version (package_info) with T-153. |
| 152-4 | minor | `schedule.dart` `isScheduleDue` | If `lastSuccess` lies in the future (the clock was moved back), a run is never due again until that date. | Treat a future `lastSuccess` as due. |
| 152-5 | info | task | The WorkManager/BGProcessingTask binding, the alert sink and the reminder l10n keys are inert seams. The builder declared this. | Lead: track these as follow-ups. |

---

## FU-121: Guard financial filter for user-added phone-number senders (C3) — APPROVED

What was checked:
- **Dart and Kotlin agree.** Both have the same regex `^\+?[0-9][0-9 ()-]{5,}$` (Dart `hasMatch`, Kotlin `matches`, both anchored). Both apply the same `bodyHints` test over the same `folded` text, in the same branch and order, and both return `Drop(not_financial)`. The shared `golden.json` gains 3 cases, and the Kotlin `GuardGoldenJvmTest` reads the same file.
- **Personal messages leave nothing.** Kotlin `CaptureIntakeTest.personalSmsFromAUserAddedSenderLeavesTheWholeRootByteIdentical` checks for no file, no status and no enqueue.
- **Registry senders are unaffected.** That branch comes first and is unchanged (tested in Dart and Kotlin). Alphanumeric user senders and notification packages keep their behaviour (tested).
- The Dart parsing guard tests pass (447). I did not run the Kotlin tests here (they need the PC runner).

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 121-1 | minor | `packages/zaghlol_parsing/lib/guard/capture_guard.dart:13-24` | `_phoneNumberShape` sits between `CaptureGuard`'s doc comment and the class, so the class doc ("The Capture Guard … decides whether a message may be written anywhere") now documents the regex. | Move the regex above the class doc comment. |
| 121-2 | info | design note | "Bank keywords without a currency" are not covered. A user-added phone sender's "Paid 10.00" (no currency) is dropped. The PO has to confirm this. Builder's note. | Lead: PO ask. |

---

## T-009: iOS App Intent → headless engine spike (SPK-03) — APPROVED

What was checked:
- **Production exclusion (native).** `Runner/Spike/IosIntentSpike.swift`, including the `AppIntent`, and `IosIntentSpikeTests.swift` are wrapped in `#if !ZAGHLOL_PROD`. `ZAGHLOL_PROD` is set on all three Runner prod configurations (Debug-prod, Release-prod, Profile-prod) and on the RunnerTests prod configurations. So the intent, and its App Shortcuts metadata, are not in a prod binary.
- **No raw text in logs.** The intent dialog shows only a duration. The Swift metrics are numbers only. The Dart handler returns only the length and the number of digit runs. Test `print`s carry `SPIKE_METRICS` JSON of numbers only, from synthetic text.
- **app-ci.yml.** The new `ios-intent-spike` job and the test list are additions only. No existing gate was changed or weakened.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 009-1 | minor | `app/lib/main.dart:64-69`, `app/lib/ingestion/ios_intent_spike.dart` | The **Dart** side is not excluded from prod. `spikeIntentMain` and `spikeIntentSilentMain` are `@pragma('vm:entry-point')` and ship in every AOT snapshot, Android prod included. They are inert without the (prod-excluded) native caller, and they neither log nor store anything, so this is not a leak. But the "excluded from prod" claim holds only for native. | Follow-up when T-061..T-067 land: delete the spike entrypoints and file (planned per its header), or gate the handler body on a `--dart-define` flavor check. |
| 009-2 | nit | `app/ios/Runner.xcodeproj/project.pbxproj:743/753` | RunnerTests Debug-prod now has `SWIFT_ACTIVE_COMPILATION_CONDITIONS` twice (`DEBUG`, then `$(inherited) ZAGHLOL_PROD`). The later one wins. | Merge into one line: `"$(inherited) DEBUG ZAGHLOL_PROD"`. |
| 009-3 | info | `IosIntentSpike.swift:216-220` | The intent title and dialog are hard-coded English. This is acceptable only because the spike is excluded from prod. | — |

---

## Fix list (blocking only)

| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| T-145 | `app/lib/features/gold/application/gold_store.dart:149-153`, `:112-124`; `app/lib/features/gold/application/purchase.dart:283-288` | `complete()` must report "not completed" when it has no live handle (bool or throw), and the service must then keep the entry at `verified`. On Android, `start()` must `queryPastPurchases()` and emit the Gold purchases that aren't acknowledged yet as `purchased`, so a verified or queued entry is acknowledged without a second verify (same key, iOS seat proof not re-signed). Acknowledged purchases must not be emitted. | `purchase_test.dart`: "restart: entry verified with no live handle stays `verified`, is completed when the store redelivers it, with one verify and one Idempotency-Key". The fake store's `complete()` must fail for purchases it never delivered. Also an adapter-level test (fake `InAppPurchase` platform addition) that `start()` emits only unacknowledged past purchases. |

## Delta re-review (fix round)

Commits 734e6ccf (T-110) and e506fa83 (T-145). `flutter test test/features/ask test/features/gold`: 250 passed.

### T-110 Ask balance: APPROVED
- Debit/credit sum closed: named accounts are keyed per account id and currency, never added; unnamed balance sums asset accounts only. Liability flag and label carried per figure.
- Unmatched name closed: a loose name bind for "balance of CIB", plus an `unknownTarget` unrecognized result when a leftover token matches no account, so no all-accounts fallback. Fixture and engine tests cover both.
- No new cross-currency summing, no text logging.
- FU (minor): the unknownTarget guard may reject balance questions with filler words not in the stop list; watch the utterance corpus.

### T-145 Android acknowledgement after restart: APPROVED
- `complete()` returns false without a live handle, so the entry stays `verified` and is not removed. `start()` lists past Play purchases and re-emits unacknowledged Gold ones with a live handle; the outbox then completes it and removes it. Verified entries are not re-verified (one verify, one Idempotency-Key, tested).
- Acknowledged purchases are skipped, so no double acknowledge; the handle is dropped after completion.
- Listener subscribes before `start()`, so the redelivery is not missed.
- FU (minor): a `verified` entry whose purchase is no longer on Play (refunded) stays in the outbox forever; add an age-out.

## Lead delta check (fix round 18c)

Commit `d6439f89` (about 24 production lines, tests fail without the fix):
- **T-080:** `parseAmount` strips commas only for valid thousands grouping (`^[0-9]{1,3}(,[0-9]{3})+(\.[0-9]*)?$`) after digit normalization; `12,5` now fails with `amountRequired`. The amount field also filters to digits and separators. Correct.
- **T-152:** `backupKeepFor` returns the Gold keep count (5) while the entitlement is `pendingVerification`; `reconcile()` and `runScheduled()` do nothing in that phase, so neither prunes nor cancels. Correct.
- **T-104:** test-only change; `enableAppLock` enabled, not secure and failed paths are covered.
- **Settings:** `setupInstalledOn` row added to the allKeys table.

Verdict: APPROVED. T-110 and T-145 were checked by the delta re-review above.

The parsing timing test "1,000 adversarial 4,000-char decisions take under 2 s" fails only under a fully parallel local run; on its own it passed 3 times out of 3. Follow-up FU-183: tag it `benchmark` if CI hits it.
