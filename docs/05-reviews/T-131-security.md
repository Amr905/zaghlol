# T-131 security and privacy review (App Store verification: JWS chain, App Store Server API, appAccountToken)

Reviewer: security-privacy-reviewer (Opus). Branch `origin/task/T-131-appstore-verify` @ d9bef12, diff against `origin/main` (EF
Designer files skipped). Inputs: `docs/04-tasks/tasks/T-131.md` design note, `security-model.md` billing parts, CLAUDE.md
non-negotiable 2a. I read all the non-Designer source and the main tests. Locally (.NET 10 SDK) I ran the Docker-free suites:
`Zaghlol.Infrastructure.Tests` filtered to `AppleJwsVerifierTests`, `AppStoreConfigurationTests`, `AppStoreClientTests` and
`AppStoreSentinelTests` (50 passed), and `Zaghlol.Application.Tests` filtered to `AppStore` (76 passed). I did not run the
Testcontainers suites (`AppStorePurchaseWriterTests`, `PurchaseVerifyIosEndpointTests`, `VerifyLiveContractTests`); those run on
the PC runner. I also checked the embedded root file: subject `CN=Apple Root CA - G3`, valid 2014-04-30 to 2039-04-30, SHA-256
`63:34:3A:BF:…:3E:91:79`, which equals `AppleRootCertificate.Sha256Fingerprint`.

## Verdict: APPROVED

There are no Critical or High findings. Nothing in this diff lets anyone get Gold they didn't pay for, and no financial data,
identifier, JWS or credential reaches a log, span, metric or exception.

- **M-1** is Medium, but it is a **go-live gate**, not a merge blocker. The code does what the design asks: Production refuses to
  start unless `AllowSandbox` is set explicitly. The open risk is PO question 4, and there is no alert yet.
- The Low and Info items are follow-ups. None is marked "before merge".

## What I checked and found sound

- **JWS shape and parsing** (`AppleJwsVerifier.cs`):
  - The length cap (16 384) runs before any decode (l.139).
  - It requires exactly 3 segments, and base64url must be strict and canonical: alphabet check, no padding, and a re-encode equality
    check (l.319-337). The `x5c` entries use strict standard base64, capped at 4 KiB before and after decode (l.340-361).
  - Header and payload are parsed with `AllowDuplicateProperties = false` and `MaxDepth = 16`, and must be JSON objects (l.50, 299-316).
  - Payload DTOs are source-generated and declare only the fields we read.
- **Algorithm and key source:**
  - `alg` must be exactly `"ES256"`.
  - `jku`, `jwk`, `x5u`, `kid` and `crit` are refused (l.159-170).
  - The key comes only from `x5c[0]`, and it must be EC P-256 (l.213-217).
  - The signature must be exactly 64 bytes, P1363 only (l.220-224). DER signatures, `none`, HS256 and ES384 are covered by tests.
- **Chain (no network):**
  - `x5c[2]` must be byte-equal to the pinned root (constant time, l.231).
  - The chain is built with `CustomRootTrust`, and the pinned root is the only anchor. `ExtraStore` holds only `x5c[1]`.
    Revocation is `NoCheck`, `DisableCertificateDownloads = true`, and `VerificationTime` is pinned (l.236-244).
  - The built chain must have exactly 3 elements. Element 1 must be byte-equal to `x5c[1]`, so the builder can't swap in an
    intermediate from a system store. Element 2's SHA-256 must equal the pin (l.247-249).
  - Both Apple OIDs are required: `…6.11.1` on the leaf and `…6.2.1` on the intermediate (l.267-273).
  - The pinned root's fingerprint is checked against a constant when it loads, and `AppStoreStartupCheck` loads it in every
    environment. `TestRootCertificate` is refused outside Development and Testing, and Production also refuses a non-null
    `TestRoot` and any fake `IAppStoreServerApi` / `IAppleJwsVerifier`.
  - The tests include "self-made root with Apple's subject", "test PKI never passes the real root", and 2/4-certificate chains.
