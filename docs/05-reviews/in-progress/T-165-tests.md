## Test verification (T-165, test-engineer)

Scope: branch `origin/t165` at 13ef486, green run 42316116828, proof run 42316160887 (`origin/proof` at ec43def). I read the code and the CI logs. I did not re-run CI locally. I wrote no files.

### Criterion and control map

| # | Criterion or design-note control | Check | Evidence |
|---|---|---|---|
| 1 | AC1: adb backup and device transfer yield no app data. Manifest has `allowBackup=false` and `hasFragileUserData=false`, with both rule-file references. | `check-no-os-backup.sh` runs aapt2 on the final APK in each `android` matrix job. | Green run: `OK: ... excludes all app data` for all 6 APKs: devnosms-debug, devsms-debug, stagingnosms-debug, stagingsms-debug, prodnosms-release, prodsms-release. Logs show `allowBackup(0x01010280)=false` and `hasFragileUserData(0x0101059a)=false`. `xml/backup_rules -> res/xml/backup_rules.xml` and `xml/data_extraction_rules -> res/xml/data_extraction_rules.xml` resolve via the resource table, not by file name. |
| 2 | `data_extraction_rules` has `cloud-backup` and `device-transfer`, each with exactly 9 domains, `path="."`, and no `include`. `backup_rules` has the same 9 excludes. | `check_rules_xmltree`, called from `check_apk`. | Same 6 OK lines. Proof run, devnosms job: `<device-transfer> excludes are [... no device_sharedpref], expected exactly [...]` and `<full-backup-content> excludes are [bogus ...]`, then `fails the T-165 no-OS-backup assertions`. |
| 3 | Negative control for the checker. | 22-case self-test (`test-check-no-os-backup.sh`), run in the `format, analyze, unit tests` job. | Log: `22 cases, 0 failed`. It has 3 positive cases, plus a 2-space-indent compatibility case that also passes. The failing fixtures include `allowBackup=true`, `hasFragileUserData=true`, `dataExtractionRules` missing, `fullBackupContent` missing, `allowBackup` missing, `allowBackup` declared twice, `<include>` present, `device-transfer` missing or duplicated, a missing domain in either section, `path` not `.`, an unknown domain, an unknown element, and unparseable attributes (fail closed). |
| 4 | XML source lint: `AllowBackup`, `DataExtractionRules` and `FullBackupContent` raised to errors. | `:app:lintDevNoSmsDebug`, plus a guard step that checks the task ran and that `lint.xml` raises all three. | Green run, kotlin job: `> Task :app:lintDevNoSmsDebug`, `BUILD SUCCESSFUL`. Proof run: `lintDevNoSmsDebug FAILED`. In the release jobs, `lintVitalProdSmsRelease` and `lintVitalProdNoSmsRelease` fail with `Unexpected domain bogus ... [FullBackupContent]`. |
| 5 | iOS: every sandbox root exists and `isExcludedFromBackup == true` after launch. `AppDelegate` runs `applyAll` first. | `BackupExclusionTests` on the simulator (iPhone 17 Pro). A CI loop requires each of the 10 named tests to be `passed`. | Green run: 9 passed and `testAppGroupDirectoriesAreExcluded` skipped. The skip matches the design: there is no App Group entitlement yet, and `testAppGroupDirectoriesAreSkippedWithoutAContainer` passes. |
| 6 | iOS: `ensureExcluded` creates the directory, is idempotent, survives delete and recreate, and a failure does not stop the others. | Tests `CreatesAndExcludes`, `IsIdempotent`, `SurvivesDeleteAndRecreate`, `ExcludeMarksEveryDirectory`, `ExcludeReportsFailureWithoutStoppingOrCrashing`. | Green run: all passed. |
| 7 | AC2: iCloud device backup excludes the DB. | The DB lives under Application Support, and that root is flagged (tests 5 and 8). | CI proves the directory flag only. No DB file is created yet (Drift arrives with T-015). Finder, iCloud and migration behaviour is device-only (manual steps 5a to 5c). The result tables are blank, so none of it has been run. |
| 8 | A file created later stays covered by the directory flag. | `testFilesCreatedLaterStayUnderAnExcludedDirectory`. | Passed in the green run. Failed in the proof run, together with `testAppContainerDirectoriesAreExcludedAtLaunch`, when `applyAll()` was removed from `AppDelegate`. |
| 9 | iOS directory set is complete. | `testAppContainerDirectoriesAreExcludedAtLaunch` asserts `count == 4`. `testDirectorySetCoversTheFlutterDataRoots` asserts the four suffixes. | Passed in the green run. Not shown failing in the proof run (see gap G3). |
| 10 | DoD: analyze, format, no hard-coded strings, no `double` money, no raw SMS. | The `format, analyze, unit tests` job. | The job passed in both runs. The diff has no Dart code, no user-facing strings, no money and no SMS. The Swift log call prints only the constant code `BACKUP_EXCLUSION_FAILED`. |
| 11 | Testing requirement: device verification test. | `docs/05-reviews/T-165-device.md` (script only; results not yet recorded). | See the script review below. |

### Does the negative proof cover each control?

