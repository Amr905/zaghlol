# Batch 19a review (batch/2026-11-14-19)

Reviewer: `code-reviewer` (Opus; code and security in one pass, PO cost rule 4). Date: 2026-11-14.
Scope: T-061, T-062, T-147 (all C4). Each task diff: `git diff origin/batch/2026-11-14-18...origin/task/<branch>`, plus the merge fix `bca01792`.

Tests run on the merged tree:
- `flutter test --exclude-tags benchmark,golden test/features/account test/features/gold test/ingestion`: 289 pass, 0 fail.
- Swift was read and not built. The builders report green `swift unit tests (xcodebuild)` jobs on `ci/T-061` and `ci/T-062`. Those runs were on the task branches, not on the merged project file (see the pbxproj note).

**pbxproj (merge `bca01792`):** the merged `project.pbxproj` has balanced braces and parentheses (256/256, 127/127). It has one `Guard` PBXGroup (`5A61…1C01`, ten files, closed with `path = Guard; sourceTree = "<group>"; };`) and one `Capture` PBXGroup (`5A62…0200`, four files). Both are listed as children of their parent groups (lines 331 and 358). All 32 T-061/T-062 build files are in a Sources phase. No Swift type name is declared twice across `Runner/` and `Shared/`. Only the batch GitHub run can prove that it builds.

---

## T-061: iOS Capture Guard (C4): APPROVED

What was checked:
- **Same decisions as Dart and Kotlin.** `CaptureGuard.decide` follows Dart steps 0 to 5 in order: length caps in UTF-16 units, one fold with lines kept for global drops, resolve, user sender with the FU-121 phone-shape filter, generic, institution and global OTP/promo drops, institution ignore, then card ignore keyed by institution. Keys and folded text are compared as `[UInt16]` and never as Swift `String`, so canonical equivalence cannot change a result. The Apple Pay longest-card match treats a tie as no institution. The shared golden file (240 entries) is read in place by `GuardGoldenTests`. The two mutation runs (`not_financial` turned into a keep, and the phone filter removed) turned the golden and negative-proof tests red.
- **Raw text never logged.** The directory has no `print`/`NSLog`/`os_log`, and a test scans the sources for them. `GuardSnapshot.description` prints only the mode and the state. Error types carry codes and JSON paths only.
- **Config tampering and wrong key.** If the tag fails, the AAD is wrong or the key is missing, the user part is `unreadable`: it is kept on disk and the Guard runs on the base only. A Keychain error counts as transient: it is not cached and is retried on the next message. A read never creates a key, so a read before first unlock cannot leave the file without its key. A write is fully validated before anything is written (tmp + fsync + rename), and the old file and rules stay if any step fails. An invalid base gives mode `invalid`, which drops every message (fails closed).
- **Keychain accessibility.** The item uses the `DbKeyKeychain` attributes: `AfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false`, never overwritten.

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 061-1 | minor (before T-063) | `app/ios/Runner/Guard/GuardUserCipher.swift:51-58` vs `app/ios/Shared/SpoolKeychain.swift:39-40` | After the merge there are **two different Keychain items, both called `spool_key_v1`**. The Guard's item is service `app.zaghlol.keys`, in the app's **own** access group. T-062's spool key is service `app.zaghlol.spool`, in the **shared** group. platform-channels.md 1.3 describes one spool key. When T-063 runs the Guard in an extension, the extension cannot read the Guard's item. It will then see the user part as `unreadable` and run on the base only, so senders the user added are dropped there. That is silent capture loss. It does no harm today because nothing calls `GuardRuntime` yet. | Before T-063 wires the Guard: point `KeychainSpoolKeyProvider` at `SpoolKeychain` (same service, account and shared group). Keep the rule that a read never creates a key, for example with a `SpoolKeychain.existing()` read that never creates. Add a test that the Guard and the spool resolve the same item query. |
| 061-2 | nit | `app/ios/Runner/Guard/GuardBaseSource.swift` | `ZaghlolDirectories.appGroupIdentifier` now has a value (T-062), but `GuardBaseSource.mirror` is still never called. | T-063: call it at launch. |

---

## T-062: iOS encrypted spool, host API, BG refresh (C4): APPROVED

