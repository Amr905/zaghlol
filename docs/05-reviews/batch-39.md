# Batch review — batch-39 (2026-11-18)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security, C4 tasks present) |
| Date | 2026-11-18 |
| Diff | `git diff origin/main...origin/task/<b>` per task; tests run on `batch/2026-11-18-39` |
| Tests run | backend `Zaghlol.Api.Tests` (Operator filter): `OidcOperatorTokenValidatorTests` 44, `OperatorAuthStartupCheckTests` 19, `OperatorIdpProfileTests` 12, `PhishingResistantRoleTests` pass. 31 endpoint tests fail locally because they need Docker (Testcontainers), and they ran green on GitHub (backend-ci 44305649838). `tools/catalog_build` `dart test` 63/63 and `--check` reproduces seed + sig. App `flutter test` mascot/capture/categorization/voice/home + `ocr_channel_test`: 606 pass (the one "failure" is a non-existent `test/features/ocr` path I passed). Kotlin was read, not built. |

| Task | Class | Verdict |
|------|-------|---------|
| T-136 (OIDC profiles) | C4 | **APPROVED** |
| T-159 (Android OCR) | C4 | **CHANGES_REQUESTED** |
| T-059 (merchant seed) | C1/C2 data | **APPROVED** (PO spot-check still due) |
| T-099 (mascot moments) | C2 | **APPROVED** (depends on batch app-ci Android/iOS build) |
| DEVICE-emu (T-165 evidence) | ops | **APPROVED** |

## T-136 — OIDC operator auth, Entra / Google by config

Traced logic. Issuer is exact (Google adds only the scheme-less alias). Audience is exact. JWKS key cache and kid/alg/key-type checks are unchanged. `exp`/`iat` are required with 60 s skew and a 1 h cap. `nbf` is relaxed only for Google (set to `iat`), and a malformed `nbf` is still refused. Entra `tid` and Google `hd` allow-lists deny by default, and startup refuses an empty list or a tenant that does not match the issuer path. `RoleMap` intersects with the row's roles, so the token can't grant roles and group overage leaves no roles. Google rejects `RoleMap` and `Enforced`. No secrets.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | minor | docs/03-technical/operator-idp-setup.md:11 | Per Microsoft's access-token claims reference, `amr` is a v1.0-only claim, so v2 access tokens probably carry no `amr`. If so, the Entra profile (MFA claim required) would refuse every operator. It fails closed, so this is not a hole. | Verify against a real tenant before T-137. Then either document ID-token use or v1 tokens, or require MFA via CA + `acrs` for Entra. |
| 2 | minor | operator-idp-setup.md:3 | A Google "Desktop app" OAuth client has a client_secret that the token exchange requires (Google treats it as non-confidential). "No client secret" is wrong for Option B. | Reword. The CLI ships the non-confidential secret. |

## T-159 — Android OCR (ML Kit + Tesseract4Android)

Checked and OK:
- `sealImage` canonicalises the path, so symlinks are resolved. It accepts only files under `cacheDir` and refuses anything else without deleting it. It caps the file at 25 MiB and the image at 64 MP, encrypts the image into the share store and zeroes the buffer, then deletes the plain file in `finally`.
- `recognize` discards the share in `finally` once the bytes were read and creates no temp file.
- No logs. Errors carry codes only.
- The `ara` model is pinned by size and SHA-256 and checked by a unit test. Apache-2.0 is recorded in ADR-009.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | **major (security, supply chain)** | app/android/build.gradle.kts:8-11 | Tesseract4Android comes from JitPack, which builds from mutable git tags. The artifact carries native `.so` that run in-process on decrypted receipt images, and nothing checks its integrity (ADR-009 admits this). `exclusiveContent` limits only *which* group comes from JitPack. | Add `app/android/gradle/verification-metadata.xml` with sha256 for `cz.adaptech.tesseract4android:tesseract4android:4.9.0` (aar, pom, module). Either verify everything or trust other groups with a `<trusted-artifacts>` regex. Show the ci/T-159 run green, and red with a corrupted hash. |
| 2 | **major (privacy, CLAUDE.md §2.1 / BR-SYNC-03)** | app/android/app/build.gradle.kts:139 | ML Kit brings `transport-backend-cct` / firelog SDK-usage telemetry to Google. Release builds will gain `INTERNET` for sync, so this becomes third-party traffic. The task left it as an open "PO point". | Exclude `com.google.android.datatransport:transport-backend-cct` (and the firelog backend) from the ML Kit dependency. Add a JVM or dependency test that the release runtime classpath lacks them, and prove OCR still works in `OcrInstrumentedTest` on ci/T-159. Alternatively, record a PO Part-1 acceptance before merge. |
| 3 | minor | OcrHost.kt:48 | `sealImage` is synchronous on the platform thread (up to 25 MiB read, bounds decode, encrypt), which can cause jank or ANR on slow devices. | Make it `@async` on the OCR executor (FU). |
| 4 | minor | docs/04-tasks/tasks/T-159.md:31 | Says "the OCR host never discards the share", which contradicts the rebase note and the code. | Fix the text. |
| 5 | minor | — | There is no in-app attribution for Apache-2.0 native libs (Tesseract4Android, tessdata) or the ML Kit terms. Android share-sheet `ocrPath` is still null, as the builder noted. | FU: register the licences via `LicenseRegistry`. The T-161 follow-up covers `ocrPath`. |

## T-059 — Egyptian merchant seed (854 merchants, 705 new)