The proof run (ec43def) broke three things: the `external` domain in `backup_rules` became `bogus`, `device_sharedpref` was removed from `device-transfer`, and `applyAll()` was removed from `AppDelegate`. Every proof job except the ios-build jobs, `widget golden tests` and `format, analyze, unit tests` failed. All three defects were caught.
- `bogus` was caught by Android lint and by the aapt2 checker.
- The removed `device_sharedpref` was caught only by the aapt2 checker, which is the only control for that case.
- The removed `applyAll()` was caught by two XCTests.

| Control | Live proof | Would it stay green if it broke? |
|---|---|---|
| Missing domain in a section | Yes (live) | No |
| Wrong domain name | Yes (lint and aapt2) | No |
| `applyAll()` dropped from launch | Yes (live) | No |
| `<include>` element | Self-test only (case 12). | Not for aapt2. Android lint does not flag an `<include>` of an existing path, so the checker is the only control, and it has the fixture proof. The parser treats `include` and `exclude` identically in structure, and the real-format layout is validated by the 6 positive passes. Residual risk is low. |
| `allowBackup=true` | Self-test only. | Android lint's `AllowBackup` check fires only when the attribute is missing, so an explicit `true` passes lint. The aapt2 check is the only control. The real output format (`=false`) is confirmed in the logs, so `=true` is matched by the same pattern. Low risk. |
| `hasFragileUserData` missing or `true` | Self-test only. | Same single-control situation. Covered by the "exactly once" and "is false" fixtures. Low risk. |
| iOS directory set loses one directory | Not demonstrated. | Statically it would not stay green. `count == 4` catches a dropped root, and the suffix test catches a swapped one. A negative run for this was not made (G3). |
| Release-APK aapt2 check | Not demonstrated live. | Release jobs failed earlier, in `lintVital`, before the assert step ran. The release path has only positive evidence (2 OK lines), plus lint-vital coverage. |

### Is the XCTest read-back vacuous?

No.
- `isExcluded` builds a fresh `URL(fileURLWithPath:)` before reading, so it bypasses the URL resource-value cache.
- `testFreshDirectoryIsNotExcludedByDefault` and the `StillFalseAfterRecreate` assertion show that new directories are not excluded by default.
- No test calls `applyAll()` on the real roots, so the launch assertion depends on `AppDelegate`. The proof run confirms `RunnerTests` is hosted by Runner and that removing the call fails the launch test.
- `ensureExcluded` itself reads the flag back and throws if it is not `true`.

### `T-165-device.md` completeness and runnability

The script covers all 5 steps of the design note. Preconditions, a reset of the D2D transport, and tables are present. The commands match the design note.
- It cannot run yet. Preconditions require fixture import and a backup passphrase, which do not exist before the T-015 and later features. The expected result "opens at Welcome" proves nothing on an empty app.
- The results tables are blank, so no device evidence exists.
- Several runnability problems are listed under G1, G2, G6 and G7 below.

### Gaps

| ID | Severity | Gap | Recommendation |
|---|---|---|---|
| G1 | Medium | Steps 1 and 3 reinstall with `adb install-multiple`. That does not reliably trigger a restore from the transport, so "opens at Welcome" could pass without restoring anything. | Add `adb shell bmgr list sets` and `adb shell bmgr restore <token> <pkg>`. Also assert that the `bmgr backupnow` output shows no app payload (for example with `dumpsys backup`). |
| G2 | Medium | The script depends on seed features that are not built, and nothing in it distinguishes "no data copied" from "no data existed". | Add a canary: before backup, plant a marker file with `run-as` under `files/`, `databases/` and `shared_prefs/`, and assert it is absent after the restore. This also makes the script runnable now. |
| G3 | Low | No negative proof shows the iOS directory set failing when a directory is dropped. | Optionally run one more proof that removes `tmp` or `Documents`. |
| G4 | Low | Neither a live nor a local negative proof shows `<include>`, `allowBackup=true` or `hasFragileUserData` failing against real aapt2 output. Fixtures only. | Optional: add a proof commit that sets `allowBackup=true`. The aapt2 output format is already confirmed by the positive logs. |
| G5 | Low | The release aapt2 assert has no live negative run. | Accept. Lint-vital and the positive pass cover it. |
| G6 | Low | Step 2: if the backup is refused, the file body is empty and `zlib.decompress` raises. The script says an empty archive is a pass. The `adb backup` restriction for apps targeting API 31 or higher is not stated. | Catch the empty case in the Python, and state that the step must run on an API 26 to 30 emulator. |
| G7 | Low | Not covered on device: `hasFragileUserData` (uninstall with data kept), the iOS "Delete everything" re-application path, and the orphan-data reset. The orphan path is a T-015/T-016 deliverable. | Track in T-015, T-016 and T-171. |
| G8 | Info | The App Group test is skipped by design until T-062 provides the entitlement. | Track in T-062. |

### Verdict: TESTS_SUFFICIENT

The CI-verifiable controls are covered, and the live proof demonstrates that the main ones fail when broken. Merge-level evidence is adequate. No gap is blocking.

Before the device script is executed on a release candidate, fix G1 and G2. Acceptance criterion 2 (iCloud) has no executed device evidence until the manual run is recorded.