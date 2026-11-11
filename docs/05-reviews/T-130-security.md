# T-130 security and privacy review (Google Play verify, acknowledge, sweeper; FU-052 S-2)

Reviewer: security-privacy-reviewer (Opus). Branch `origin/task/T-130-play-verify` @ d758dca, diff against `origin/main` (EF Designer
files skipped). Inputs: `docs/04-tasks/tasks/T-130.md` design note, `security-model.md` §1 and §4 (purchase authorization),
CLAUDE.md non-negotiable 2a. I read all the non-Designer source and the main tests. Locally I ran `dotnet build -warnaserror`, which
is clean and includes `NuGetAudit` (mode all, level low), plus the Docker-free tests: `Zaghlol.Infrastructure.Tests` GooglePlay
(54 passed, including `PlaySentinelTests`) and `Zaghlol.Application.Tests` Purchases (86 passed). I did not run the Testcontainers
suites (no Docker here); those are on the PC runner.

## Verdict: CHANGES_REQUESTED

One Medium finding must be fixed before merge: **M-1, the sweeper's oldest-first window can be blocked for good**. M-2 is Medium
but can wait until go-live, which is already blocked on PO question 4. L-1 is Low, and I mark it **before merge** because the fix
is three lines. The other Low and Info items are follow-ups.

None of the findings lets anyone get Gold they didn't pay for. The entitlement path itself is sound: Gold is never granted on doubt
or for a forged, replayed or foreign token.

## What I checked and found sound

- **Never grant on doubt.**
  - `PlayVerification.VerifyAsync` writes nothing before the binding check and the state mapping.
  - An unknown or unspecified Play state throws `StoreUnavailableException` (502). So do 401/403, 408, 429, 5xx, a timeout, an open
    circuit and an unparsable 2xx (`PlayDeveloperApiClient.cs` l.172-180, 234-254).
  - `PENDING_PURCHASE_CANCELED` is a 422 with no row. Pending maps to `pending`, with no acknowledge and no grant (`PlayStateMapping`
    l.47-67; the `StatusOf` gate in `PlayVerification` l.88-93).
  - `NullVerifyGrant` returns no entitlement, and `PurchasesStartupCheck` refuses Production while it is registered or while the App
    Store verifier is missing.
- **Install binding.**
  - `StoreBindingRef.Matches` runs on every `RequireCaller` verify before any write. The comparison is constant time and fixed
    length, and an absent value fails.
  - The value is read from the right place for each API: subscriptions read
    `externalAccountIdentifiers.obfuscatedExternalAccountId`; `productsv2` reads the top-level `obfuscatedExternalAccountId`. I
    checked this against Google's `ProductPurchaseV2` reference ([purchases.productsv2](https://developers.google.cn/android-publisher/api-ref/rest/v3/purchases.productsv2)).
  - The HMAC key is public by design. That is correct: the check binds the store value to the install that the bearer token
    authenticates, so learning another install's ref gives an attacker nothing.
  - Cross-install replay gives `PURCHASE_NOT_OWNED` with no row written. The vector file is shared with T-145 and T-131.
- **Foreign tokens.**
  - The package comes only from config.
  - The product must be in the allow-list (exactly 3 products, typed by kind), and Play's product ID must equal the request's.
  - The token regex requires an alphanumeric character, so a token can never be a `.` or `..` path segment, and every path value
    is `Uri.EscapeDataString`-escaped. I found no SSRF or path injection.
  - v1 `products.get` and `subscriptions.get` don't exist in the client.
  - `latestOrderId` is not declared in any DTO (R5-8).
- **Monotonic writes.** `readAt` is taken before the Play call. The writer locks the row `FOR UPDATE` and applies only when
  `last_verified_at < @read_at`. `install_id` is written on insert only, and `acknowledged` never goes back to false.
