# T-175 Security assessment, pass 1 (source-only, cloud workspace)

| Field | Value |
|-------|-------|
| Task | [T-175](../04-tasks/tasks/T-175.md) (C4), pass 1 of 2 |
| Reviewer | `security-privacy-reviewer` (Opus) |
| Baseline | `security-model.md` (MASVS L2 + R, ASVS L2), CLAUDE.md §2, SRS BR-SYNC-03/04 |
| Tree | `main` @ `1d91d798`, worktree branch `task/T-175-assessment-1` |
| Date | 2026-11-19 |
| Verdict | **CHANGES_REQUESTED**: acceptance criterion "No open high/critical findings" is **not met** (H-1 is open). |

**Counts:** Critical 0 · High 1 · Medium 1 · Low 6 · Info 10.

"No Critical" is a statement about what pass 1 could see (static source, lockfiles, and host-runnable tests). It says nothing about what MobSF, ZAP, device testing and a pen test (§2) may find. Nothing in the app or backend code was changed: this pass is an assessment.

---

## 1. Scope covered

### 1.1 Dependency scans (SCA)

The usual tools could not be installed. `go install` failed because `proxy.golang.org` does not resolve; GitHub release downloads return 403; `api.osv.dev` is refused by the egress proxy. Instead I downloaded the OSV bulk export from `storage.googleapis.com/osv-vulnerabilities/<ecosystem>/all.zip` (Pub, NuGet, Maven, npm, GitHub Actions, SwiftURL) and matched it locally with a small script that evaluates OSV `ECOSYSTEM`/`SEMVER` ranges. The matcher was checked against a known positive control: `System.Text.Json 8.0.0` correctly reported GHSA-8g4q-xg66-9fp4 and GHSA-hh2w-p6rv-4g7w.

| Ecosystem | Source | Checked | Result |
|---|---|---|---|
| NuGet (backend, all 12 projects) | `dotnet list backend/Zaghlol.sln package --vulnerable --include-transitive` + OSV cross-check of every `obj/project.assets.json` | 219 package versions | **0 vulnerable** by both methods. Deprecated: test projects only (xunit 2.x "Legacy"; `System.IdentityModel.Tokens.Jwt` / `Microsoft.IdentityModel.Protocols*` 6.34.0 pulled in transitively by test tooling). Outdated with no advisories: OpenTelemetry 1.12/1.15, Serilog 9, and others (I-1). |
| Pub (app + packages + `tools/drift_codegen`) | `flutter pub get` (exit 0, no advisory or retraction warnings) + OSV on both `pubspec.lock` files | 187 hosted versions | **0 advisories** |
| npm (`backend/openapi`, the Spectral lint toolchain; CI only) | OSV on `package-lock.json` | 242 versions | **2**: lodash 4.17.23 (L-3) |
| Maven (direct Gradle declarations and plugins) | Read from `app/android/app/build.gradle.kts` and `settings.gradle.kts`, then matched against OSV | 13 coordinates | **2**: kotlin-gradle-plugin 2.4.0 and junit 4.12 (androidTest) (L-3) |
| Gradle transitive graph and plugin AARs | Not resolvable: no Android SDK in the workspace (`ANDROID_HOME` unset) | — | **Not covered** (§2) |
| Swift / CocoaPods | No `Podfile.lock` or `Package.resolved` in the repo; plugins are resolved at build time. PDFium (pdfium_flutter 0.4.3) is fetched by URL with a pinned checksum (`Package.swift:27`, podspec SHA-256 check). | — | Plugin pods **not covered** (§2) |
| Native binaries | `sqlite3` 3.9.1 (sqlite3mc) and `pdfium_dart` 0.4.3 downloads are SHA-256 pinned in the packages' build hooks (`asset_hashes.dart`, `pdfium_archive_integrity.dart`). Tesseract 5.5 comes in the tesseract4android AAR. | — | Binary CVE matching **not covered** (I-8) |
| GitHub Actions | All 74 `uses:` lines across the workflows | 11 actions | All are **pinned to full commit SHAs**; **0 advisories** |
| Container images | `backend/Dockerfile` | — | Floating tags (L-5); CI already runs Trivy on the built image (`backend-ci.yml` ~l.212) |

### 1.2 Secrets scan