What was checked:
- **Encryption at rest and AAD binding.** Each entry is AES-256-GCM `nonce12‖ct‖tag16`, with AAD `zaghlol.spool.v1|entry|<ulid>`. A renamed or swapped entry fails the tag (negative proof `testRenamedEntryIsNotAuthenticAndIsDeletedOnProof`). The status file uses AAD `zaghlol.capture.v1|status`. Plaintext buffers are zeroed with `memset_s`. Files are created `0600` with `O_EXCL`, use `F_FULLFSYNC`, and have protection `completeUntilFirstUserAuthentication`, which matches the key's availability.
- **No delete on a cipher or Keychain failure.** `KeychainSpoolCipher` maps every key-load failure, and every CryptoKit error other than an authentication or size error, to `.unavailable`. `SpoolStore.read` treats `.unavailable` as transient: the entry is kept and the drain stops (`keyRelated`). An entry is deleted only when all four attempts prove it bad, or by the lost-key rule (first-attempt tag failure on an entry whose ULID time is before the key's creation). `SpoolKeychain` creates or replaces a key only when all four reads agree on `notFound` or on a wrong length. `errSecInteractionNotAllowed` and every other status create nothing and delete nothing. When the app and an extension create the key at the same time, `errSecDuplicateItem` sends the loser to read the winner's key. `CaptureStatusStore` never overwrites on a Keychain error.
- **Ack only after an ok cycle.** `ackSpool` and `holdSpool` accept only ids this engine's host drained (`ownIds`, capped at 100). The claim makes the UI and headless engines take turns. The Dart cycle acks only after the DB commit (shared `IngestionRunner`; `ios_spool_port_test` "acks after the commit"). `HeadlessIngestion.attempt` returns true only for `outcome == .ok`. Every timeout or failure leaves the entry. Native sends `close` before `destroyContext()`.
- **Entitlements.** `com.apple.security.application-groups` = `group.$(PRODUCT_BUNDLE_IDENTIFIER)` (one per flavor). `keychain-access-groups` lists the app's own group **first**, so the default group, and with it K_db, K_bk and the seat keys (which pass an explicit group anyway), stays the same. The `.shared` group is second.
- **Info.plist and PrivacyInfo.** `BGTaskSchedulerPermittedIdentifiers = [app.zaghlol.ingest]` and `UIBackgroundModes = [fetch]` are both required for a `BGAppRefreshTask`. `ZaghlolAppGroup` and `ZaghlolSharedKeychainSuffix` are expanded per flavor, and an unexpanded `$(` value is rejected. PrivacyInfo adds `FileTimestamp` / `C617.1` (timestamps of files inside the app or App Group container), which is the right reason for the `.tmp` age sweep.
- **Backup exclusion.** The spool and status directories call `ensureExcluded` before their first write (again if a directory disappears). `applyAll` runs at launch. Nothing is written at the container root. `testAppGroupDirectoriesAreExcluded` is on the must-pass list.
- **Contract change in platform-channels.md: approved.** `holdSpool`, `getSpoolStatus` and `clearSpoolAlerts` copy the Android semantics, and the Dart drain (`IosPigeonSpoolPort`, same `_guard` error mapping) is shared. The iOS column of the table is updated for held entries, the drain budget, the claim and the status file.
- Nothing logs. Errors are code-only (`IO_ERROR`, `NOT_AVAILABLE`, `message: nil`).

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 062-1 | minor (data, low likelihood; before extensions write) | `app/ios/Shared/SpoolCipher.swift:30-45`, `app/ios/Shared/SpoolStore.swift:381-413` | `KeychainSpoolCipher` keeps the key for the life of the process, and the read ladder reuses that cached key on every attempt. If **another process** replaces the Keychain item (the unusable → recreate path, or "Delete everything" while an extension is running), entries written under the new key fail all four attempts in this process. They are then deleted as "proven not authentic". This is a real multi-process gap that Android, with one process, does not have. It is rare, because a replacement needs every read to agree on `notFound` or a wrong length. | Before `deleteOnProof` (and before the lost-key shortcut), drop the cached key and re-read the Keychain once. Delete only if the entry still fails under the key that is current then. Add a test: two ciphers over one fake Keychain, where one replaces the key, and the other's entry is not deleted. |
| 062-2 | minor | `app/ios/Shared/SpoolStore.swift:335` | Nothing calls `releaseHeldIfVersionChanged`, so held entries are never put back after an app update (on Android this happens at process start). Nothing is lost, because held entries stay on disk. | Call it once per process with `CFBundleVersion`, for example in `SpoolRuntime.make` or at launch. |
| 062-3 | minor | `app/pigeons/capture_api.dart` `registerBackgroundRefresh`; no Dart caller | Dart never calls `registerBackgroundRefresh`, and the handler only reschedules after it has run once. So the `app.zaghlol.ingest` chain never starts. The foreground drain is still the guarantee. | The capture bootstrap (T-063/T-065) calls it on iOS when the app starts. |
| 062-4 | nit | `docs/03-technical/platform-channels.md` §1.3 "Write" row | The iOS column still says `Data.write(options: .atomic)`. The code uses `.tmp` + `F_FULLFSYNC` + `rename`, and a 10-minute `.tmp` age sweep, because several processes write. | Update the row. |
| 062-5 | nit | `app/ios/Runner/Platform/Capture/HeadlessIngestion.swift:85` | The headless engine registers every generated plugin, including the sign-in and IAP plugins. It needs fewer. | Optional: register only what `ingestionMain` uses. |

PO setup (not code): the App Group `group.<bundle id>` and the keychain group must be registered for each flavor's App ID in the developer portal. The manual device steps listed in the task file are still open.

---

## T-147: Optional sign-in, S-69, sign-out, delete account (C4): APPROVED

What was checked:
- **No financial data sent.** `SignInRequest` holds only the provider, ID token, raw nonce, the Apple authorization code (used only for revocation), `replaceLink` and the iOS seat proofs. `toJson()` validates before anything is sent. `toString` on every credential and outcome type hides its values. Nothing logs.
- **A new nonce for each attempt.** `newRawNonce(Random.secure())` gives 24 bytes (192 bits), base64url, held only in memory. The provider gets `hex(SHA-256(raw))`. A new nonce is made on every loop pass, including the `SEAT_KEY_MISMATCH` retry and the `replaceLink` repeat. Google calls `initialize(nonce:)` once per attempt, and attempts run one at a time. The device check is still open in T-172.
- **Apple state guard.** 24 CSPRNG bytes. The state is single use: it is dropped on every `consume`, including a wrong guess. It lasts at most 10 minutes. The comparison runs in constant time. Missing, reused, unknown or expired states are rejected. A Custom Tab that never returns times out at the state's lifetime and counts as a cancel.
- **Tokens dropped on sign-out.** `EntitlementService.signOut` deletes the entitlement and account tokens **before** the call, so an offline sign-out still signs out. Delete account clears the account token only after the 204.
- **Token bound to this install.** The response goes through `EntitlementService.anchored` (the T-144 binding check). The service then checks again that the stored account token has `iid == installId` and `sub == accountId`. Otherwise the result is `SignInFailed`, never a success.
- **The "paused" marker cannot grant Gold.** `signedOutPausedStateKey` is written only when the token that was dropped had `acct`, and it holds this install's ID. `evaluate` reads it only when **no** claims are cached, and it can only produce `EntitlementPhase.paused`. `isGold` is true only for `active`/`grace` (`gating.dart:84-85`), so `paused` fails closed like `free`. The marker is deleted only when a backend-signed, verified, install-bound token is stored (`entitlement.dart:633`, inside `handleBody`). A marker copied from another install does not match `installId`. The only extra effect is that `refreshIfDue` fetches while the marker is set, which is the intended behaviour.
- R5-6 (no `seatKeys` after a mismatch that a retry confirmed), Android never sending `seatKeys`, R5-3(b) (Restore only with a StoreKit transaction, otherwise the support path) and D-54 (only `PurchaseGold` on this install) all match the ACs. The tests pass.

### Findings

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 147-1 | minor | `app/lib/features/account/presentation/account_launcher.dart`; root scope | S-69 cannot be reached yet. `goldSignInOpenerOverride(navigatorKey)` is not added to the root overrides, and Settings has no entry for it. The builder listed this. | FU: wire both (T-172 or the Settings owner). |
| 147-2 | minor | `app/lib/features/account/application/id_token_source.dart:128-150` vs `app/lib/features/backup/data/drive_auth.dart:51-63` | The Drive authorizer calls `GoogleSignIn.instance.initialize` (without a nonce) through the same singleton, outside the sign-in queue. If that call lands between the sign-in's `initialize(nonce:)` and `authenticate()`, the ID token carries no nonce and the backend rejects it. This fails closed and is not a security issue. | FU: share one Google init queue between the two, or have the Drive path skip `initialize` once sign-in has run. Record it with the T-172 device check. |
| 147-3 | minor | `app/lib/features/account/application/account_service.dart:184-193` (`signOut`) | Sign-out never calls `GoogleSignIn.signOut()`, so the next sign-in may pick the same Google account again without asking. | FU: call the provider sign-out as best effort, ignoring errors. |
| 147-4 | nit | `app/lib/features/account/application/account_providers.dart:95-101` | `AccountStatus.linkedGold` reads `claims?.acct` without checking `claims.sub == installId`. This affects only the sign-out dialog wording. | Optional. |
| 147-5 | nit | `app/lib/features/catalog_sync/presentation/sync_lifecycle.dart:6` | The relative import comes before `dart:async`, which is out of directive order. | Move it. |

---

## Fix list (blocking findings only)

None. No blocker, and no major touching money, security, privacy or data loss, in T-061, T-062 or T-147. Findings 061-1 and 062-1 should be fixed before T-063 starts writing from extensions or App Intents. The Lead should file them as follow-ups owned by T-063.
