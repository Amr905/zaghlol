# Review - batch 44 (T-137 ops CLI; T-175 L-1 and L-2 fixes)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer + security-privacy-reviewer (Opus, one combined report) |
| Date | 2026-11-19 |
| Diff | `git diff batch/2026-11-19-43-qa-fixes HEAD` on `batch/2026-11-19-44` (HEAD c07b2395) |
| Verdicts | **T-137: CHANGES_REQUESTED** (one security Medium, before merge, in `break-glass-unfreeze.sql`; the CLI itself has no blocker or major). **T-175 L-1 / L-2: APPROVED** (minors as follow-ups) |
| Not reviewed | `docs/05-reviews/T-175-pass1.md` (read for context only, as asked) |

## What I ran
- `dotnet build backend/Zaghlol.sln -warnaserror`: 0 warnings, 0 errors. `dotnet format --verify-no-changes`: clean.
- `Zaghlol.Ops.Tests`: 109 passed, 6 failed. All 6 are `CliIntegrationTests` and fail only because Docker is not reachable (Testcontainers).
- `flutter test test/app test/core/logging test/core/l10n test/privacy`: all passed (includes the new `payAfterGate` and `early_error_handlers` tests, ARB parity and the privacy guards). `flutter analyze` on the touched Dart files: no issues. `dart format`: 0 changed.
- Not run here: the Kotlin unit tests (no Android SDK) and every DB-backed test (no Docker). What CI has to prove is listed at the end.

---

## T-137 - `zaghlol-ops` CLI, runbook, privacy disclosures, break-glass SQL

### Acceptance criteria

| AC | Result | Evidence |
|----|--------|----------|
| 1. Every admin endpoint reachable from the CLI, each with its audit row (Testcontainers) | **Met in code, CI to prove** | `CommandLineTests.EveryAdminOperationOfTheSpecHasACommand...` passes (spec-driven). `CliIntegrationTests.EveryAdminOperationIsReachable...` runs every Admin operation and checks the audit row of **every audited one**: `catalog_draft_put` x3, `catalog_draft_create`, `catalog_draft_delete`, `catalog_publish`, `flag_update`, `price_override`, `contribution_promote`, `contribution_reject`, `support_lookup` x2, `support_seat_move` x2, `support_detach`; `support_unfreeze` is checked in the second test. The builder's note that only support commands are asserted is **wrong**: catalog, flags, prices and contributions are asserted too. The operations without an audit check (`metrics daily-active`, `bank-requests list`, `catalog draft list`, `contributions list`, `flags get`) are reads, and the server writes no audit row for reads by design (backend-api.md §1 "every write audited"). AC1 is not missed. |
| 2. R3-9 auth code + PKCE over loopback; test that device-code is never called | Met | `OidcLogin.cs` reads only `issuer`, `authorization_endpoint`, `token_endpoint`; `grant_type` is always `authorization_code`; S256 only. `OidcLoginTests.LoginUsesAuthorizationCodeWithPkceAndNeverTheDeviceCodeFlow` and the integration test assert the grant types and that no device endpoint is requested. Issuer mix-up check, state on the callback, nonce/aud/iss on the ID token, HTTPS endpoints, no redirects followed (`OpsEnvironment.cs:65-71`). |
| 3. D-57: no order-ID option or env var, echo off, sentinel absent from all output | Met | Parser has closed option lists; `--order*`/`--owner*` gets a fixed message and no value is echoed (`CommandLine.cs:321-325`); support writes take 0 positionals. Env reads go through an allow-list (`OpsEnvironment.cs:41`). Prompt: `Console.ReadKey(intercept: true)`, no mask, refuses redirected input, `char[]` cleared, bytes zeroed (`SecretPrompt.cs`, `CommandContext.cs:78-115`). `Printer` redacts the value as a second line of defence. Sentinel tests cover 2xx/4xx/5xx/network/timeout, an API that echoes the value, and tempting env vars. |
| 4. Runbook: one action per alert, R4-7(3), R5-5(b), R4-6 | Met | `docs/ops/support-runbook.md` §4, §5, §6, §7; `RunbookTests` ties every alert rule to an action. Reviewed by me: see F5 and F7. |
| 5. R6-1 quarterly role review records dual-role holders | Met | Runbook §9 item 2 with the query; the server-side rule is the PO's choice (PO_DECISIONS R6-1), disjoint-roles fallback described. |
| 6. R5-5(a) residual documented with alert containment | Met | Runbook §5 last paragraph. |
| 7. Helpdesk PDPL status and ticket retention recorded (OQ-16) | Met as an open record | Runbook §10 records vendor, PDPL processor status and ticket retention as **PO to confirm**, and sets an interim same-day order-ID redaction rule that applies regardless. Must be closed before release (T-176/T-177 and the notice depend on it). |
| 8. Privacy-disclosure doc covers §2a items 1-4, linked from T-028/T-162/T-176/T-177 | Met | `docs/ops/privacy-disclosures.md` matches security-model §2a wording; adds the helpdesk item 5; the four task files link it. |
| 9. DoD | Met for the CLI | Build clean, formatted, tests added. No UI, no money, no SMS. |