`gitleaks` and `trufflehog` could not be installed (same network limits). I used **detect-secrets** (from PyPI) over all 4,289 tracked text files, a targeted regex pass over the working tree (AWS, GCP API key, GitHub/GitLab/Slack tokens, `-----BEGIN … PRIVATE KEY`, `"private_key"`, `client_secret`, `AccountKey=`), and a regex pass over the **full git history** (1,076 commits, `git log -p --all -G`).

Result: **no real credential found** in the tree or history. All 1,103 detect-secrets hits were triaged. They are test vectors (Wycheproof, JWS/keyed-hash/seat-proof vectors), synthetic test JWTs, Gradle verification checksums, Xcode scheme IDs, pinned public keys, a published root-certificate fingerprint, ARB copy strings containing the word "password", and the deliberate dev-only values below. The only `PRIVATE KEY` PEM in history is the placeholder `AAAA`/marker in `AppStoreConfigurationTests.cs:76,157`.

**Known dev-only values (excluded as accepted, each refused outside Development/Testing or in release builds):**

| Value | Where | Why it is safe |
|---|---|---|
| Catalog seed dev signing key `s0000a` (P-256 private `d`) | `tools/catalog_build/dev/dev_signing_key.json` | `verifySeedSignature` refuses `s0000x` kids unless `allowDevKeys` (`!kReleaseMode`); public half in `packages/zaghlol_catalog/lib/src/trusted_keys.dart:16-22`. See H-1: release currently has no other seed key. |
| Postgres role passwords `*_dev_only` | `backend/deploy/db/dev-passwords.sql:3-7`, `backend/docker-compose.yml:22,54,71,72,102`, `docker-compose.phone-test.yml`, `docs/qa/tools/run_backend_local.sh:6,8`, `docs/qa/tools/api_db_followup.py:286-295` | Local compose only; ports bound to 127.0.0.1 in `docker-compose.yml`. Production uses the secrets manager / IAM (T-140). |
| Local KMS key ring (`Kms__Provider=Local`, `local:seat`, `local:audit`, `local:install-pepper`) | Generated by `backend/tools/dev-keys.sh`, not committed | `KmsServiceCollectionExtensions.cs:49` refuses `Local` outside Development/Testing. |
| Dev response/entitlement keys `s0000d` / `e0000x` | `--dart-define=ZAGHLOL_DEV_KEYS`, `/dev/v1/app-keys` | `devBackendKeys` is empty under `kReleaseMode` (`sync_providers.dart:54`); `allowDevKeys: kDebugMode` (`:94,:138`); dev routes are mapped only in Development (`DevFakeStores.cs:36,55`). |
| Test signers, Apple/Play test roots | `backend/tests/**` | Test assemblies only. |

### 1.3 Focused source review (security model §1-§7, CLAUDE.md §2)

