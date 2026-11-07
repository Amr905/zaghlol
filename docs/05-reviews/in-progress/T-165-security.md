## Security & privacy review (security-privacy-reviewer, Opus, 2026-11-07)

**Scope:** `git diff origin/main...origin/t165` (branch `task/T-165-no-os-backup` at `13ef486`, 14 files). I read the T-165 design note, CLAUDE.md §2, security-model.md §7, FR-SEC-05, D-50, D-55, D-62 and EC-67.

**CI evidence, checked with `gh run view`:**
- Run 42316116828 on `13ef486`: all 13 jobs green.
- Negative-proof run 42316160887 on `task/T-165-proof` (`ec43def`) was built from three deliberate breaks: a `bogus` domain in `backup_rules.xml`, `device_sharedpref` removed from `<device-transfer>`, and `applyAll()` removed. It failed in the right places:
  - The aapt2 assertion failed on all 4 debug APKs, naming both rule files.
  - Release lintVital and `:app:lintDevNoSmsDebug` failed on `backup_rules.xml:10`.
  - Two XCTests failed: `testAppContainerDirectoriesAreExcludedAtLaunch` and `testFilesCreatedLaterStayUnderAnExcludedDirectory`.

  This shows that each layer detects a regression on its own.

### Verdict: **CHANGES_REQUESTED**

The design is implemented faithfully and the static guarantees are strong. Two small in-scope gaps (F1, F2) must be fixed before merge. F3 is a release gate, not a merge gate. F4–F8 are follow-ups for other tasks; the Lead should copy them into those task files.

### Coverage matrix (focus 1)

| Path | Status |
|---|---|
| Android Auto Backup and key/value backup (API 26–30) | Covered. `allowBackup="false"` (AndroidManifest.xml:15), with `backup_rules.xml` excluding all 9 domains as defense in depth. |
| `adb backup` (API 26–30) | Covered by `allowBackup=false`. Device step 2 verifies it. For API 31+, see F2. |
| Cloud backup (API 31+) | Covered. `<cloud-backup>` excludes all 9 domains and `allowBackup=false`. |
| D2D (API 31+) | Covered. `<device-transfer>` excludes all 9 domains. The CI check runs on the compiled XML in every final APK, so merging and resource shrinking cannot change the result unnoticed. Custom backup agents are not covered; see F1. |
| OEM tools (Smart Switch, Pixel cable copy) | Residual as D-50 describes. Any copy contains only SQLCipher ciphertext, and the Keystore key cannot be exported. The wipe-to-Welcome step belongs to T-015/T-016. One condition must hold; see F6. `hasFragileUserData=false` closes the "keep data on uninstall" variant. |
| iOS iCloud and encrypted Finder backups | Covered for `Library/Application Support`, `Documents`, `Caches` and `tmp`. Other `Library/*` subdirectories are not covered; see F2/F5. |
| iOS Quick Start direct migration | Not proven by any static check. Only device step 5c tests it; see F3. |
| App Group container | Not present yet. `appGroupIdentifier = nil` (BackupExclusion.swift:25) is safe today; see F5. |
| `UserDefaults` / Keychain | Nothing writes `UserDefaults` today: there are no pub dependencies and no native use. The policy exists only as a comment (BackupExclusion.swift:16-17), so nothing enforces it; see F7. `ThisDeviceOnly` is owned by T-015. D-62 seat keys are Secure Enclave keys and never enter backups, so T-165 does not conflict with them. |
| `UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace` | Absent from Info.plist, so `Documents` is not exposed through Finder or Files. |

### Findings

**F1 — Medium — `.github/scripts/check-no-os-backup.sh:110` (also :8). Owner: T-165 (required).**
`check_manifest_xmltree` asserts only `allowBackup`, `hasFragileUserData`, `fullBackupContent` and `dataExtractionRules`. It does not assert that `android:backupAgent` is absent.
- **Leak path:** the main manifest does not declare `backupAgent`, so if a plugin or library manifest declares one, the manifest merger adds it silently. The merger fails only on conflicts, and here there is none. On API 31+, D2D ignores `allowBackup=false`. `dataExtractionRules` are applied only by the default `FullBackupAgent` file walk, so a custom agent's `onBackup`/`onFullBackup` can stream any file, including `zaghlol.db`, during device transfer.
- **Required:** fail if `android:backupAgent(` appears anywhere in the final manifest. Also fail on `android:fullBackupOnly(…)=true`, which only matters when an agent is present. Add a self-test fixture `backupAgent present → fail` to `test-check-no-os-backup.sh`.