- **Credentials.**
  - Production refuses `CredentialSource=None`, a non-Google base URL, a test package or product, and any `IPlayDeveloperApi` other
    than the real client.
  - The JSON key goes through `CredentialFactory.FromJson<ServiceAccountCredential>`, so an `external_account` config placed in the
    secret can't make the library run an executable.
  - Credential library errors become a constant-message `PlayAccessTokenException` (auth_error).
  - 401/403 are 502 plus `ZaghlolStoreAuthError` (paged, with a zero baseline sample), never a 422 that blames the user.
  - The bearer token is added per attempt inside the pipeline. `RemoveAllLoggers()` removes the HttpClient logs.
  - The key stays in memory for the process lifetime. That residual is documented and accepted.
- **Secrets in telemetry.** Tokens, order IDs, linked tokens and the obfuscated ref are `Sensitive<T>` or never logged. Outbound
  spans carry only URL templates. `PlayApiException` and `StoreUnavailableException` have constant messages and never read the
  response body. The sentinel test covers success, a Polly retry, a 404, 5xx exhaustion and a timeout across logs at Verbose, spans
  and exception text. Every metric tag comes from a constant set.
- **Idempotency (S-2, S-3, S-4, S-6).**
  - No connection is held while the handler runs. The claim, complete and release steps are short transactions.
  - The 30 s handler timeout is shorter than the 60 s lease. A lost lease means the answer is returned but not stored.
  - A takeover is possible only for the same (install, operation, key), so one install can't reach another's rows.
  - S-4: the `EXISTS … FOR SHARE` install guard covers both the claim insert and the final insert.
  - S-6: the envelope context `idem/v2/<install>/<op>/<b64u(SHA-256(key))>` binds the ciphertext to its row.
  - S-3: both the architecture test and the top-level `rotateInstallToken` scan are present.
  - Only 2xx, 409 and 422 are stored, and the CHECK constraints enforce this in the database too.
- **DoS bounds.**
  - Responses are capped at 256 KB through `MaxResponseContentBufferSize` with `ResponseContentRead`, which covers chunked bodies.
  - Attempt timeout 5 s, total 20 s, 3 jittered retries on transient errors only, and a breaker. Outside Dev/Testing the
    resilience values can't be changed.
  - The token is pre-validated with no Play call.
- **Migration and grants.** The migration adds one nullable column and two CHECKs. Grants are unchanged, and `ops_ro` doesn't get
  `claim_id`.
- **Supply chain.** `Google.Apis.Auth` 1.78.0 brings `Google.Apis`/`.Core` 1.78.0 and `Newtonsoft.Json` 13.0.4.
  `Microsoft.Extensions.Http.Resilience` 10.8.0 brings Polly 8.4.2. `WireMock.Net.Minimal` 2.21.0 is referenced only from test
  projects. All are centrally pinned with transitive pinning, and `NuGetAudit` reports no advisory at level low.
- **Sweeper lock.** A session `pg_try_advisory_lock` is held on one dedicated connection and unlocked on dispose. A dropped
  connection releases it, and a second runner is then harmless: acknowledge is idempotent and every update is guarded.

## Findings

### M-1 (Medium, before merge): the sweeper's fixed oldest-first window can be blocked for good, and Google then auto-refunds valid purchases

**Where:**
- `PlayAckSweepStore.cs` l.24-30: `ListSql` selects `state IN ('pending','active','in_grace','canceled_active')`,
  `ORDER BY created_at LIMIT 200`.
- `PlayAckSweepJob.cs` l.72 and l.94 (`Skipped`) and l.88 (`Failed`): none of these updates the row.

**How it fails:**
- Some rows stay in the 200-row window across runs:
  - pending purchases (Play allows slow payment methods to stay pending for days);
  - rows whose product left the catalog;
  - rows whose product doesn't match;
  - rows with an unknown state;
  - rows whose token now gets a final 4xx (`Failed`, never written).