| Area | Evidence reviewed | Result |
|---|---|---|
| On-device encryption, keys (Dart) | `core/db/encrypted_open.dart`, `app_database_opener.dart`, `key_bootstrap.dart` | `PRAGMA key` is issued only by `openEncryptedExecutor` with a raw 256-bit key, which is zeroized after first use. `secure_delete=FAST` and FTS5 secure-delete are set. Residual I-7. |
| Keys (Android) | `platform/keys/AndroidKeystoreKek.kt` | AES-256-GCM, non-exportable, randomized encryption, StrongBox with fallback to the TEE, no auth or unlock requirement (by design, §3). Matches §3. |
| Keys (iOS) | `DbKeyKeychain.swift`, `SpoolKeychain.swift`, `SeatKeyStore.swift`, `AttestationHost.swift`, `GuardUserConfigStore.swift`, `SpoolStore.swift` | Every item is `AfterFirstUnlockThisDeviceOnly` and not synchronizable. Files use `completeUntilFirstUserAuthentication`. The wipe keeps only seat keys (`IosCaptureHost.swift:333-360`). Matches §3/§7. |
| Backup exclusion | Android `AndroidManifest.xml:28-36`, `data_extraction_rules.xml`, `backup_rules.xml`; iOS `Shared/BackupExclusion.swift` | `allowBackup=false`, all 9 domains excluded for both cloud-backup and device-transfer, `hasFragileUserData=false`; iOS `isExcludedFromBackup` is set and then read back. Matches §7. |
| SMS / notification ingestion logging | `git grep` for `Log.*`/`println`/`printStackTrace` in `src/main` and `src/sms` Kotlin: **none**. Swift `print`/`NSLog`/`os_log`: **none**. Dart `print`: none. `debugPrint` is muted by `installDiagErrorHandlers` and `installQuietErrorHandlers`. `SpikeLog` exists only in `src/devSms` and only when debuggable. | Meets CLAUDE.md §2.6, except for the start-up window (L-2). |
| SMS receiver / notification listener | `src/sms/AndroidManifest.xml:17-25` (`BROADCAST_SMS`), `main/AndroidManifest.xml:132-146` (`BIND_NOTIFICATION_LISTENER_SERVICE`, ongoing notifications filtered out); `src/noSms` removes all SMS permissions and the receiver | Correct. |
| Exported components | Merged-manifest sources: `MainActivity` (launcher + `zaghlol://`), `ShareActivity` (`SEND`, 4 MIME types; refuses `file://`, user-info authorities and our own providers, `ShareSource.kt:45-54`), `SafeToSpendWidgetReceiver` (APPWIDGET_UPDATE), `BankNotificationListener`, `SmsReceiver`; WorkManager `DiagnosticsReceiver` removed; `FileProvider` not exported (`cache/shared_images/` only) | One issue: L-1 (MainActivity extras). The widget receiver is missing from §7's list (I-10). |
| Deep links | `core/routing/deep_links.dart:19-30` | Allow-list, 256-char cap; `zaghlol://voice` only opens the Add sheet (no mic). No destructive target. |
| Network boundary (app) | `core/backend/backend_client.dart:84-99`, `transport.dart:13,77-131`, `sync_providers.dart:38-140`, `response_signature.dart:99-182` | HTTPS only (http allowed for localhost/LAN only under `kDebugMode`); no `badCertificateCallback`; no User-Agent; 1 MiB response cap after decompression; ES256 response signatures with pinned kids, dev kids refused in release. **Release pins nothing yet (H-1).** No analytics/ads/crash SDK (`test/privacy/dependency_scan_test.dart` passes; ML Kit datatransport CCT excluded via `build.gradle.kts:153-156` with the `CCTDestination.java` stand-in). |
| Voice (egress) | `features/voice/application/voice_controller.dart:134-151,229-233`; speech_to_text 7.5.0 Android `createRecognizer` | On-device recognition only when the OS confirms support; the online recognizer starts only after the consent sheet (D-42). iOS sets `requiresOnDeviceRecognition`. |
| Android TLS | `network_security_config.xml` | Cleartext off; release trusts system CAs only; user CAs only under `debug-overrides`. |
| iOS ATS / entitlements | `Runner/Info.plist`, `*.entitlements` | No ATS exceptions. Entitlements: Sign in with Apple, App Group, two keychain groups (own + `.shared`), iCloud Documents. No App Attest entitlement, deliberately (`platform-channels.md:361`). |
| Entitlement trust (BUG-001) | `gold/application/entitlement.dart:43-48,394-416,435-470`, `gating.dart:84,201-207`, `gold_store.dart:230-250` | The cached token is re-verified (ES256) on every read and bound to `sub == installId` (account token: `iid`). `debugOverride` is a no-op unless `kDebugMode`. Store `purchased` never grants by itself. **BUG-001 is still open**: `releaseEntitlementKeys` and `releaseResponseKeys` are empty (H-1). |
| Backend authn/authz | `Endpoints/**` (every mapped route), `Auth/OidcOperatorTokenValidator.cs:119-223`, `OperatorAuthStartupCheck.cs`, `AdminRolesLiveContractTests.cs` | Every `/admin/v1` route needs an operator role equal to the spec's `x-required-roles` (tested both ways). `/v1` install-scoped routes go through the `RequireInstallToken` group. Anonymous routes match the spec exactly: health, register, signed catalog snapshot, Apple form_post callback, Apple ASSN (JWS), Google RTDN (Pub/Sub OIDC). Operator JWT checks: algorithm allow-list with key-type match, exact issuer and audience, own lifetime rules, tenant/domain allow-list, `amr` MFA. Residuals: L-6 (no fallback policy), I-4 (phishing-resistant MFA is advisory by default). |
| Rate limits | `RateLimiting/ZaghlolRateLimits.cs:38-187`, `ForwardedHeadersStartupCheck.cs` | Per /24 (/56 for IPv6) token bucket before auth; per-token, registration, restore (sliding window), and support-lookup limiters. Forwarded headers are trusted only from configured proxies (`ForwardLimit=1`), and outside Development/Testing the host refuses to start without them. |
| Input validation | `AppleCallbackEndpoint.cs:28-110`, spec "unknown fields rejected" (`ArchitectureTests.TheUnknownFieldProbe…`) | Size caps, repeated fields refused, regex-checked values, constant intent URL. Good. |
| Logging redaction (backend) | `Observability/RequestLogMiddleware.cs` (route template, never raw path), `InstallLogHash.cs`, `ApiTests.RequestBodiesAreNeverLogged` | Meets §6 "Logging privacy". |
| Startup fail-closed (backend) | `KmsServiceCollectionExtensions.cs:44-49`, `OperatorAuthStartupCheck.cs`, `DevFakeStores.cs:36`, `HostStartupTests` | Production refuses Local KMS, a test issuer, operator auth turned off, fake stores, and missing forwarded-header config. |
| CI / supply chain | `.github/workflows/*.yml` | Top-level `contents: read` except `device-flows.yml` (write; `workflow_dispatch` / push to `ci/**` only). Commit jobs run no repo code. `head_commit.message` passes through `env:` (no injection). No `pull_request_target`. Store builds use `--obfuscate --split-debug-info` (`release-android.yml:139-141`, `release-ios.yml:111-113`); R8 is on by the Flutter Gradle plugin's release default. Gaps: M-1, L-4, L-5. |