**F2 — Medium — `docs/05-reviews/T-165-device.md:108` (step 5a) and :53-66 (step 2). Owner: T-165 (required).**
- Step 5a uses a deny-list: no `zaghlol.db*`, `spool/` or staging files. A file that a plugin later writes under `Library/` with another name, outside the four excluded roots, would still pass. Examples are `Library/<plugin>/`, `Library/WebKit`, `Library/HTTPStorages` and `Library/Preferences/<bundle>.plist`.
  - **Required:** make 5a an allow-list. Record the full `AppDomain-app.zaghlol*` listing. Only OS-generated entries may be present, plus `Library/Preferences/<bundle-id>.plist`, and that plist must contain no app-written keys. Anything else is a FAIL.
- Step 2 runs `adb backup` only on API 26–30. On Android 12+, `adb backup` still exports app data for **debuggable** apps, and the `dev` build is debuggable.
  - **Required:** add a row for API 31+ with the debuggable dev build. Expect no `apps/app.zaghlol.dev/` entries, because `allowBackup=false` should still refuse.

**F3 — Medium (release gate) — `docs/05-reviews/T-165-device.md` (all result tables are empty). Owner: T-165 / T-171.**
Neither acceptance criterion ("adb backup / device transfer yields no app data", "iCloud device backup excludes DB") can be shown in CI. They rest entirely on the device run.
- Quick Start **direct** (wireless or cable) migration is the weakest assumption. Apple documents `isExcludedFromBackup` for iCloud and Finder backups. It does not clearly document that direct device-to-device migration honours it. If 5c shows the DB arriving, the only defense left is the D-50 wipe.
- **Required:** T-165 may merge, but it must not be marked Done in TASKS.md until `T-165-device.md` is filled in on a release candidate with every row PASS. Record the iOS and Android versions used. T-171 should depend on that result, not only on the merge.

**F4 — Medium — `app/ios/Shared/BackupExclusion.swift:54-62` (roots), `app/ios/Runner/AppDelegate.swift:13`. Owner: T-166 (add to task file).**
The exclusion lives on the root directory. If "Delete everything" (or a restore swap in T-149/T-150) deletes or renames `Application Support` or `Documents` **itself**, the flag is lost. `path_provider` then recreates the directory without the flag, and the new DB written during the same process lifetime goes into the next iCloud backup until a cold relaunch. The test at BackupExclusionTests.swift `testEnsureExcludedSurvivesDeleteAndRecreate` demonstrates exactly this flag loss. The leaked data is ciphertext under a `ThisDeviceOnly` key, but it still breaks FR-SEC-05.
- T-166 does not mention T-165 or `applyAll` today.
- **Required in T-166:**
  - Delete the *contents* of the roots, never the roots themselves.
  - Call `ZaghlolDirectories.applyAll()` natively after the wipe and before the first-launch DB is created.
  - Add an XCTest that the roots are still excluded after the wipe.
- Restore tasks must swap files *inside* the root, never replace the root.

**F5 — Low — `app/ios/Shared/BackupExclusion.swift:25`, `.github/workflows/app-ci.yml:240`, `app/ios/RunnerTests/BackupExclusionTests.swift:128`. Owner: T-062 (and T-065 for the Share Extension).**
- The CI must-pass list does not include `testAppGroupDirectoriesAreExcluded`. Once T-062 sets the group ID, a simulator build without the entitlement would still `XCTSkip` silently.
- The App Group container has its own `Library/Preferences`, and nothing excludes files written at the container root outside the 3 listed directories.
- Extensions never run `AppDelegate`. A user can share into Zaghlol before ever opening the app, so the Share Extension's first spool write happens before `applyAll()` has ever run.
- T-062 does not reference T-165 today.
- **Required in T-062/T-065:**
  - Set `appGroupIdentifier`.
  - Add the test to the CI list as must-pass, not skipped.
  - Every extension calls `ensureExcluded` on its target directory before its first write.
  - Write nothing at the container root.