- Every run then re-reads the same 200 oldest rows and never reaches newer `active` rows.

**Exploit:** an attacker with a Play account needs no money for this. They start 200 or more cash/slow-payment ("pending")
purchases, each bound to one of their own installs and verified once. That puts 200 `pending` rows at the head of the queue. From
then on, no newer purchase that missed its inline acknowledge is ever swept. Google refunds it at 72 h and the paying user loses
Gold (BR-GOLD-06). The same thing happens organically as stuck rows build up.

**What limits it:** the 48 h alert still fires, because `SummarizeAsync` counts every ackable row. So the failure is not silent, but
only an operator acting by hand prevents the refunds.

**A second effect:** expired, never-acknowledged rows stay in `ix_purchases_unacked` forever, so each run's scan grows over time.

**Required change:**
- Ackable rows must always be processed before pending ones, and a row that can't be processed must not block the rest. For
  example: `ORDER BY (state = 'pending'), last_attempt_at NULLS FIRST, created_at`, with a cheap `last_attempt_at` (or
  `next_sweep_at`) stamp written on `Skipped` and `Failed`. Any equivalent round-robin is fine.
- Add a test: 200 stuck rows (pending, unknown product, Play 404), then one newer `active` unacknowledged row, which is
  acknowledged in a single run.
- Optional: narrow the partial index, or the query, so terminal states drop out of the scan.

### M-2 (Medium, follow-up; must be resolved before go-live together with PO question 4): the Play call budget doesn't bound the real quota and has no reserve for acknowledgements

**Where:**
- `PlayDeveloperApiClient.cs` l.196: one `TryAcquire` per logical call, but the resilience pipeline inside it can make 4 HTTP
  calls.
- `StoreCallBudget.cs` l.32-50: a per-process bucket (600 burst, 130/min).
- `GooglePlayOptions.cs` l.30: sized as "~187 K/day per process".

**Exploit:**
- A single client network may register 60 installs an hour, and each install token may make 10 requests a minute.
- So 13 junk installs from one IP keep the verify lane of one API process at 130 calls a minute. Each well-formed junk token costs
  one Play 404.
- That denies real verifies (503) on that process, and the junk calls also use up the inline `ack` permits, because verify and ack
  share the bucket with no reserve for ack.
- With 2 or more API replicas plus the Workers process (each with its own bucket), or during a Play 5xx episode (retries not
  counted), real Play quota use can exceed the 200 K/day project quota. Play then returns 429 to everything, the sweeper included,
  for the rest of the day.
- No Gold is granted, but verification is unavailable and acknowledgements are delayed.

**Required change:**
- Count each attempt against the budget, for example by moving the acquire into a `DelegatingHandler` inside the retry, or by
  charging `1 + MaxRetries`.
- Size the bucket per replica (config: total quota / replica count), and document this in `deployment.md`.
- Keep a reserve in the shared bucket that only `ack` and `rtdn` may use, the same way restore is held to 30 %.
- Add a verify-specific per-install limit, for example 10 an hour.

### L-1 (Low, before merge): an active subscription with no parsable `expiryTime` is stored and answered as active with `expires_at = NULL`

**Where:** `PlayStateMapping.cs` l.47-48 (`Active`/`InGracePeriod` map to active regardless of expiry); `PlayDtos.cs` `PlayTime.Parse`
returns `null` for any missing or odd timestamp. The sweeper uses the same mapping.

**Risk:**
- A subscription row with a NULL expiry looks like a lifetime purchase.
- T-132 builds the entitlement `exp` from `ExpiresAt`. If it reads NULL as "no expiry", or falls back to a long window, a parsing
  gap or a Play format change grants open-ended Gold.
- This breaks "never grant on doubt".

**Required change:** for subscriptions, treat `Active`, `InGracePeriod` or `Canceled` with `expiryTime == null` as `Unknown`
(502, no write). Add a unit test.