### 1.4 Tests run (host only, no containers)

| Suite | Result |
|---|---|
| `Zaghlol.Application.Tests` | **1057 / 1057 passed** |
| `Zaghlol.Workers.Tests` | 30 / 30 passed |
| `Zaghlol.Ops.Tests` | 3 / 3 passed |
| `Zaghlol.Api.Tests` | 330 passed. 354 could not run: Testcontainers found no Docker (`DockerUnavailableException`). 1 failed: `HostStartupTests.TheApiRefusesToStartWithoutAKeyRing`, which passed 3 of 3 times when run alone (I-9). Ran with the `live` store traits excluded. |
| `Zaghlol.Infrastructure.Tests` | 485 passed; 677 need Docker |
| `Zaghlol.Contract.Tests` | 86 passed; 91 need Docker |
| App: `flutter test test/privacy test/features/security test/core/backend test/core/logging test/features/gold` | **381 / 381 passed** (data-boundary client/flows, dependency scan, plaintext scan, source guards, voice permission, app lock, response signatures, diag log, entitlement, binding vectors) |

Every failure except the one in I-9 was classified from the logs as `DockerUnavailableException`. Docker-dependent suites run in CI on PostgreSQL 17.

---

## 2. Scope NOT covered (pass 2) and what each needs

| Item | Why not here | Needs |
|---|---|---|
| **MobSF** static + dynamic (APK/AAB, IPA) | Docker Hub is blocked; MobSF source is on GitHub (403); there is no Android SDK, so no APK can be built; no macOS, so no IPA | A signed `prodSms` and `prodNoSms` AAB/APK and an IPA from `release-android.yml` / `release-ios.yml`; MobSF on a CI runner or workstation; for dynamic analysis, a rooted emulator (MobSF + Frida). |
| **OWASP ZAP** baseline + active scan | Image not pullable; **no staging** (T-140 BLOCKED) | A deployed staging backend with a production-like KMS adapter; ZAP with `backend/openapi/zaghlol-v1.yaml` imported; an install-token bootstrap script for authenticated `/v1` scans; an operator IdP test tenant for `/admin/v1`; rate limits relaxed for the scanner's source address only. |
| **Device dynamic tests** (MASVS-STORAGE/CRYPTO/AUTH/NETWORK/PLATFORM/RESILIENCE) | No device or emulator | Rooted Android + jailbroken iPhone; the T-171 `privacy_scan` on device after a scripted session; Keystore/Keychain attribute dump; `adb backup` / D2D / iCloud backup checks; logcat and Console capture during SMS, notification and share ingestion (including the L-2 window); `FLAG_SECURE` / recents / iOS privacy overlay; app-lock backgrounding; mitmproxy with a user CA (release must fail TLS) and a system CA on a rooted phone (signatures must reject tampering); drozer / `am start` fuzzing of exported components, including an **L-1 proof of concept**; Frida bypass of app lock and root detection (expected, record only). |
| **Manual pen test** (ASVS L2) | Needs staging and store sandboxes | Cross-install IDOR on every `/v1` route; seat move / restore / rebind abuse (D-52…D-66) with real Play Integrity and App Attest; forged or replayed ASSN V2 and RTDN; Apple callback; idempotency replay; IPv6 /56 and forwarded-header rate-limit evasion; operator OIDC (alg/kid/issuer/tenant/amr, `acrs` under `Enforced`); support-desk social-engineering paths (D-57). |
| Gradle transitive SCA, plugin native SDKs (Play Billing, play-services-auth, ML Kit, Glance…), CocoaPods/SPM of plugins | No Android SDK or macOS | `./gradlew :app:dependencies --configuration prodSmsReleaseRuntimeClasspath` → osv-scanner / OWASP dependency-check; `flutter build ios --config-only` then `Podfile.lock` → osv-scanner. |
| Native binary SCA (sqlite3mc, PDFium chromium/8125, Tesseract 5.5 / leptonica / libpng / libjpeg, Flutter engine BoringSSL) | No binary scanner available | Trivy/grype on the extracted `.so` / `.framework` with version metadata, or vendor advisories checked by hand. |
| DB-backed backend tests (1,122) | Testcontainers needs Docker | CI (`backend-ci.yml`) on PostgreSQL 17 is the gate. |
| Production KMS, secrets manager, IAM, WAF, TLS/HSTS config, DB network isolation | Not written yet (T-140) | Review of the T-140 IaC (`backend-iac-validate.yml`) plus a config scan of the deployed staging environment. |
| Store-policy review (Play SMS declaration, Data safety, App Privacy) | Out of pass 1 | T-176 / T-177 packages. |
| T-175 design note (task file: "Required — solution-architect … before implementation (C4)") | Not written | Pass 1 was run as an assessment at the Lead's direction. The architect's note should fix pass-2 methodology, tools and exit criteria. |