**F6 — Low — D-50 / orphan detection (no T-165 line; cross-task). Owner: T-015/T-016.**
D-50 is safe only if orphan detection keys on *the Keystore/Keychain key being unusable*, not on the presence of a wrapped-key blob. On Android, a Keystore-wrapped `K_db` blob stored in a file or sharedpref travels with the DB in an OEM copy, while the wrapping key does not. Detection must therefore treat "alias missing **or** unwrap fails **or** SQLCipher open fails with a key error" as orphaned. It must then wipe the DB, the spool, temp files and wrapped blobs, but on iOS never the D-62 seat keys.

T-165 itself does not conflict with D-50:
- `hasFragileUserData=false` supports D-50.
- `ensureExcluded` only creates empty directories, so it cannot trigger a false orphan state.
- `applyAll()` runs before any DB open.

**F7 — Low — `app/ios/Shared/BackupExclusion.swift:16-17`. Owner: T-171 (privacy suite) or the custom_lint slot.**
The rule "no app data in `UserDefaults`" is a comment only. **Recommended:** a CI guard that fails on any of the following in `app/lib`, `app/ios` or `app/pubspec.yaml`, with an allow-list for reviewed exceptions:
- `UserDefaults`, `NSUbiquitousKeyValueStore`
- `shared_preferences`
- `getLibraryDirectory`
- `getExternalStorageDirectory` / `getExternalFilesDir` on Android (USB/MTP exposure)

**F8 — Low — `.github/workflows/app-ci.yml:334-337`. Owner: T-176 (Android release pipeline).**
The assertion runs on `flutter build apk` output. Play ships the **AAB**, which is a different artifact. **Recommended:** run the same check on the release AAB, for example via `bundletool build-apks --mode=universal` followed by `check-no-os-backup.sh`, or via `bundletool dump manifest` plus the resources.

### Logging (focus 3) — no findings
- `BackupExclusion.swift:108` logs the constant `BACKUP_EXCLUSION_FAILED` with `privacy: .public` and no interpolated path or error.
- `ensureExcluded` errors are caught and dropped (`exclude`, lines ~98-105).
- XCTest messages use `lastPathComponent` of fixed sandbox names, in CI only.
- The CI script prints the compiled rule XML and the four manifest attribute lines. Neither contains user data.

### CI robustness (focus 4) — acceptable, notes only
- The aapt2 check fails closed:
  - It uses `set -euo pipefail`.
  - A missing APK makes aapt2 fail.
  - It requires exactly-once attributes, the exact sorted domain set, `path="."`, no `<include>`, and no unknown elements.
  - Resource IDs are resolved to `xml/backup_rules` and `xml/data_extraction_rules`.
  - It handles any aapt2 indentation width.
  - 22 negative-control cases run in `static`.
- XCTest names are matched individually against "passed", and none is a prefix of another.
- The lint suppression (`lint.xml:15`) is narrow: one unrelated issue ID (`PermissionImpliesUnsupportedChromeOsHardware`), scoped to `src/noSms/AndroidManifest.xml`. It does not touch the backup checks.
- Residual (Info): the `app-ci.yml:175` grep would still pass if a later `<issue id="AllowBackup" severity="ignore"/>` or a lint `baseline` were added. The APK assertion is the real guarantee, so this is acceptable. CODEOWNERS on `.github/scripts/`, `.github/workflows/`, `app/android/app/lint.xml` and `app/android/app/src/main/res/xml/` would protect all of the gates; that sits with the Lead.

### iOS exclusion durability (focus 2) — sound with F4
- Excluding directories rather than files is the correct choice (QA1719). SQLite `-wal`/`-shm` files, atomic `.atomic` writes and in-directory renames do not affect the flag on the parent.
- On first launch, `applyAll()` runs before `super` (AppDelegate.swift:13), so before the implicit engine and plugin registration. Files created before that point do not exist.
- The flag covers existing contents retroactively, so builds from before T-165 are also covered after one launch.
- The only way to lose the exclusion is deleting or replacing a root (F4) or writing outside the roots (F2/F5).

**Required before re-review:** F1 and F2 on this branch. Merge may follow; Done in TASKS.md waits for F3. F4–F8 should be added to T-166, T-062/T-065, T-015/T-016, T-171 and T-176.