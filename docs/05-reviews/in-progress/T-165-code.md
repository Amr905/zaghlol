# Review: T-165 Exclude app data from OS backups and device transfer (code review)

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer (Opus) |
| Date | 2026-11-07 |
| Commit / diff | `task/T-165-no-os-backup` @ `13ef486` (`git diff origin/main...origin/t165`, 14 files, +857/-6) |
| CI | Green: run 42316116828 (13/13). Negative proof: run 42316160887 on `task/T-165-proof` @ `ec43def`, red in 7 jobs as intended (see Notes) |
| Verdict | **APPROVED** (no blocker or major findings). The on-device script has not been run yet, so AC1/AC2 are proven only by static/CI evidence (F1). |

## Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| adb backup / device transfer yields no app data | **PASS (static)**; device run PENDING | Main manifest sets `allowBackup=false`, `fullBackupContent=@xml/backup_rules`, `dataExtractionRules=@xml/data_extraction_rules` and `hasFragileUserData=false`. Both rule files exclude all 9 domains with `path="."`, in `cloud-backup`, in `device-transfer` and in `full-backup-content`. None has an `<include>`. aapt2 checked the final APK in all 6 variants, including both release APKs. The release APK's obfuscated paths (`res/Qq.xml`, `res/4j.xml`) were resolved through `dump resources`. In the proof run, a missing `device_sharedpref` and a `bogus` domain were both caught. The device tables in `T-165-device.md` §1–4 are blank. |
| iCloud device backup excludes DB | **PASS (static)**; device run PENDING | `applyAll()` is the first statement in `didFinishLaunching` and runs before `super`. The flag goes on Application Support, Documents, Caches and tmp. In the green run, `testAppContainerDirectoriesAreExcludedAtLaunch` passed without calling `applyAll` itself. In the proof run, removing `applyAll()` made that test and `testFilesCreatedLater…` fail. `T-165-device.md` §5 is blank. |
| DoD (CLAUDE.md §7) | PASS | No Dart, strings, money or SMS in the diff. Static job green. The only log call emits the constant code at `privacy: .public` with no path or error text. |
| Design note: CI negative control | PASS | 22-case self-test runs in the `static` job (`22 cases, 0 failed`). |
| Design note: lint raised to error | PASS | `lint.xml` sets the three IDs to `fatal`. `:app:lintDevNoSmsDebug` runs, and a guard step checks the task executed and the severities are set. In the proof run, `lintVital*Release` was also blocked. |
| Design note: iOS XCTests 1–4 | PASS | The CI loop requires 10 named tests to pass. The App Group test is an `XCTSkip` until T-062. |

### Design-note items traced
- **Android API 26–30 vs 31+.** Handled correctly. `allowBackup=false` covers Auto Backup, key/value backup and `adb backup`. `<device-transfer>` covers D2D on API 31+. `fullBackupContent` is kept as defense in depth. All attributes are in `src/main`, so every flavor and build type inherits them. No pre-emptive `tools:replace` was added, which follows the note.
- **`hasFragileUserData`.** Set explicitly to `false` and asserted on the final APK.
- **Merged manifest.** The checker reads the compiled manifest in each built APK, not the source. Each attribute must appear exactly once.
- **iOS ordering.** `applyAll()` runs before `super`, and therefore before the implicit engine and plugin registration. It runs on every launch and is idempotent.
- **iOS directory set.** It matches the note's table: 4 container roots and 3 App Group directories. The App Group directories are skipped while `containerURL` is nil, and the code returns `[]` for both a nil ID and an unknown ID.
- **iOS read-back.** It is real. A fresh `URL(fileURLWithPath:)` avoids the URL's resource cache. `testFreshDirectoryIsNotExcludedByDefault` and `testEnsureExcludedSurvivesDeleteAndRecreate` (which asserts `false` after a plain recreate) show the read can return false, so the positive assertions are not vacuous.
- **iOS failure handling.** No throw, no crash, and the remaining directories still get processed (tested). The log is code-only. Moving it to the native diag hook is deferred to T-021 (F5).
- **"Delete everything" re-apply and App Group activation.** Deferred to later tasks as the note says, but the follow-ups are not recorded in those tasks (F3, F4).

### Declared deviations
1. **Helper in `app/ios/Shared/`.** Matches the note. Accepted.
2. **Extended `swift-unit` with `--config-only`.** Accepted. The note asked for a new job built with `flutter build ios --simulator --debug`. The existing job already runs `xcodebuild test -scheme dev -configuration Debug-dev` with Runner as test host, and the proof run shows it detects a missing `applyAll()`. `--config-only` was already used in that job before this task. The destination is the first available iPhone rather than the "latest" one, which is also unchanged from before.
3. **`fatal` severity, plus the `PermissionImpliesUnsupportedChromeOsHardware` suppression.** Accepted. `fatal` is at least `error` and also blocks `lintVital` on release, as the proof shows. The suppression covers one issue ID in one file (`src/noSms/AndroidManifest.xml`), whose only `uses-permission` entries are `tools:node="remove"`. That is a plausible false positive, and the check still runs everywhere else. It also hides nothing today, because lint never runs on the Sms variant (F6).
4. **Checker in `.github/scripts/` with a 22-case self-test.** Accepted. Keeping the logic in a script makes it testable, which inline YAML would not be. One gap in the self-test is F2.
5. **Extra `ZaghlolDirectories.exclude(_:)`.** Accepted. It is internal, `applyAll()` is a thin wrapper over it, and it is what lets the "one failure does not stop the others" behaviour be tested without touching the real roots.