---

## 3. Findings

Severity follows CVSS-style impact × likelihood **in this product's threat model** (`security-model.md` §1). "Owner/class" is a proposal for the follow-up task, which the Lead decides.

### High

**H-1 — Release builds have no production trust anchors, and the backend has no production KMS (BUG-001 / T-140), so the core integrity chain is absent and unassessed.**
- `app/lib/features/catalog_sync/application/sync_providers.dart:38-40`: `releaseResponseKeys = []`.
- `app/lib/features/gold/application/entitlement.dart:46-48`: `releaseEntitlementKeys = []`.
- `packages/zaghlol_catalog/lib/src/trusted_keys.dart:16-22`: the only seed key is the committed dev key `s0000a`, which release refuses, so a release build can verify no bundled seed either. FU-090 says the seed must come KMS-signed from the backend.
- `backend/src/Zaghlol.Infrastructure/Kms/KmsServiceCollectionExtensions.cs:44,49`: the only adapter is `Local`, which Production refuses.
- **Impact:** fail-closed, so there is **no exploit today**. Nothing verifies, so Gold is never granted, flags never switch on remotely, and catalog/sync bodies are dropped. But the controls that protect catalog and flag integrity and Gold entitlements (ES256 signatures, KMS-held keys, key rotation) cannot be tested end-to-end, and a hurried late fix (for example adding a key list without the `kid` rules, or shipping with dev kids allowed) is the most likely way to introduce a Critical. Also tracked as QA BUG-001 (HIGH).
- **Required:** T-140 creates KMS keys and the cloud KMS adapter. Embed the current and next public JWKs for the `s…`/`e…` kids; replace the seed key with a KMS-signed one and remove `s0000a` from the release set; add the FU-263(b) CI guard that fails a `prod` build while either list is empty or contains a `?0000?` kid. Re-run this assessment's §1.3 network and entitlement rows against staging in pass 2.
- **Owner/class:** `backend-engineer` T-140 (C4) + `flutter-core-engineer` FU-115 (C4).

### Medium