- **Expired or revoked intermediate (signing time versus now):**
  - `Api` JWSs are validated at `now`. `App` JWSs are validated at their own `signedDate`, which must not be later than now + 5 min.
  - So an app JWS signed under an intermediate that has since expired is accepted. That is intended, because of the 2023
    intermediate rollover.
  - This is safe because the app JWS only names the transaction. `SameTransaction` (`AppStoreVerification.cs` l.214-220) requires
    Apple's fresh `Get Transaction Info` copy, validated at `now`, to match its transaction ID, original transaction ID, bundle,
    product, type and environment. The binding, ownership type and state all come from the API copies (l.114-146).
  - Even a forged app JWS (an attacker holding a compromised and revoked Apple leaf key) can't give more than Apple's own fresh
    answer gives. The most it changes is 502 versus 422 in the `4040010` window, through a forged `signedDate`.
  - See I-2 for the remaining revocation note on API copies.
- **Gold only from Apple's fresh answers (2a):**
  - Nothing is written before step 6.
  - A state outside the table, a missing `expiresDate` or `gracePeriodExpiresDate` on an entitling row, a latest product not on
    the allow-list, an `ours.Count != 1`, any API JWS failure, and any contradiction between the API copies all give 502 with no write
    (`AppStoreStateMapping.cs` l.44-52; `AppStoreVerification.cs` l.142-146, 241-274).
  - Refund or revocation (status 5 or `revocationDate`) is checked before any entitling row.
  - Only explicit Apple codes are final: `4000006`, and `4040010` after the 10-minute window. Every other 4xx, 401/403, 429, 5xx,
    timeout and open circuit is 502, and our own budget is 503.
- **Environment routing:**
  - The client is chosen only by the signed `environment` (`AppStoreServerApiClient.cs` l.126). There is no fallback on
    `4040010` (tested).
  - `Xcode` and `LocalTesting` map to `Unknown` and give 422.
  - The API copy, the latest transaction and the renewal info must all carry the same environment.
- **Base-URL lock:**
  - Outside Development and Testing, both URLs must equal exactly `https://api.storekit.apple.com` and
    `https://api.storekit-sandbox.apple.com` (`AppStoreOptions.cs` l.225-241). That also refuses the legacy `*.itunes.apple.com`
    hosts.
  - The URLs must be https, with no query and no userinfo.
- **appAccountToken binding:**
  - The token is parsed with `Guid.TryParseExact(..,"D")` and its 16 big-endian bytes are compared in constant time
    (`StoreBindingRef.cs` l.60-72). Upper-case hex parses to the same bytes, so the case equivalence is safe: it compares the UUID
    value, not the text, and no other text form is accepted (the length must be 36, format `D`).
  - The binding is checked on Apple's copy. Absent, unparsable or different gives `PURCHASE_NOT_OWNED` with no row.
  - `inAppOwnershipType != PURCHASED` (family-shared or anything unknown) is also `NOT_OWNED` on `RequireCaller`.
  - Replay of another install's JWS is therefore refused. A same-install replay is idempotent, and `IsNewPayment` stays false.