### Findings

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| F1 | **Security Medium - before merge** (code: major) | `backend/deploy/db/break-glass-unfreeze.sql:18,31,38` | The input check accepts an upper-case UUID (`[0-9a-fA-F]`) and the audit row's `target` is the raw input `:'purchase'`. The API writes and reads `target` as `purchaseId.ToString("D")`, which is lower-case (`SupportActionStore.cs:198,216`), and `NewestUnfreezeAsync` matches `target = @target` exactly (`:71-74`). **Exploit path:** the DBA pastes the purchase UUID in upper case (common from some consoles and Windows tools); the freeze is cleared, but the `support_unfreeze` row is invisible to the server, so the R6-1 24-hour lock (`SupportRules.UnfreezeLockActive`) never applies. The single operator who made the correction can then redo the protected move at once, and the row is also missed by every per-purchase audit query (90-day move count, lookup history, the second-lead check). That is exactly the bypass R6-1 forbids, made silently. | Write `target` as `(:'purchase'::uuid)::text` (canonical lower case) and use the same value in the `WHERE`. Add a short test (DB-backed is fine for CI) that runs the script with an upper-case UUID and then asserts the same operator's ordinary move is `409`. |
| F2 | Security Low / code minor (fix together with F1) | `backend/deploy/db/break-glass-unfreeze.sql:28-35` | The script relies on people for three conditions it could check itself: (a) the PO rule says "after a 24 h lock" and backend-api.md:618 requires 24 h since the freeze row, but the script unfreezes a freeze that started minutes ago; (b) it does not check that the requesting operator holds `support_lead` (roles are in `zaghlol.operators.roles`); (c) the runbook and PO_DECISIONS allow break-glass only "if only one operator exists", but the script also runs when a second enabled `support_lead` exists, which would make it a way around the different-operator rule. All three are still gated by `migrator` access and PO approval, so this is Low. | Add to the CTE: `dispute_frozen_until - interval '30 days' <= now() - interval '24 hours'`, `'support_lead' = ANY(op.roles)`, and `NOT EXISTS` another enabled operator holding `support_lead` (or state in the runbook why one of these is waived). Fill `freeze_audit_id` from the newest correction row instead of `NULL` (nit). |
| F3 | minor | `backend/src/Zaghlol.Ops/Program.cs:9-13`, `Cli/SecretPrompt.cs:268` | Ctrl-C at the order-ID prompt does nothing visible: `CancelKeyPress` sets `e.Cancel = true` and cancels the token, but `Console.ReadKey` keeps blocking and Ctrl-C is never delivered as a key (no `TreatControlCAsInput`), so the Ctrl-C branch in the prompt is dead. After Enter nothing is sent (the cancelled token stops the request; checked), so nothing leaks, but the operator is stuck until Enter or Escape. The design note says Ctrl-C cancels. | Set `Console.TreatControlCAsInput = true` while the prompt runs (restore after), or document Escape only. |
| F4 | Security Low | `backend/src/Zaghlol.Ops/Commands/SupportCommands.cs:16-17,41-44` | `support lookup --email ADDRESS` puts a user's e-mail into shell history and the process list (`ps`), where D-57 is careful to keep the order ID out. The server side hashes the e-mail in the audit row, so the CLI is the weakest link. | Follow-up: read the e-mail from a terminal prompt (`--email -`, or a prompt when `--email` has no value), or tell agents in runbook §4 to prefer `--install` and to use a shell with history off. |
| F5 | minor (docs) | `docs/ops/support-runbook.md:132` | The quarterly review says "Run as `ops_ro`". `zaghlol_ops_ro` is a break-glass-only login whose credentials are not issued until T-140 (T-122 F1, backend-schema.md:422). | Say "run as `migrator` (or the T-140 read path)" until T-140 decides. |
| F6 | minor | `backend/src/Zaghlol.Ops/Api/AdminApiClient.cs:42`, `OpsConfig.cs:171-185` | `new Uri(config.ApiUrl, "/admin/v1/...")` drops any path prefix in `apiUrl` (an API behind `https://host/api/` would be called at `https://host/admin/...`). Same origin, so the token does not leave the host, but the call goes to the wrong place. | Reject an `apiUrl` with a path other than `/` in `OpsConfig`, or join paths. |
| F7 | nit (docs) | `docs/03-technical/design-notes/T-137.md` §3 vs `Cli/CommandContext.cs:141-161` | The note says API problems are printed as status and code only; the CLI also prints the server's `title` and `detail` (sanitised to printable ASCII, capped, redacted). The runbook (§2.3) describes the real behaviour. | Align the design note. |
| F8 | minor | `backend/src/Zaghlol.Ops/Auth/WindowsCredentialStore.cs:50-72` | `ITokenStore.WriteAsync` promises "stored and read back"; the Windows store returns `true` without reading back (macOS/Linux do read back). | Read back and compare, as the process store does. |
| I1 | Info | `Auth/TokenStores.cs:174-179` | macOS: an item created by `/usr/bin/security` trusts that tool, so any process of the same user can read it without a prompt. This is the accepted same-user residual in the design note and runbook §2.2. `security -i` may truncate very long lines; the read-back turns that into the memory fallback, which is safe. | None; keep the manual first-run check in runbook §2.2 for Windows and macOS. |
| I2 | Info | `Cli/SecretPrompt.cs:205-210` | No-echo relies on .NET's terminal handling between `ReadKey` calls. Fine in my reading, but it is not testable here. | Manual check per OS at first setup: type and paste an order ID quickly and confirm nothing appears and the terminal echo is restored after the command. |