**M-1 — The documented SCA and secret-scanning controls are not implemented for the app, Gradle, npm or the repo; only NuGet and the container image are scanned in CI.**
- `security-model.md` §6 "Dependencies": "Dependabot/Renovate; `dotnet list package --vulnerable` and SCA in CI; container image scanning; SBOM per release".
- As built: `backend-ci.yml:108-135` (NuGet) and the Trivy image scan (~l.212) only. There is no `.github/dependabot.yml` or `renovate.json`, no pub/OSV scan in `app-ci.yml`, no Gradle dependency check, no secret scanning, no SBOM step in `release-*.yml`.
- **Impact:** this pass found four advisories (L-3) that no CI job would have reported; new advisories against pub, Gradle or plugin dependencies after launch would go unnoticed.
- **Required:** an `osv-scanner` job on `pubspec.lock`, `backend/openapi/package-lock.json` and the resolved Gradle lockfile (enable Gradle dependency locking, or export `:app:dependencies`); Dependabot for `pub`, `nuget`, `npm`, `gradle` and `github-actions` (security updates at least); gitleaks on PRs; CycloneDX SBOMs from `release-android.yml`, `release-ios.yml` and `backend-deploy.yml`.
- **Owner/class:** new FU, `backend-engineer` + `flutter-core-engineer`, C2.

### Low

**L-1 — The exported `MainActivity` accepts the notification-route and cancel-ID extras from any app; one route performs a state change (mark bill paid) without user interaction, including while the app is locked.**
- `app/android/app/src/main/kotlin/app/zaghlol/MainActivity.kt:90-91,152-156,163-170` reads `app.zaghlol.notification.route` (`NotificationChannels.kt:41,47-48` only checks the shape: leading `/`, printable ASCII) and `EXTRA_CANCEL_ID` from the launching intent.
- `app/lib/features/notifications/domain/notification_routes.dart:59-61` maps `/recurring/<id>/paid/<yyyy-mm-dd>` to `MarkPaidTarget`.
- `app/lib/app/notification_taps.dart:49-62` then calls `billsActionsProvider.markPaid` directly.
- **Exploit path:** any installed app can call `startActivity(new Intent().setClassName("app.zaghlol", "app.zaghlol.MainActivity").putExtra("app.zaghlol.notification.route", "/recurring/<id>/paid/2026-12-01"))`. The app opens on top and records the payment. A second extra lets it cancel any of Zaghlol's notifications by ID.
- **Likelihood is low:** the recurring ID (`^[A-Za-z0-9_-]{1,64}$`, a random-based ID) is not observable by another app, and the effect is a data-integrity nuisance (a bill marked paid, an alert hidden), not disclosure. The `zaghlol://` path correctly has no such action (`deep_links.dart`).
- **Required:** accept route and cancel extras only from the app's own `PendingIntent`s. Either carry the per-process hand-off token the share path already uses (`ShareHandOff`), or route notification taps through a non-exported trampoline activity or receiver. Require a user tap inside the app (not only the intent) before `markPaid` runs. Add a drozer / `am start` negative test in pass 2.
- **Owner/class:** `native-platform-engineer` + `flutter-core-engineer`, C2.

**L-2 — Error and `debugPrint` redaction is installed only after the database opens; before that, or for the whole session if the DB fails to open, release builds print errors to logcat or Console.**
- `app/lib/main.dart:177-185` installs `installDiagErrorHandlers` inside `diagLoggerProvider.future.then(...)`, and `.catchError((_) {})` swallows a DB-open failure, so the handlers are then **never** installed.
- Until then `FlutterError.onError` is the framework default (`presentError` → `debugPrint`), and `debugPrint` is not muted, which contradicts `security-model.md` §7 ("`debugPrint` is stripped in release builds").
- **Exposure:** errors from `initDateFormatting`, `resolveDbDirectory`, `_resumeWipe`, the registry load, the first frames, `SharedItemsLifecycle`, and the key or orphan-DB paths. These rarely carry financial text, but shared-text intake and first-launch restore run in this window, and on a DB-open failure the session continues unredacted.
- **Required:** at the top of `main()`, synchronously install a code-only handler that buffers diag codes and mutes `debugPrint` outside `kDebugMode`; flush the buffer to `DiagLogger` once it is ready. Add a test that `debugPrint` is a no-op before any provider is read.
- **Owner/class:** `flutter-core-engineer`, C2.

