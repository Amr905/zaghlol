# Release pipelines and store packages (T-176, T-177)

Status: **prepared, not shipped.** Everything that needs no secret is done and dry-run on GitHub. Going live is blocked on the store accounts and signing material listed in `docs/workflow/PO_DECISIONS.md` Part 2 ("Store release").

| File | What it is |
|---|---|
| `.github/workflows/release-android.yml` | prodSms / prodNoSms App Bundles; unsigned dry run, signed + Play internal upload when the secrets exist |
| `.github/workflows/release-ios.yml` | prod archive / IPA; unsigned dry run, signed + TestFlight internal upload when the secrets exist |
| `.github/scripts/release-version.sh` (+ `test-release-version.sh`) | version and build-number derivation |
| `app/fastlane/Fastfile` | `android internal` (supply), `ios archive_signed` (match-free signing, see below), `ios testflight_internal` (pilot) |
| `app/android/app/build.gradle.kts` | upload-key signing config (`ZAGHLOL_UPLOAD_*` env or git-ignored `key.properties`), native debug symbols in the AAB |
| `play-data-safety.md`, `play-sms-declaration.md` | Play Console answers and the SMS declaration package |
| `app-store-privacy.md` | App Privacy answers, privacy manifest status, App Review notes |
| `store-listing.md` | ar + en listing skeleton, no invented claims |

## How to run

Both workflows are `workflow_dispatch` only (Actions tab, or `gh workflow run release-android.yml --ref main -f flavor=both -f upload=true`). Each runs in a protected GitHub environment (`android-release`, `ios-release`). The PO creates them in Settings > Environments, adds required reviewers, restricts deployment to `main` and `v*` tags, and puts the secrets there (not at repo level).

Signing and upload are decided per run from what exists:

| Condition | Result |
|---|---|
| No signing secrets | builds the prod flavor **unsigned** (Android: debug-signed, iOS: `--no-codesign`), runs every assertion, keeps a 3-day artifact labelled UNSIGNED, prints a notice. This is the dry run. |
| Signing secrets present | signed build. Android: `ZAGHLOL_REQUIRE_UPLOAD_KEY=true`, so Gradle fails instead of falling back to the debug key, and the workflow fails if the bundle carries the debug certificate. |
| Signed + upload secrets + `upload: true` + ref is `main` or `v*` | upload to the Play **internal** track (draft release) / TestFlight **internal** testers (no review submission, no external group). Promotion to closed, production or App Review stays manual. |

The repository is public, so signed bundles, IPAs, R8 mappings and dSYMs are never kept as artifacts in the clear. Play gets the R8 mapping and native symbols inside the AAB; App Store Connect gets dSYMs through the export. Dart `--split-debug-info` symbols, the mapping and dSYMs can be kept only as an artifact encrypted with `SYMBOLS_PASSPHRASE` (AES-256-CBC, PBKDF2 600000 iterations); without the passphrase they are not kept. No Crashlytics or other crash SDK (CLAUDE.md section 2). Decrypt: `openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in X.tar.enc | tar -x`.

## Version derivation

`BUILD_NAME` is the semver part of `version:` in `app/pubspec.yaml`. The build base is the `build_number` input, else the workflow run number. iOS `CFBundleVersion` = base. Android `versionCode` = base x 2 (+1 for prodNoSms), because both flavors share `app.zaghlol` and Play needs a unique, increasing code per uploaded bundle. Over 2,100,000,000 or a malformed version fails. The `+N` in pubspec is not used for stores.

## What the Android job asserts (on the AAB's universal APK, the T-165 review F8 follow-up)

Permissions (prodSms exactly READ_SMS + RECEIVE_SMS among the restricted ones; prodNoSms none), applicationId, minSdk 26, **targetSdk 36**, versionCode, no OS backup (`check-no-os-backup.sh`), SMS receiver / spike placement, no benchmark or spike code in `libapp.so`, 16 KB page alignment, system-CA-only `network_security_config` referenced from the manifest, signing state.