### Break-glass script: is it safe, and does it bypass R6-1?
- **Allowed by the PO:** PO_DECISIONS R6-1 says "If only one operator exists, the unfreeze needs the break-glass procedure in the runbook." So a privileged path outside the API is expected, and the runbook gates it on a ticket, a store-console check by the lead, and PO approval.
- **Safe in construction:** psql `:'var'` quoting (no injection), input shape checked before anything runs, `ON_ERROR_STOP`, one statement with `FOR UPDATE` on the purchase, commit only when exactly one audit row was written, else rollback with a message that names no value. It touches only `dispute_frozen_until` (like the API), writes `at` from the database clock (no back-dating even though `migrator` bypasses RLS), and stores no order ID (the audit CHECK would refuse one anyway). No alert is raised automatically; the runbook makes the lead post it and applies the second-lead check.
- **Does it bypass R6-1 more than allowed?** It waives the different-operator rule, as the PO allows. It keeps the 24-hour lock for the requester only when the purchase UUID is typed in lower case (**F1**), and it does not enforce the "24 h since the correction" rule or the "only one operator" precondition (**F2**). After F1 (and preferably F2) it matches PO_DECISIONS.

### Verdict T-137: **CHANGES_REQUESTED**
Only F1 must be fixed before merge (a few lines in the SQL script plus a test). F2 should go in the same small fix. F3-F8 can be follow-ups. The CLI, the runbook and the disclosures doc are otherwise ready.

---

## T-175 fixes L-1 and L-2