**L-3 — Known-vulnerable build and test tooling (none ships in the app or the backend runtime).**
- `backend/openapi/package-lock.json:2373-2374`: lodash 4.17.23. GHSA-r5fr-rjxr-66jc (High, `_.template` import-key code injection; fixed 4.18.0) and GHSA-f23m-r3pf-42rh (Moderate, prototype pollution in `_.unset`/`_.omit`; fixed 4.18.1). Pulled in by Spectral 6.15.0 and run in CI (`backend-ci.yml:89`, `npm ci --ignore-scripts`) on repo-controlled input only, so not reachable by an attacker.
- `app/android/settings.gradle.kts:23,25`: Kotlin Gradle plugin 2.4.0, GHSA-r937-wjx7-w2jp / CVE-2026-53914 (unsafe deserialization of build-cache metadata; fixed 2.4.20). Relevant only for a shared or remote build cache.
- `app/android/app/build.gradle.kts:201`: `junit:junit:4.12` (androidTest), CVE-2020-15250 (TemporaryFolder permissions); test APK only.
- **T-192 disposition of the junit item (risk acceptance, awaiting PO signature).** junit 4.12 on the androidTest classpath is pulled in transitively by the `integration_test` plugin's `api("androidx.test.espresso:espresso-core:3.3+")` and `androidx.test:runner`; the plugin pins its own unit-test junit at 4.13.2 but not its instrumentation classpath, and `app/build.gradle.kts` must match what the plugin resolves (consistent resolution). A forced override could not be verified in the cloud workspace (no Android SDK or Gradle run), so it was not made blind. **Accepted risk:** CVE-2020-15250 (`TemporaryFolder` creates files readable by other local users) is reachable only when instrumented tests run on a developer or CI device or emulator; the test APK is never signed for release, never shipped, and not part of the release variants. No app or backend runtime code includes junit. **Condition to revisit:** the `integration_test` plugin (Flutter SDK) moves its espresso/runner dependency to a junit 4.13.2 release, or a verified `androidTestImplementation` constraint passes `:app:assembleDevSmsDebugAndroidTest`. **PO decision:** [ ] Accepted  [ ] Rejected, signed: ____________  date: ________
- **Required:** bump Spectral (or add a lodash ≥ 4.18.1 override), Kotlin to ≥ 2.4.20 (Compose compiler plugin to match), and androidTest junit to 4.13.2 if the integration_test classpath allows.
- **Owner/class:** `boilerplate-engineer`, C1.

**L-4 — The Play upload uses a long-lived service-account JSON key, contrary to §6 ("CI uses OIDC federation (no long-lived keys)").**
- `.github/workflows/release-android.yml:92,282` (`secrets.PLAY_SERVICE_ACCOUNT_JSON`). `backend-deploy.yml:81` already uses workload-identity federation, which the Play upload could also use (`google-github-actions/auth` with a Play-enabled service account).
- **Impact:** a leaked repo secret lets someone publish to the Play tracks. App Store Connect has no OIDC option, so the ASC `.p8` key (`release-ios.yml:252-254`) is an accepted exception: keep it in a protected GitHub environment with required reviewers.
- **Required:** WIF for the Play upload; release jobs in a protected `environment:` with reviewers; update §6 to name the ASC exception.
- **Owner/class:** T-176 / T-177, C2.

**L-5 — Backend base images are referenced by floating tags, not digests.**
- `backend/Dockerfile:5` `mcr.microsoft.com/dotnet/sdk:10.0` and `:22` `aspnet:10.0-noble-chiseled`. Builds are not reproducible, and a compromised or regressed tag would be picked up silently. Trivy and the non-root check (`backend-ci.yml` ~l.205-215) reduce the risk.
- **Required:** pin `@sha256:` digests and let Dependabot (M-1) bump them.
- **Owner/class:** T-140, C1.

**L-6 — No authorization fallback policy on the backend; `/v1` authentication is opt-in per route group, and no test enumerates anonymous routes.**
- `Auth/InstallTokenAuthentication.cs:34`, `Auth/OperatorAuthentication.cs:71`, `Auth/PubSubPushAuthentication.cs:272` add named policies only. `Program.cs:120-135` maps route groups.
- Today's anonymous set matches the spec exactly (§1.3). But a future `endpoints.MapPost("/v1/…")` outside `MapInstallScoped()` would be public by default, and only the admin prefix has a role-coverage test (`AdminRolesLiveContractTests`).
- **Required:** either `AddAuthorizationBuilder().SetFallbackPolicy(<authenticated>)` with explicit `.AllowAnonymous()` on the six public routes, or an architecture test that every `RouteEndpoint` either carries `IAuthorizeData` or appears on a named allow-list equal to the spec's `security: none` operations.
- **Owner/class:** `backend-engineer`, C2.