### L-2 (Low, follow-up, owner T-185/T-133): verify never fills `install_id` on an existing row

**Where:** `PurchaseWriter.cs` l.76-84. `UpdateSql` never touches `install_id`.

**Risk:**
- Suppose the row is first inserted by restore (`BindingCheck.Skip`, which passes `install_id = NULL`) or by a later RTDN insert
  path. A binding-checked verify from the real buying install then never records it.
- The purchase then looks like its "buying install is gone". That opens the support attach gate (D-54, D-57) and closes self-service
  account attach for the real buyer, which makes social engineering of support easier.

**Required change:** on a `RequireCaller` verify, set `install_id = COALESCE(install_id, @install)`. The binding proves the caller
is the buyer. Add a test.

### L-3 (Low, follow-up): the ack sweeper alert can go stale or go missing

**Where:** `ZaghlolMetrics.SetUnacked` is an in-memory gauge, set only on the replica that held the lock.
- A Workers replica that once saw `ge_48h > 0` and then stops winning the lock keeps reporting it, so the page never clears.
- If the sweeper fails every run (DB error, logged by type only) or the Workers process is down, the gauge is never set. Nothing
  then pages before the 72 h refunds.

**Required change:**
- Export a `zaghlol.purchase.sweep.last_success` timestamp, with an alert when it is older than 1 h.
- Either reset the gauge on replicas that didn't run, or alert on the `AlertFired` counter only (already present).

### L-4 (Low, follow-up): `IsFinalRejection` is any other 4xx, not just 400/404/410

**Where:** `PlayPorts.cs` l.90.

**Risk:** a Play 409 or 412, or a 4xx caused by our own configuration (for example a package the service account can see but that
Play answers 404 for), becomes a stored `422 PURCHASE_TOKEN_INVALID`. That blames the user for 24 h of replays, with no alert. The
design note limits final rejections to 400, 404 and 410.

**Required change:**
- Restrict `IsFinalRejection` to 400, 404 and 410.
- Treat other 4xx as `client_error` → 502.
- Add an alert on a `client_error` rate spike.

### I-1 (Info): the base URL and package checks apply only in `Production`

`GooglePlayOptions.cs` l.148. Staging (neither "relaxed" nor Production) accepts any https base URL and a test package. A wrong
`BaseUrl` in Staging sends a real `androidpublisher` bearer token to that host. Consider applying the base-URL lock everywhere
except Development and Testing.

### I-2 (Info): a token-minting timeout is reported as an auth error

`PlayCredentials.cs` l.63. The catch-all also catches the `OperationCanceledException` from a Polly attempt timeout while the token
is being minted (metadata server or STS slow). That reports `auth_error` and pages for what is really a timeout. Map OCE to
`Timeout`.

### I-3 (Info): license-tester purchases grant Gold in production

They grant Gold, recorded as `environment = sandbox` (PO question 3). This is acceptable because only Play Console license testers
can make them. Keep the metric visible.

### I-4 (Info): the credential source is not enforced

`Purchases:Google:Credential` is read from any configuration provider, so nothing stops it from being placed in `appsettings*.json`.
The deployment doc says secrets manager. A startup check could refuse it when the value comes from a file-based provider.

### I-5 (Info): the fallback ownership check passes on a refunded predecessor order

`PlayOrderLookup.ByChainAsync` passes on a predecessor token's `latestSuccessfulOrderId` even if that older order was refunded. It
does require the head token to be active. This is acceptable for proving the claimant has the receipt, but note it for T-186.

## Summary for the Lead

- Must fix before merge: M-1 (sweeper head-of-line blocking) and L-1 (null-expiry subscription treated as active).
- Follow-ups: M-2 (budget per attempt and per replica, ack reserve, verify per-install limit; blocks go-live with PO question 4),
  L-2 (owner T-185), L-3 and L-4 (owner T-133), I-1 to I-5.
- Re-review: delta only.