## What the iOS job asserts

Bundle ids (app, ShareExtension, widget), version and build number, no `NSAllowsArbitraryLoads`, `PrivacyInfo.xcprivacy` present with `NSPrivacyTracking=false` and required-reason **35F9.1**, extensions embedded, dSYMs present.

## App size (T-190, NFR-PERF-07)

Release builds ship arm64-v8a and armeabi-v7a only (no x86_64). Side-loaded per-ABI APKs: `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --flavor <prodSms|prodNoSms>`. Measured 2026-11-20: Play download arm64 28.8 MiB, unsigned iOS IPA 17.4 MiB (report: `docs/05-reviews/T-190-size.md`). Each release workflow runs `.github/scripts/check-app-size.sh` against `.github/size-baseline.json` (fails above +10 % or over the 40 MiB / 60 MiB budget); after an intended change update the baseline in the same commit. The `size-report` workflow (manual, or a push to `size/**`) prints the per-ABI breakdown and the bundletool download size.

## iOS signing: deliberate deviation from "fastlane/match"

The task text says fastlane/match. `match` needs a private certificates repository and a second passphrase. The pipeline instead takes one Apple Distribution `.p12` plus three provisioning profiles as secrets and lets fastlane switch `Release-prod` to manual signing at build time (`update_code_signing_settings`), leaving the committed project on automatic signing. Fewer moving parts; if the PO prefers match, only `archive_signed` changes. The signed path **could not be dry-run** (no Apple account); the unsigned path was.

## Store requirements tracked here (researched 2026-11-18)

- **Play target API.** "Starting August 31, 2026, new apps and app updates must target Android 16 (API level 36)"; an extension can be requested to **November 1, 2026**. The app already targets 36 (ADR-019) and the job asserts it. Source: Play Console Help, "Target API level requirements for Google Play apps" (support.google.com/googleplay/android-developer/answer/11926878).
- **Play SMS permissions.** SMS-based money management ("track and manage budget") is an exception for apps that are not the default SMS handler: eligible permissions `READ_SMS`, `RECEIVE_SMS`, `RECEIVE_MMS`, `RECEIVE_WAP_PUSH`; the declaration form in Play Console is required; exceptions are temporary and case by case; budgeting apps may not share non-financial or personal SMS history; no sale or research use of SMS data. Changing the use means resubmitting the form. Source: Play Console Help, "Use of SMS or Call Log permission groups" (answer/10208820). Details and the declaration text: `play-sms-declaration.md`.
- **Play Data safety.** Collection means "transmitting data from your app off a user's device"; data processed only on the device is not collected; a privacy policy URL is required to complete the form; the form asks whether all collected data is encrypted in transit and whether users can request deletion. Source: answer/10787469.
- **Apple privacy manifest.** Apps that use required-reason APIs without declaring the reason in their privacy manifest "aren't accepted by App Store Connect" (since 2024-05-01). Each executable with such use needs its own manifest (app and the Share extension have one; the widget extension: see `app-store-privacy.md`). Source: Apple, "Describing use of required reason API".
- **Apple SDK minimum.** "Apps uploaded to App Store Connect must be built with Xcode 26 or later using an SDK for iOS 26" (effective 2026-04-28). `release-ios.yml` therefore selects Xcode 26 on the runner (app-ci still pins 16.4 for its no-codesign legs; moving app-ci is a follow-up). Source: developer.apple.com/news/upcoming-requirements.
- Play Billing 8+, Sign in with Apple parity and in-app account deletion: `docs/03-technical/deployment.md` section 2.

## Not done here (needs the accounts)

Play app creation, Play App Signing enrolment, upload key generation, the SMS declaration submission and demo video, App Store Connect record, App Privacy submission, TestFlight group, the real policy URLs (FU-195), Play Integrity cloud project number (`PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER` variable), and the pre-launch report AC ("both AABs pass the Play pre-launch report"). T-176 and T-177 stay open until those are done; their acceptance criteria are only partly met by this prep.
