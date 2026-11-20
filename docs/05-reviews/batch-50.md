# Batch 50 review (branch batch/2026-11-20-50)

Reviewer: code-reviewer (Opus 5.5). Diff: `origin/main...batch/2026-11-20-50`. Read-only on code.
Checked: `check-app-size.sh` self-test passes locally; `flutter test test/app` produced no result here (timed out, left to CI); the keep-rule, gitleaks and digest reviews are by reading. The analyze gate and the Gradle/R8 builds are CI's.

## T-193 AC3 app items: APPROVED

- MainActivity now always sets the launch route (null for a plain launch), so a stale route cannot survive a relaunch. `LAUNCHED_FROM_HISTORY` makes `NotificationRoutes.accept` return null, so a Recents relaunch neither routes nor cancels. The Kotlin tests cover both.
- `onNewIntent` also goes through `acceptedNotification`, so it has the same Recents protection.
- `MarkPaidConfirmDialog` takes the bill name and due text from `billItemProvider` and `ZDateFormat`, so digits follow the locale setting. A missing bill or an unparsable date degrades to the title-only dialog. Strings are in both ARB files and the generated l10n files are updated. The test covers en/ar text, direction, and the no-name case.
- Minor (nit): `notification_taps.dart` has a blank line between a `package:` import and the relative imports, and the import order is off (`locale_providers` before `generated`). `dart format` does not catch it. Fold into FU-272.
- Minor: the ar test asserts only `«Gym»`, not the due-date phrase. The en test checks the full phrase, so the risk is low.

## T-192: APPROVED (two minors)

- Digests: the same `openbao:2.7.2@sha256:5046...561f` is used in compose and `backend-ci.yml`. The Dockerfile pins both the SDK and the chiseled runtime. No unpinned `FROM`/`image:` is left in the backend except `postgres:17`, `otel` and `alpine` in the local dev compose files. Those are out of T-192 scope; note them in FU-272. Dependabot now has a docker-compose entry. The duplicate in the workflow env is documented as a manual sync.
- `.gitleaks.toml`: the blanket `backend/tests/.*`, `app/test/.*` and `packages/*/test` allowlists are replaced by named files. Every file I checked exists. Lock files are anchored. This narrows exposure, and any new test file with a trip pattern will now fail loudly, which is intended. No real-secret hiding found.
- `security-scan.yml`: the Gradle graph is now scanned instead of the checksum XML. The job stays `continue-on-error`, which is consistent with the stated triage plan.
- Minor: `gradle-deps-to-lockfile.py` `COORD` needs `group:artifact:version`. BOM/platform-managed lines print as `group:artifact -> version` and are silently dropped, so some transitives are not scanned (a coverage gap, not a false pass; the empty-graph guard still holds). `:buildEnvironment` runs on the root project only. Follow-up FU-272.
- setup.sh: the write-new-then-`mv` change is correct for 0400 files.

## T-190: APPROVED (minors)

- ABI: `variant.packaging.jniLibs.excludes.add("lib/x86_64/**")` for release, with `-Pzaghlol.releaseX86` as an opt-out. app-ci, release-android and size-report pass `--target-platform android-arm,android-arm64`. app-ci fails the release job if any `lib/x86_64/` entry remains. The release-android universal-APK step uses `-Ptarget-platform=`, which is the Flutter Gradle plugin's property.
- R8 keeps: they cover Tesseract4Android (JNI), ML Kit registrars, Glance receivers/widgets/ActionCallback, WorkManager workers, Billing, Play Integrity and Rive. Pigeon is correctly left out (no reflection). Manifest components are covered by aapt2 rules. `-keep class * implements ComponentRegistrar` is broad but small. app-ci builds release with R8 on every PR, so missing-class errors would surface there; the build prints R8 diagnostics. No keep for `androidx.biometric` is needed (consumer rules). The tooling cannot prove runtime reflection safety: the release builds have not run on a device. Make sure a release-configuration smoke test is on the pre-launch checklist (the `releaseX86` flag exists for that). FU-272.
- `check-app-size.sh`: logic is right (growth limit, budget warning vs enforce, unknown keys only printed, non-numeric fails). The self-test covers each branch and is wired into app-ci. `enforce_budget: true` in the baseline JSON conflicts with the script comment ("proposals until PO confirms, D-69"). With the baseline Play download at about 29 MiB against a 40 MiB budget it is not hit today, but it makes a PO-unconfirmed target a hard gate. Minor: confirm intent with the PO or set to false.
- Bundletool download (`size-report.yml:64`): fetched with `curl` from GitHub releases, version-pinned (`1.18.1`) but with no checksum verification. The hash is only printed. Severity: minor, not major. The workflow runs on `size/**` pushes and manual dispatch only, has `contents: read`, uses no secrets, `persist-credentials: false`, uploads text only, and signs with a throwaway key. A compromised jar could run arbitrary code only in an ephemeral runner with no secrets. Required: pin the expected sha256 in the workflow and `sha256sum -c`. FU-272.
- Baselines are measured values with the update rule documented. ADR-024 and `T-190-size.md` are consistent with the scripts.

## CI fixes from PR #85: APPROVED

- `KeyFingerprints.cs` and the setup.sh rename-over for 0400 files are correct and minimal.
- The Kotlin test fix (`NotificationHandOff.token.matches`) fixes the earlier per-instance mismatch.
- FU-270: the probe now uses `dart analyze` (whole workspace) and filters to the probe file's diagnostics, so another file's diagnostics cannot satisfy it. The probe is removed with its trap. Minor: whole-workspace `dart analyze` increases CI time; acceptable.

## Verdicts

| Task | Verdict |
|---|---|
| T-193 AC3 app items | APPROVED |
| T-192 | APPROVED |
| T-190 | APPROVED |
| CI fixes | APPROVED |

No blocker or major findings. Minors are proposed as FU-272 (a single follow-up bundling: import order in `notification_taps.dart`; gradle lockfile BOM gap; bundletool sha256; `enforce_budget` intent; device smoke test of the release/R8 build; digests for local-dev images). `docs/implementation-status.md` still says the next free number is FU-270; FU-270 and FU-271 are already referenced elsewhere, so the Lead should check numbering before filing.