## Findings
| # | Severity | File:line | Issue | Required change | Owner |
|---|----------|-----------|-------|-----------------|-------|
| 1 | minor | `docs/05-reviews/T-165-device.md:48-122` | The task's testing requirement is a device verification. All result tables are blank, so AC1/AC2 are demonstrated only statically. The note schedules the script for a release candidate, and no RC exists yet. | Lead: mark T-165 done with an explicit open item to run and record `T-165-device.md` on the first RC, and add it to the T-171 / release checklist. Do not cite AC1/AC2 as device-proven until then. | Lead → T-171 |
| 2 | minor | `.github/scripts/test-check-no-os-backup.sh:77-131` (covers `check-no-os-backup.sh:134-171`) | The self-test only exercises `check_manifest_xmltree` and `check_rules_xmltree`. Nothing tests `resolve_resource` or `check_apk`: a `fullBackupContent` ID resolving to the wrong resource name, an ID missing from `dump resources`, the `(file)` path parse with an obfuscated `res/Qq.xml`, or aapt2 failing or producing empty output. By reading the code these all fail closed today, because empty output yields no ROOT or a name mismatch. But no fixture pins that behaviour, and the release-path check was not reached in the proof run (lintVital stopped it first). | Add fixtures for `dump resources`: a correct obfuscated path passes; a swapped name, a missing ID, and no `(file)` line each fail. Add one `check_apk` case with a stub aapt2 that exits non-zero with empty output, expecting failure. | T-165 follow-up (any later CI-touching task) |
| 3 | minor | `app/ios/Shared/BackupExclusion.swift:25`; `.github/workflows/app-ci.yml:235-240` | T-062 has to set `appGroupIdentifier`, enable `testAppGroupDirectoriesAreExcluded` and add that test to the CI must-pass loop. T-062 and T-063 also have to add `Shared/BackupExclusion.swift` to the extension and widget targets and route every native directory creation through `ensureExcluded`. None of this is recorded in `T-062.md` or `T-063.md`. If it is missed, the CI loop stays green while the spool goes unprotected. | Lead: add a "Review follow-ups" entry to T-062 and T-063 covering all four items. | Lead → T-062, T-063 |
| 4 | minor | `docs/04-tasks/tasks/T-166.md` (no line; the item is missing) | The note requires "Delete everything" to call `applyAll()` natively after recreating the directories. On iOS the in-process "restart into first-launch state" does not re-run `didFinishLaunching`. T-166 does not mention this. | Lead: add a T-166 follow-up: after the wipe, call `ZaghlolDirectories.applyAll()` natively before Dart reopens storage, and test it. | Lead → T-166 |
| 5 | minor | `app/ios/Shared/BackupExclusion.swift:108` | `BACKUP_EXCLUSION_FAILED` appears in no diag-code registry and is not mentioned in T-021. Until T-021 picks it up, the failure exists only in `os_log` and is invisible to the app's diagnostic export. | Lead: add the code to T-021's allow-listed code set, with a note to swap the `os_log` call for the native diag hook. | Lead → T-021 |
| 6 | minor (out of scope) | `app/android/app/src/sms/AndroidManifest.xml:3-4`; `.github/workflows/app-ci.yml` lint step | Lint runs only on `devNoSmsDebug`, so no lint check covers the Sms flavor. That flavor declares `READ_SMS`/`RECEIVE_SMS` without `<uses-feature android:name="android.hardware.telephony" android:required="false"/>`, so Play will likely filter out non-telephony devices. This is the real positive that the noSms suppression was correctly scoped to avoid. `lintVital` does not catch it because the issue's default severity is not fatal. | Not for T-165. Lead: file a follow-up to add the `uses-feature` to the sms manifest and lint one Sms variant in CI. | Lead → ADR-004 owner / new FU |
| 7 | nit | `.github/scripts/check-no-os-backup.sh:110-124` | The manifest assertions count attributes across the whole manifest instead of anchoring them to `<application>`. A (malformed) attribute on another element would satisfy the count while `<application>` lacked it. This is unrealistic, because aapt2 and the merger would not produce it, but it is a weaker guarantee than the rules-file parser gives. | Optionally scope the greps to the lines between `E: application` and the next element at the same indentation. | T-165 follow-up |
| 8 | nit | `.github/scripts/check-no-os-backup.sh:145-152` | The `mktemp -d` work directory leaks on the early-return path when the manifest check fails. This is harmless on CI runners. | Add `trap 'rm -rf "$work"' RETURN`, or clean up before `return 1`. | T-165 follow-up |
| 9 | nit | `docs/05-reviews/T-165-device.md:56-58` | The `dd bs=24 skip=1` + zlib step assumes an unencrypted `adb backup`. If the tester enters a desktop backup password, the header is longer and the step fails confusingly. | Add "leave the backup password empty on the device prompt". | T-165 follow-up (doc) |
| 10 | nit | `docs/05-reviews/T-165-device.md:108, 116-122` | Some cheap device checks are missing. (a) No `AppDomainGroup-group.app.zaghlol*` row for the Finder check, so the App Group spool is never inspected once T-062 lands. (b) No step confirming that uninstall offers no "keep app data" option (`hasFragileUserData`). (c) The header does not record which flavor (Sms or NoSms) was tested. | Add an `AppDomainGroup` row marked "N/A until T-062", a one-line uninstall-dialog check on Android 10+, and a flavor field. | T-165 follow-up (doc) |