### L-1: notification trampoline and per-process token
- **Forged intents, cold start:** `MainActivity` honours route and cancel id only through `NotificationRoutes.accept`, which needs `ACTION_TAP` and the per-process token (constant-time compare, 128-bit `SecureRandom`). Another app can still start the exported `MainActivity`, but without the token both extras are dropped (`MainActivity.kt:92-95`). `NotificationTapActivity` is `exported="false"`, so only our own PendingIntents (all `FLAG_IMMUTABLE`, `NotificationPresenter.kt:96-102,133-138`) can reach it. The trampoline runs in the same process as `MainActivity`, so the cold-start token is the one `MainActivity` checks. After process death, a re-created activity or a Recents relaunch carries the old token and is refused, which also stops stale replays.
- **Warm start:** `onNewIntent` uses the same check (`MainActivity.kt:184-187`) before dismissing or calling `onTap`.
- **Real taps and action buttons:** both PendingIntents now target the trampoline with the same request codes and flags as before. The trampoline forwards route and cancel id with `NEW_TASK | SINGLE_TOP` to the `singleTop` `MainActivity`. This is an activity trampoline, which Android 12+ still allows (the restriction applies to service and receiver trampolines). The action button's notification is still dismissed through the forwarded cancel id.
- **Manifest:** trampoline not exported, `taskAffinity=""`, `noHistory`, `excludeFromRecents`, translucent, no intent filter. `security-model.md` §7 updated.
- **Dart:** `payAfterGate` waits for the app lock (the controller starts locked, fail-closed), then asks for in-app confirmation, then pays. The lock screen is painted above the root navigator (`AppLockGate` in `MaterialApp.router` `builder`), so the dialog can't be answered over a locked app even in a warm-start race. New strings are in ar and en.

### L-2: early error handlers
- `installEarlyErrorHandlers()` is the first line of `main()`. In release and profile builds it replaces `FlutterError.onError` and `PlatformDispatcher.onError` (returns `true`, so the engine prints nothing) and makes `debugPrint` a no-op. Errors are kept only as `diagEventForError` events: a fixed code plus a `SafeException`'s constant code, never the message, the stack or `toString()`. So a raw SMS in an exception message cannot be printed or stored. The buffer is capped at 32 events and is dropped if the DB never opens; it is flushed once the diag logger exists. The test uses an SMS-like canary and asserts nothing is printed and only codes are stored.
- The headless ingestion entry (`ingestion_main.dart:71-74`) still installs its quiet handlers after `ensureInitialized` (not changed here, not SMS-bearing): Info.

### Findings

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| N1 | minor | `app/android/app/src/main/kotlin/app/zaghlol/MainActivity.kt:92-95` | Before, every `onCreate` called `setLaunchRoute(...)`, which also cleared a stale route. Now a launch without an accepted intent leaves any untaken route in the process-wide `NotificationRoutes.launchRoute`. `takeLaunchRoute` is take-once, so this matters only if Dart never took it (engine failure), but the old reset was free. | `NotificationRoutes.setLaunchRoute(accepted?.route)` unconditionally. |
| N2 | Security Low | `MainActivity.kt:156-169` | In the same process, if the Flutter activity was finished (Back) and the user reopens it from Recents, Android re-delivers the task's base intent, which may be the trampoline's intent with a still-valid token. The route replays. This is now behind lock and confirmation, and `markPaid` with `expectedDue` is idempotent, so the impact is a second dialog. | Ignore the extras when `intent.flags` has `FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`. |
| N3 | minor | `app/lib/app/notification_taps.dart:84-104` | The confirmation says only "Mark this bill as paid?", without the bill name or due date, so the user confirms a bill they can't see in the dialog. There is no widget test of the dialog in ar and en (CLAUDE.md §7; the unit tests cover only `payAfterGate` ordering). | Show the bill name and the locale-formatted due date; add a widget test in both locales that drives a real `MarkPaidTarget` through lock, then confirm and cancel. |
| N4 | Info | `NotificationPresenter.kt` | Notifications already on screen from the previous build target `MainActivity` directly. After the update, tapping one opens the app with no route (one-time effect). | None; mention it in the release notes if worth it. |

### Verdict T-175 L-1 / L-2: **APPROVED**
L-1 and L-2 are closed as specified in T-175-pass1. N1-N3 are follow-ups. The `am start` negative proof stays on the pass-2 list.

---