### Info

- **I-1 — Backend dependency hygiene.** 0 vulnerable NuGet packages. Many minor and major updates are available (OpenTelemetry 1.12 → 1.21, Serilog 9 → 11, .NET 10.0.10 → 11 packages, Testcontainers 4.6 → 4.17, xunit 2 → v3). No advisories; schedule them with M-1's bot.
- **I-2 — Pub, GitHub Actions and Swift (SwiftURL) data: 0 advisories.** Actions are all SHA-pinned.
- **I-3 — Native downloads are integrity-pinned.** sqlite3mc (`sqlite3-3.9.1/lib/src/hook/asset_hashes.dart`) and PDFium (`pdfium_dart` `verifyPdfiumArchive`; `pdfium_flutter` SPM checksum / podspec SHA-256). The pins themselves were checked; the binaries were not.
- **I-4 — Operator phishing-resistant MFA defaults to `Advisory`** (`OperatorAuthOptions.cs:74`), with a startup warning (`OperatorAuthStartupCheck.cs`). This is the documented residual R3-9/R4-6. Make sure the production config sets `PhishingResistantMode=Enforced` with `RequiredAcrs` on Entra (T-136 / T-140) and verify it in pass 2.
- **I-5 — Dev material is committed by design** (§1.2 table). Release and production refuse each item; the repo is public (`release-android.yml:238`), so treat these keys as known to everyone.
- **I-6 — App lock is a UI gate, not a crypto gate** (`security-model.md` §3, §4.3; `DeviceSecurityHost.kt:148-190`, `DeviceSecurityHost.swift:15,51`). A hooked app can skip it; this is accepted by design (background capture). Pass 2 records it under MASVS-AUTH only.
- **I-7 — The `PRAGMA key` hex is built as an immutable Dart `String`** (`core/db/encrypted_open.dart:211`), so that copy cannot be zeroized and stays in the heap until GC. The key bytes themselves are zeroized. This is a language limitation; accept and document it in §3.
- **I-8 — Native parsers of untrusted input:** PDFium (statement import), Tesseract/leptonica and ML Kit (shared images), and the platform image decoders. They are not sandboxed beyond the app process. Binary SCA and fuzzing belong to pass 2 (§2).
- **I-9 — `HostStartupTests.TheApiRefusesToStartWithoutAKeyRing` is flaky in a full-suite run.** It got `ObjectDisposedException` from `DeferredHost.StartAsync` instead of `KmsConfigurationException`, most likely an interaction between `Program.cs:117` (the BUG-002 fix resolves `HostExitCode` before `RunAsync`) and the startup failure. It passed 3 of 3 runs alone. It is a fail-closed startup test, so a flaky one weakens the guarantee. **Owner:** `backend-engineer`, C2 (add to FU-263).
- **I-10 — Security-model §7 IPC list drift.** It omits the exported `SafeToSpendWidgetReceiver` (`AndroidManifest.xml:78-87`, no permission: any app can force a widget refresh, which is harmless) and does not mention `MainActivity`'s intent extras (L-1). The phone-test compose file (`docker-compose.phone-test.yml:68-88`) publishes a Development API with `Dev__FakeStores=true` (`POST /dev/v1/grant-gold`) on all interfaces: intended for LAN phone tests, but `run-backend-locally.md` should warn against untrusted networks. **Owner:** docs, C1.

---

## 4. What would close T-175

1. H-1 is closed (T-140 keys and KMS adapter, FU-115 pinning, the CI guard), then re-verified against staging.
2. M-1 and L-1…L-6 are fixed or explicitly risk-accepted by the PO and recorded in `docs/01-requirements/requirements.md` §13-15.
3. Pass 2 (§2) runs MobSF, ZAP, device dynamic tests and the pen test; their findings are tracked to closure in `docs/05-reviews/security-assessment.md` (the task's named artifact). Only then can "No open high/critical findings" be claimed on evidence.