What passed:
- Append-only: the first 149 merchants are identical in order and category.
- No alias key is shared across merchants, and no token-prefix alias shadows another category.
- Signed with the dev kid `s0000a` only, and `--check` reproduces the seed and signature.
- 20-row random sample: real brands in sensible categories, except item 3 below.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | minor | tools/catalog_build/data/catalog_curated.csv:668, 893 | Arabic normalisation strips the `ال` article, which leaves generic token-prefix keys: `gy` (LG, from "إل جي") matches any name whose first token is "جي", and `tby` (Altibbi, from "الطبي") equals "طبي", which means "medical". Aldo's key becomes `dw` (exact match). The pre-existing `abd` prefix (El Abd) matches every "عبد …" name. | Change these merchant rows to `exact` or remove the Arabic alias. Add a builder lint that rejects prefix keys of 3 characters or fewer. |
| 2 | minor | catalog_curated.csv (new rows) | 18 new merchants duplicate existing ones (Uber/Uber Egypt, Vodafone/Vodafone Egypt, Valu/Valu Egypt, Netflix, Noon, Jumia, Orange, Etisalat, Swvl, DiDi, Mobil, Faces, Sympl, Watch It, Vezeeta, VOX, THNDR, Zara Home). Same category, but per-merchant stats get split. | Next seed: fold the new aliases into the original id. Don't delete rows, because ids are append-only; mark the duplicates retired. |
| 3 | minor | catalog_curated.csv:1049 | VFS Global (visa centre) is filed under `entertainment`. | Move it to travel or bills. |

PO spot-check still applies, because the source links are unverified.

## T-099 — mascot moments, interim animation, Rive seam

Reduce motion shows the still, and Rive is never mounted then. Loops run only for listening, thinking, scanning and counting. The pull-to-refresh mascot is shown only while `onRefresh` runs. Tap lines come from ARB. If the Rive asset is missing or fails to load, the widget falls back to the still. It uses only the approved brand still. `rive` 0.14.11 and `rive_native` 0.1.11 are MIT and pinned by sha256 in `pubspec.lock`. `rive_native` downloads prebuilt binaries from `rive-flutter-artifacts.rive.app` at build time, and each download is checked against a hash shipped in the package (`hash.txt`, SPM checksum).

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | minor | app/pubspec.yaml:66 | `rive: ^0.14.11` uses a caret, while every other dependency in this block is pinned exactly. | Pin `0.14.11`. |
| 2 | minor | — | The CI build now depends on a third-party CDN (hash-checked). The batch app-ci Android/iOS run (44312210459) was still in progress when this review was written. | Lead: confirm it is green before merge. Note the CDN in the supply-chain docs. |
| 3 | minor | — | Pull-to-refresh is wired on Home only. The task also names Transactions. | FU. |

## DEVICE-emu — T-165 emulator evidence

I checked runs 44308240398 (API 34) and 44310207479 (API 30). Their logs match the claims in the task file for auto-backup (refused), restore (0/3 canaries), API 30 adb backup (header only) and D2D (UNKNOWN). The `api` input is passed via `env:`/`with:`, so it can't inject shell commands.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | minor | .github/scripts/t165-backup-emu.sh:97 | A 0-byte archive yields `RESULT PASS`. That is a false pass when the confirm screen was not tapped, which is what happened on API 34; the task file correctly disclaims it. | Report UNKNOWN unless a confirm tap was logged. |
| 2 | minor | t165-backup-emu.sh (flags `case`); T-165.md:153 | On API 34, `flags=0x0` passes the manifest check vacuously, yet the evidence ticks it for API 34. | Read the `flags=[…]` line or `ApplicationInfo`. Mark the API 34 row as not evidence. |

## Fix list (blocking only)

| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| T-159 | app/android/build.gradle.kts:8-11 | Gradle dependency verification (sha256) for the JitPack `cz.adaptech.tesseract4android` artifacts | ci/T-159 run green, and red with a corrupted checksum (evidence in task file) |
| T-159 | app/android/app/build.gradle.kts:139 | Exclude ML Kit datatransport/firelog telemetry backends (or a recorded PO acceptance) | Dependency/classpath check that the release runtime classpath has no `transport-backend-cct`, plus `OcrInstrumentedTest` green |

## Lead delta check: T-159 fix round (2026-11-18)

- **Supply chain (1adcdbd3, 27e38690):** `app/android/gradle/verification-metadata.xml` verifies `cz.adaptech.tesseract4android` (aar and module sha256, generated on CI run 44317027022). Every other group stays trusted through the regex. The temporary trust-all commit (6bcb80c0) is superseded. A CI negative proof corrupts the checksum and expects the build to fail.
- **Telemetry (1a92d267, 6bb45c05):** `transport-backend-cct` and `firebase-datatransport` are excluded from the app. A no-op `CCTDestination` stub keeps ML Kit linking, so nothing is uploaded. A CI classpath gate fails if the backends reappear in the prod release classpath.
- **CI:** Android builds and Kotlin tests are green on ci/fix39 (44323861749; `stagingNoSms` was a network flake, passed on rerun).

Verdict: T-159 **APPROVED**. All five tasks approved.
- **FU-260:** batch-39 minors: risky short merchant aliases, two false passes in the T-165 emulator script, the PO spot-check of the 705 merchants, `ocrPath` not set by Android share intake, the SPK-02 accuracy run, and the known `capture_providers_test` flake under load.