## What CI must prove (not runnable here)
1. **Backend (`backend-ci`, PostgreSQL via Testcontainers):** the 6 `CliIntegrationTests`, especially `EveryAdminOperationIsReachable...` (AC1 audit rows) and `UnfreezeNeedsADifferentLeadAfter24Hours...`. After the F1 fix: the break-glass script run with an upper-case UUID, then the same operator's ordinary move refused with `409`.
2. **Android (PC runner):** `NotificationHandOffTest` and the existing Kotlin suites; the merged-manifest exported-component check (T-041) still passes with the trampoline (not exported).
3. **Emulator (device-flows, or a manual run recorded on the task):**
   - `adb shell am start -n app.zaghlol/.MainActivity --es app.zaghlol.notification.route /recurring/<id>/paid/<date> --ei app.zaghlol.notification.cancel_id <id>`, cold and warm: no navigation, no dialog, no notification cancelled.
   - The same with `-a app.zaghlol.action.NOTIFICATION_TAP --es app.zaghlol.extra.NOTIFICATION_TOKEN 0000...`: ignored.
   - `am start -n app.zaghlol/.platform.notifications.NotificationTapActivity`: refused (not exported).
   - A real bill notification: content tap and the "Mark as paid" button, cold (process killed) and warm, with the lock on and off. The route opens, the action shows the dialog only after unlock, and the notification is dismissed.
4. **Operator workstations (manual, runbook §2.2):** `login` / `status` / `logout` on Windows (Credential Manager) and macOS (Keychain), plus the prompt no-echo check (I2).

## Lead delta check (2026-11-19)

F1 and two of the three F2 checks fixed by the Lead in `backend/deploy/db/break-glass-unfreeze.sql` (15 lines):
- The audit target is written as `(:'purchase'::uuid)::text`, the canonical lower-case form the API writes and looks up.
- The operator must hold `support_lead`, and no other enabled `support_lead` may exist (otherwise the API route applies).

Proof, local PostgreSQL 16 migrated with `Zaghlol.Workers --migrate`: an upper-case UUID run cleared the freeze and wrote target `aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee`; a `support_agent`-only operator was refused; with a second enabled lead the script refused and wrote no row. Not automated (the script runs under psql); recorded here. The third F2 check (24 h since the correction that started the freeze) is left as FU-264.

**T-137: APPROVED after delta.**

## Delta review: T-175 infra lane

Scope: `git diff 0595a0be HEAD` (fixes M-1, L-3, L-5 partial, L-6 of `T-175-pass1.md`). Reviewer: code-reviewer. Backend builds clean (0 warnings). DB/Docker tests cannot run here; the non-DB subset was compared against the base commit.

### Findings

**F1 (major) - the fallback policy breaks 39 existing non-DB tests in `Zaghlol.Api.Tests`.**
Base `0595a0be`: 0 non-Docker failures. HEAD: 39 (every one is `Unauthorized` where `OK/NotFound/BadRequest/...` is expected). `Zaghlol.Api.Tests` fails 354 on base and 393+ on HEAD for the Docker reason; the extra 39 are real.
Cause: the test hosts map routes without a policy or `AllowAnonymous()`, and `AddInstallTokenAuthentication` now installs the fallback. Affected: `Signing/SigningHostFixture.cs:114-182` (`/t/signed*`, `/t/anchored*`, `/t/unsigned`: ResponseSigningTests, TimeNonceTests), the `/t/...` routes behind `Installs/InstallsHostFixture.cs` used by RateLimitTests, and `Observability/ObservabilityHostFixture.cs` (VerboseLevelSentinelTests).
Required change: add `.AllowAnonymous()` to those test routes (or to the groups mapping them) and re-run; CI `backend-ci` would otherwise go red. Production behaviour is unaffected. `Zaghlol.Contract.Tests`: the 2 new tests pass; the other 88 non-Docker tests pass; 91 fail only on Docker.

**F2 (minor) - the live contract test covers only `/v1/` and `/admin/`** (`AnonymousRoutesLiveContractTests.cs`, route filter in the second test). `/dev/v1/*` and any future route outside those prefixes are not compared (health is `/v1/health`, so it is covered). Dev routes are mapped only in Development and are untested; their `AllowAnonymous()` is required (without it the fallback would 401 them) and is correct.