- **App Store Connect key:**
  - The key must be PKCS#8 P-256, and it is loaded once into `ECDsa`.
  - Production refuses it when it comes from any `FileConfigurationProvider` (`AppStoreOptions.cs` l.154-160), and requires
    issuer, key ID and bundle.
  - The JWT is ES256/P1363 with `kid`, `typ: JWT`, `iss`, `iat`, `exp = iat + 20 min` (Apple's cap is 60), `aud
    appstoreconnect-v1` and `bid`. `bid` is required for In-App Purchase keys, so that assumption is correct.
  - The token is cached and re-minted 5 min before `exp`.
  - Configuration errors name the key, never the value.
- **No leaks:**
  - HTTP loggers are removed.
  - Request URLs carry a template. T-130's `RedactingActivityProcessor` drops `url.full` and `url.path` and renames the span to the
    template.
  - Error bodies are read only for the numeric `errorCode`.
  - Every exception is a `SafeException` with a constant message.
  - `AppStoreSentinelTests` pushes the transaction IDs, the order ID, the `appAccountToken`, the JWS, its payload and the bearer
    token through a success, a Polly retry, an error body that echoes them, 5xx exhaustion and a timeout, with every category at
    Verbose. None of them appears in logs, spans or exception text, and positive controls prove the calls happened.
  - Metric tags come from constant sets.
- **DoS:**
  - JWS and certificate caps apply before decode, and the chain is fixed at 3.
  - Responses are capped at 1 MiB (`MaxResponseContentBufferSize`, buffered read), and order lookup handles at most 50
    transactions.
  - A budget permit is taken for each HTTP attempt, inside the retry, and `AppleBudgetDeniedException` is never retried.
  - The budget is a separate Apple bucket with a 20 % notification reserve. Restore is denied first and capped at 30 %.
  - Verify is limited to 10 per install per hour.
- **Order lookup** (`AppStoreOrderLookup.cs`):
  - The format is checked after upper-casing, and a sandbox purchase gives `fail` with no call.
  - Status `1` gives `fail`, and any other non-zero status gives `unavailable`.
  - Every signed transaction is verified at `now`. A wrong bundle or a non-Production environment gives `unavailable` and is alerted.
  - `pass` needs a constant-time `originalTransactionId` match and no refunded match. Every API error gives `unavailable`.
  - The order ID is never stored, logged or traced (sentinel test).
- **Migration, least privilege:**
  - `last_payment_at` gets `app_rw` UPDATE on that column only. `worker_rw` and `ops_ro` get nothing (`GrantMatrix.cs` l.250-258).
  - Apple's product/plan re-plan uses columns that `app_rw` could already update. The Google `UpdateSql` still doesn't touch them.
  - No transaction ID is stored. `store_key` (the original transaction ID) remains, as T-130 had it.
- **Alerts:**
  - `ZaghlolAppleSignedAnswerInvalid` pages on any `source="api"` JWS failure or contradiction. App-side failures are not paged,
    which is correct because those are attacker noise.
  - `ZaghlolStoreAuthError` now covers `app_store` 401/403.
  - The `client_error` rate is alerted.

## Findings

### M-1 (Medium, go-live gate; owner PO question 4 + T-132): `AllowSandbox = true` in Production gives free Gold to every TestFlight tester, and nothing alerts on it

- **Where:** `AppStoreOptions.cs` l.120-127 (required, but `true` is the proposed value); `AppStoreVerification.cs` l.70-71; the
  sandbox rows are written as normal `active` purchases. `deployment.md` l.97 says "watch" the
  `zaghlol.purchase.environment{env="sandbox"}` counter, but `purchases.yaml` has no rule for it.
- **Leak path:** anyone who installs a TestFlight build (trivial with a public TestFlight link) buys Gold in the sandbox for free.
  Verify accepts the Sandbox JWS against the production backend, writes `environment = sandbox` and `state = active`, and T-132's
  grant gate then issues a normal signed Gold entitlement on that install. The same applies to anyone with sandbox tester
  credentials. The result is Gold not backed by money, against the intent of 2a. App Review does need sandbox, so `false` is not a
  free fix either.
- **Required before go-live (not before merge):**
  1. The PO answers question 4, including "no public TestFlight link".
  2. T-132 either refuses `IVerifyGrant` for `environment = sandbox` outside an allow-listed review window, or issues sandbox
     entitlements with a short `exp` (for example 24 h) and a `sandbox` claim the app shows as a test grant.
  3. Add an alert on `increase(zaghlol_purchase_environment_total{store="app_store", env="sandbox"}[1d])` above a small
     threshold, so sandbox volume beyond App Review is visible.

### L-1 (Low, follow-up; owner T-131 follow-up or T-181): a foreign but genuine JWS spends Apple budget before it is refused

- **Where:** `AppStoreVerification.cs` l.78-104 (limiter, then `Get Transaction Info`, then for subscriptions the status read)
  versus l.114-119 (the binding, checked only on the API copy).
- **Exploit:** one genuine Apple-signed transaction (the attacker's own, or a sandbox one while M-1's `AllowSandbox = true`) is
  replayed from many installs. Each verify costs up to 2 Apple calls, plus retries charged against the shared `verify` lane, and
  only then gives `PURCHASE_NOT_OWNED`. With 10 per install per hour, about N installs drain the per-replica bucket and
  legitimate iOS verifies get 503. How large N must be depends on how cheap install registration is (App Attest, T-181).
- **Required change:** the `appAccountToken` and `inAppOwnershipType` in the app JWS are Apple-signed and can't change for a
  transaction. On `RequireCaller`, also check the binding on the **app** copy before any Apple call: a mismatch gives 422
  `PURCHASE_NOT_OWNED` with no call. Keep the authoritative check on the API copy. Add a test that a foreign binding causes zero
  WireMock calls.

### L-2 (Low, follow-up; owner T-185, depends on PO question 5): restore (`BindingCheck.Skip`) skips the ownership-type check too

- **Where:** `AppStoreVerification.cs` l.114-120. With `Skip`, both the binding and `OwnershipType != Purchased` are skipped.
- **Path:** a family member restores a `FAMILY_SHARED` transaction. `RequireCaller` rejects it, but restore writes it as `active`
  and it can then be granted. If the PO answers question 5 with "Family Sharing gives no Gold", restore is a way around that
  answer.
- **Required change:** in T-185, apply the `inAppOwnershipType` rule on restore too (skip only the `appAccountToken` check, as the
  task text says: "skips only the `appAccountToken` check"), or record the PO's choice to allow it. Add a test.

### L-3 (Low, follow-up; owner T-132): binding is checked on the presented transaction, but the row's state and `obfuscated_install_ref` follow the latest

- **Where:** `AppStoreVerification.cs` l.114-139; `PurchaseWriter.cs` l.93 (`obfuscated_install_ref = COALESCE(@ref, …)`).
- **Path:** a user buys on install A, moves to install B (restore), and upgrades on B, so the new transaction's token is B. Install
  A can still verify its *old* transaction: the binding matches A, the state comes from the latest (active) transaction, and the
  update rewrites `obfuscated_install_ref` back to A. This is not free Gold, because it is the same Apple account and the same
  payment. But the stored ref flips between devices, and any later logic that reads `obfuscated_install_ref` as "the current owner
  install" would be wrong.
- **Required change:** the T-132 seat rule must count seats per purchase and must not treat `obfuscated_install_ref` as the seat
  owner. Optionally, write `obfuscated_install_ref` only when the presented transaction is the latest one. Add a test for the
  two-install scenario.

### I-1 (Info): the budget check is not atomic, and limits are per replica

`AppleCallBudget.TryAcquire` reads `CurrentAvailablePermits` and then acquires (l.41-74), so under concurrency the reserve can be
breached by a few permits. `AppleVerifyLimiter` is in memory per replica, so the effective per-install limit is 10 × replicas. Both
are acceptable for a soft budget. Note them in the go-live sizing (deployment.md).

### I-2 (Info, accepted risk): no revocation checking for API copies

API JWSs are validated at `now` with `RevocationMode = NoCheck`. Forging an API answer would need both TLS interception toward
`api.storekit.apple.com` and a compromised, unexpired Apple WWDR intermediate or leaf key. Rejecting OCSP (design note §2.6) is
reasonable. If Apple announces a revocation, the response is to ship a denylist of intermediate thumbprints. Record that in the
runbook next to the `ZaghlolAppleSignedAnswerInvalid` alert.

### I-3 (Info): a refunded lifetime purchase is always stored as `refunded`

`MapLifetime` (l.60-62) never gives `revoked`, while subscriptions tell the two apart by `revocationReason`. Neither state grants
Gold, so there is no security impact. It matters only for support reporting; align it when T-134 lands.

## Checks outside this task's code

- Test fixtures are synthetic: `AppleTestPki` signs at test time, and the recorded sandbox vector is a dynamic skip until the PO
  provides it. That vector must use a synthetic install ID.
- No new NuGet package (the in-house verifier), so no analytics or telemetry SDK was added.