## Checklist
- [x] `flutter analyze` clean (static job green; no Dart changes)
- [x] Tests added and passing (count: 10 XCTests required to pass and 1 skipped by design; 22 checker self-test cases; aapt2 assertion on 6 APKs; lint)
- [x] RTL + LTR verified (N/A: no UI)
- [x] No hard-coded strings (N/A: no user-facing strings)
- [x] No `double` money, explicit currency (N/A)
- [x] No sensitive data in logs (`os_log` emits the constant code only, `privacy: .public`, with no path or error)
- [x] Stays within the task's scope (`lint.xml`, the `build.gradle.kts` `lint {}` block and the workflow README are the minimum needed to run the required lint; no drive-by refactors)

## Notes for the Lead
- **Was the checker fail-closed and hard to fool?** Yes, by reading the code and the logs.
  - **aapt2 failures.** `check_apk` runs inside `if`, so `set -e` is suspended there. But aapt2 failures produce empty output, which then fails on a missing ROOT, attribute count 0, or an empty resolve.
  - **Falsy or odd values.** Booleans must match `=false( |$)` exactly. A bool resource reference, `true`, a missing attribute (where the default is true) or a duplicate all fail.
  - **Resource obfuscation.** Rule files are found by resource ID through `dump resources`, not by path, so obfuscated paths are handled; the green release run shows `res/Qq.xml`. Name collapsing fails closed.
  - **Rules-file shape.** A missing or extra domain, a duplicate exclude, `path` other than `.`, `<include>`, an unknown element, or a duplicate or missing section each fail. The parser is indent-adaptive and tolerates both 2-space and 4-space layouts.
- **CI integrity.** The diff adds no `continue-on-error` and no new actions. Every `uses:` in `app-ci.yml` is pinned to a SHA. The lint guard catches an `UP-TO-DATE`/`FROM-CACHE` lint task, because it greps for a bare `> Task :app:lintDevNoSmsDebug`.
- **Proof run coverage.**
  - **Debug jobs (devSms, devNoSms, stagingSms, stagingNoSms).** The aapt2 assertion caught both Android mutations.
  - **Release jobs (prodSms, prodNoSms).** `lintVital` stopped them first, at "Build APK", because of `bogus`. So the aapt2 step on release APKs was never shown red. It is the same script with the same inputs, and the green run shows it parsing the obfuscated release resources, so this is acceptable. F2 would close the gap without a device.
  - **kotlin-unit.** Lint failed as intended.
  - **swift-unit.** The two launch-dependent tests failed as intended.
  - **ios build jobs, golden, static.** Green as expected: the mutations don't affect them.
- **Before marking T-165 done**, F3–F5 are backlog edits you can make directly in T-062, T-063, T-166 and T-021. F1 needs an explicit open item so the device evidence actually gets recorded on the first RC.
- The test-engineer's in-progress report is at `/home/claude/zaghlol/docs/05-reviews/in-progress/T-165-tests.md`. Its findings line up with this review.

Files referenced:
- `/home/claude/zaghlol/docs/04-tasks/tasks/T-165.md`
- `/home/claude/zaghlol/.github/scripts/check-no-os-backup.sh` (branch `origin/t165`)
- `/home/claude/zaghlol/.github/scripts/test-check-no-os-backup.sh` (branch)
- `/home/claude/zaghlol/.github/workflows/app-ci.yml` (branch)
- `/home/claude/zaghlol/app/android/app/lint.xml`, `/home/claude/zaghlol/app/android/app/src/main/AndroidManifest.xml`, `/home/claude/zaghlol/app/android/app/src/main/res/xml/{backup_rules,data_extraction_rules}.xml` (branch)
- `/home/claude/zaghlol/app/ios/Shared/BackupExclusion.swift`, `/home/claude/zaghlol/app/ios/Runner/AppDelegate.swift`, `/home/claude/zaghlol/app/ios/RunnerTests/BackupExclusionTests.swift` (branch)
- `/home/claude/zaghlol/docs/05-reviews/T-165-device.md` (branch)
- `/home/claude/zaghlol/docs/04-tasks/tasks/{T-062,T-063,T-166,T-021,T-171}.md` (follow-up targets)