**F3 (minor) - `.gitleaks.toml` allowlists whole test trees** (`backend/tests/.*`, `app/test/.*`, `packages/*/test/.*`). A real secret pasted into a test file would be hidden. Prefer the `_dev_only` regex plus specific fingerprints; keep path allowlists to the named dev files only. `docker-compose*.yml` and `dev_signing_key.json` are documented dev-only values: acceptable.

**F4 (minor) - Dockerfile L-5 is not done** (digest pins are TODO comments, `backend/Dockerfile:5-8, 26`); the finding is only partially addressed as stated. Dependabot docker ecosystem will not bump an unpinned tag to a digest. Track as a follow-up with a named owner.

**F5 (nit)** - `dotnet-tools.json` lost its trailing newline (cosmetic). `dependabot.yml` `directory: /` for pub assumes the root `pubspec.yaml` is the app (CLAUDE.md puts the app in `app/`; the audit uses `/pubspec.lock`, so presumably a workspace root); confirm, or Dependabot finds no manifest.

### Checks that passed

- **Fallback policy semantics** (`InstallTokenAuthentication.cs:36-55`): applies only to endpoints with no `IAuthorizeData` and no `IAllowAnonymous`, so it cannot open a protected route nor override one. Install-scoped routes keep `RequireInstallToken`; the `/admin/v1/*` groups keep `RequireOperatorRole` (every admin MapGet/Post/Put/Delete found carries it: catalog, contributions, bank-requests, metrics, flags, prices, support); RTDN keeps `PubSubPushAuthentication.Policy`. The default-scheme handler returns `NoResult` for unmarked endpoints, so an unmarked route yields a 401 challenge and never a DB lookup. Unmatched (404) and 405 requests carry no `RouteEndpoint`, so they pass and keep their problem answers.
- **Anonymous set**: `GET /health`, `POST /v1/installs`, `GET /v1/catalog/{version}/full`, `POST /v1/apple/android-callback`, the Apple notification ingest, and the two `/dev/v1/*` routes carry `AllowAnonymous()`; nothing the app needs anonymously is closed. `RequireAppHeader` and the rate-limit/signing metadata on those routes are untouched.
- **Contract test** (second test): meaningful (compares the real endpoint data source with the spec's empty-`security` operations, asserts a floor of 4 and that no policy-less route is spec-anonymous). First test exercises the fallback directly for anonymous, signed-in, no-endpoint and 405 cases.
- **OpenAPI**: the 5 `security: []` additions match the 5 non-dev anonymous routes; no top-level `security` default exists, so the absent-key reading in the test is consistent.
- **Workflow**: `permissions: contents: read` only; third-party actions pinned by SHA with version comments; checkout, setup-dotnet and upload-artifact SHAs are identical to `backend-ci.yml`; the osv-scanner and gitleaks SHAs could not be verified offline (no GitHub API access in this session). Secrets: only `GITLEAKS_LICENSE`; PR comments and artifact upload disabled; no `pull_request_target`; `continue-on-error` is on the two scan jobs and documented as temporary, the SBOM job is blocking. Dependabot config is sane (weekly, grouped, small limits).
- **lodash override** (`package.json`, lockfile): single hoisted 4.18.1, five nested copies removed, consistent with the override; spectral-cli 6.15.0 unchanged.
- **Kotlin 2.4.0 to 2.4.20** (`settings.gradle.kts`): both plugins move together; Gradle verification metadata is not changed in this diff, so confirm `verification-metadata.xml` covers the new Kotlin artifacts (a Gradle build was not run here). The junit 4.12 deferral comment is accurate.

### Verdict

**CHANGES_REQUESTED** - one major (F1): add `AllowAnonymous()` to the test-host routes so the 39 regressed tests pass again. No blocker; the production authorization design is correct.

### Lead delta check: infra lane F1 (2026-11-19)

Test-only routes in `SigningHostFixture`, `ObservabilityHostFixture` (an anonymous route group) and `InstallsHostFixture` (`/t/ping`) now carry `AllowAnonymous()`. Production code unchanged. Api.Tests: 331 passed, 354 failed, all 354 Docker-unavailable (0 others). Contract.Tests: 88 passed, 91 failed, all Docker-unavailable. **Infra lane: APPROVED after delta.** Minors (gitleaks allowlisting whole test trees, L-5 digests, dev routes outside the anonymous-route test) go to FU-264.
