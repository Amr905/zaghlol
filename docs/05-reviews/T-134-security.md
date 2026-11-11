# T-134 security and privacy review (App Store Server Notifications V2 endpoint and reconciliation)

Reviewer: security-privacy-reviewer (Opus), 2026-11-11. Branch `origin/task/T-134-assn` @ 641f3fa, diff against
`origin/task/T-134-design-note` (EF Designer file skipped). Inputs: `docs/04-tasks/tasks/T-134.md` (design note, implementation
notes, deviations, provisional PO defaults), CLAUDE.md non-negotiables 1 and 2a, the T-131 security review (the verifier pipeline
reused here was reviewed there).

I read all the new and changed non-Designer source, the migration and its `Down`, the grant matrix, the alert rules, and the main
tests (endpoint forgeries and the sentinel test, store and grant tests). Evidence is GitHub `backend-ci` run 42984304721 on
`ci/T-134` @ 641f3fa:
- Api.Tests 446/446 passed. This includes `AppleNotificationEndpointTests`: 18 forgeries → 401 with zero rows and no Apple call,
  and the AC 3 sentinel scan of the DB, logs and activities.
- Application.Tests 703/703 and Workers.Tests 25/25 passed.
- Infrastructure.Tests 827 passed, 3 skipped, **1 failed**:
  `CheckConstraintTests.EveryCheckConstraintInTheSchemaHasANegativeCase` (expected 52, actual 54). The two new CHECKs are not in
  that inventory. This is not a security defect, but the merge gate is red (see I-5). `GrantTests`, `AppleNotificationStoreTests`
  and the `relacl`/`attacl` test all passed.

## Verdict: APPROVED

There are no Critical, High or Medium findings, and none is marked "before merge".

A forged, tampered or replayed request cannot write a row, cannot spend Apple budget and cannot change Gold. A genuine notification
can only start a re-read from Apple of a purchase that verify already created. The worker's login cannot move a seat or write the
binding and payment columns. No notification content beyond the extracted columns reaches the DB, a log, a span or a metric label.

The three Lows and the Infos are follow-ups. Separately from this verdict, the CI test failure (I-5) must be fixed before merge
under the normal gate.

## What I checked and found sound

- **Unauthenticated endpoint, order of checks**
  - Order in `AppleNotificationEndpoints.cs` / `AppleNotificationIngest.cs`: the global per-network rate limiter, then the 256 KB
    body cap (`Content-Length` and streamed), then `application/json`, then the envelope.
  - The envelope uses its own source-generated context: unknown members skipped, duplicates refused, case-sensitive, a single
    `string?` member, and `ToString` never renders the payload.
  - Then the outer JWS at most 65 536 chars, before any decode. Every later failure returns the same `401 UNAUTHORIZED` problem with
    no detail. The 400/401 split only reveals "envelope vs. signature", which an attacker already knows.
  - No DB read or write and no Apple call happens before the outer signature, claims, bundle, environment and both nested JWSs have
    passed.
- **Outer JWS** (`AppleJwsVerifier.Verify`, unchanged from T-131 apart from the per-call cap)
  - Only `alg = ES256`; `jku/jwk/x5u/kid/crit` are refused; exactly 3 `x5c` entries.
  - `x5c[2]` must byte-equal the pinned G3 root (constant time). The chain is built offline with the pinned root as the only
    anchor, element 1 must byte-equal `x5c[1]`, and both Apple OIDs and P-256 are required.
  - The signature must be 64-byte P1363. Header and payload use strict base64url and `MaxDepth = 16` with duplicates refused.
  - Validation time is the payload `signedDate`, bounded by `≤ now + 5 min` in the verifier and `≥ now − 10 d` in the ingest
    (l.124-129). The signature is still checked with the leaf key, so a backdated `signedDate` gains nothing without Apple's key.
- **Nested JWSs.** These are verified with the same pipeline (16 384 cap) and bound to the outer `data`:
  - transaction bundle = `data.bundleId` = configured bundle (an empty configured bundle accepts nothing);
  - transaction environment = `data.environment` (only `Production`/`Sandbox`; `Xcode`/missing → 401);
  - both transaction IDs match `^[0-9]{1,32}$`;
  - renewal `originalTransactionId` and environment, when present, are bound to the transaction and `data`.

  The outer signature covers the nested strings, so they can't be swapped independently.
- **Replay and dedupe.**
  - The ingest runs `ON CONFLICT (store, external_id) DO NOTHING` on the canonical lower-case UUID.
  - The acceptance window (10 d) is shorter than the retention (90 d), and a unit test asserts that invariant.
  - A replay at most triggers a fresh re-read: state can't be pushed backwards, because the write is Apple's current answer under
    the monotonic `last_verified_at < @read_at` guard.
- **Entitlement integrity**
  - The worker never inserts a purchase (`NO_PURCHASE`, no Apple call). It writes only Apple's API answer, verified at `now` and
    cross-checked for originalTransactionId, bundle and environment.
  - It writes only a catalog product of the same type: `ReadLifetimeAsync` requires `NonConsumable`, and `ReadSubscriptionAsync`
    requires `AutoRenewable`. A row can't change between lifetime and subscription.
  - An unknown mapping, contradiction or API JWS failure never writes.
  - A sandbox notification with `AllowSandbox` off → 200, not stored (l.160). For sandbox rows already stored, see L-1.
  - A product we don't sell → 200, not stored, alerted.
  - **REFUND_REVERSED auto-restore** gives nothing verify wouldn't: verify also writes Apple's current state. I agree with the
    provisional PO default 4.
  - The refund floor never grants; it only delays applying a non-refunded answer.
- **DB grants (migration `AppleNotifications`, `GrantMatrix.AppleNotifications`)**
  - The worker gains exactly `UPDATE (product_id, plan)` on `purchases` and `INSERT` on `store_notifications`.
  - It has no grant on `install_id`, `obfuscated_install_ref`, `environment`, `last_payment_at` or the account columns. It keeps only
    SELECT on `purchase_seats`, so "a notification never moves a seat" is enforced by the database.
  - `Down` revokes exactly those two grants. The renderer emits column-level `GRANT UPDATE (...)`, never a table-wide UPDATE.
  - CI's DB tests prove that T-131's `UpdateAppleSql` fails with 42501 on the worker login, and that the worker statement succeeds.
- **Forged traffic vs. cost**
  - Nothing unverified reaches the DB or Apple.
  - The worker calls Apple only for a UUID that passed full verification and maps to a known purchase, on its own budget partition.
    The API partition refuses lane `Notification` and the worker partition refuses every other lane, so app traffic and
    notifications can't drain each other.
  - The `Retry-After` handling no longer blocks a worker or a verify call for long.
- **Logs, metrics, spans, alerts, dead letter**
  - Worker logs carry counts and exception type names only.
  - Metric tags come from fixed sets: unknown types become `other`, and env is `production|sandbox|none`.
  - `last_error` holds constant codes only (DB CHECK).
  - The pagination token goes in the query string. The client span carries only the URL template, `RedactingActivityProcessor`
    strips `url.full/url.query`, and `RemoveAllLoggers()` is on the Apple clients.
  - Alert text names no identifiers.
  - Dead-lettered rows keep only the extracted columns. `transactionId`, `appAccountToken`, `status`, `bundleId` and the JWS text
    are never stored.
  - `Include Error Detail` stays refused (FU-025), so a CHECK failure can't put row values into a logged exception.
- **Reconciliation.**
  - History: `onlyFailures: true`, a 7-day window ending 5 min ago, at most 20 pages per environment, and a token-null loop guard.
  - Each entry goes through the same ingest (same verification, same dedupe). An entry failing verification is skipped and
    alerted.
  - Sandbox is queried only with `AllowSandbox`.
  - Response size is capped at 1 MB.
- **Config and fail-closed**
  - The worker now runs the T-131 startup validation of `Purchases:Apple:*`: it refuses to start outside Development/Testing
    without it. Production refuses a test root or test bundle, and requires an explicit `AllowSandbox`.
  - A `WorkerShare` outside (0, 1) stops startup.
  - No new secret. The App Store Connect key comes from the secrets manager (see I-3).
- **Data egress / privacy**
  - Nothing new leaves the server to Apple except the history request (dates and a flag).
  - `CONSUMPTION_REQUEST` is never answered, so no usage data is sent. I agree with provisional PO default 3.

## Findings

### L-1 (Low): the worker keeps refreshing sandbox purchases after `AllowSandbox` is turned off

- **Where.**
  - `AppleNotificationProcessor.cs` l.191 compares the row's environment with the purchase's environment only.
  - `AppleNotificationStore.cs` l.102-108 (`ExpiredSql`) has no environment filter. `AppleExpirySweepJob` (l.138 on) re-reads every
    row it selects.
  - Verify refuses sandbox when the flag is off (`AppStoreVerification.cs` l.73), and so does the ingest (l.160). `v_entitlements`
    has no environment filter.
- **Path.**
  1. With the provisional launch setting `AllowSandbox = true` (App Review / TestFlight, deployment.md l.97), a TestFlight tester
     gets a sandbox Gold subscription row.
  2. Ops later sets `AllowSandbox = false` to stop granting sandbox Gold.
  3. Queued sandbox `store_notifications` rows are still applied. The hourly sweep keeps re-reading the sandbox subscription and
     moving `expires_at` forward while sandbox auto-renew continues.

  So the worker extends Gold that verify would now refuse. The impact is bounded: sandbox renewals stop on their own, and only
  testers have sandbox accounts.
- **Required change (follow-up).**
  - When `environment = sandbox` and `!AllowSandbox`, the processor completes the row without an Apple call (a new code, e.g.
    `SANDBOX_DISABLED`).
  - The sweep excludes `environment = 'sandbox'`.
  - Add one test each.
  - Raise with T-132 whether entitlement issuance should also ignore sandbox rows when the flag is off.

### L-2 (Low): an unauthenticated request can force a full X.509 chain build, at a generous per-network rate

- **Where.** `ZaghlolRateLimits.cs` l.58 and l.115 (1 200/min per IPv4 /24 or IPv6 /56, in addition to the general 600/min);
  `AppleJwsVerifier.cs` l.232-280.
- **Path.**
  1. The attacker copies Apple's public leaf, intermediate and root from any StoreKit JWS (they are not secret) and attaches a junk
     signature.
  2. Each request decodes up to 64 KB, parses two JSON documents, loads two certificates, runs `X509Chain.Build` against the pinned
     root, then ECDSA-verifies, and only then fails with 401.
  3. IPv6 /56 partitions are cheap to obtain in bulk, so the per-partition limit doesn't bound the total.

  This is CPU-only: no DB write, no Apple call, no data exposure. It is still the most expensive unauthenticated operation the API
  has, and Apple's real delivery rate is orders of magnitude below 1 200/min.
- **Required change (follow-up). Any of:**
  - memoize successful chain validations in a small bounded cache keyed on `SHA-256(x5c[0] ‖ x5c[1])`, valid for the leaf's
    validity interval, so repeated genuine chains skip `Build`;
  - lower the default bucket (e.g. 120/min) and add a process-wide cap for this route;
  - optionally restrict the route at ingress to Apple's published notification source range (check Apple's current documentation
    before relying on it).

### L-3 (Low): an authentic notification for a product missing from the allow-list is acknowledged and lost

- **Where.** `AppleNotificationIngest.cs` l.211-215 (`IgnoredProduct` → 200, nothing stored);
  `AppleNotificationProcessor.cs` l.83 (`AppleStateRefresher`: an unknown stored product → `UNMAPPED`, so the sweep can't repair
  the row either).
- **Path.**
  1. An operator removes a product from `Purchases:Apple:Products` while purchases of it exist (a retired SKU, or a config typo
     in a deploy).
  2. Apple sends `REFUND` for a lifetime purchase of that product. We answer 200, so Apple doesn't retry, and `onlyFailures` history
     won't return it.
  3. The purchase stays `active`, and the user keeps Gold after a refund.

  The `ZaghlolAssnIgnoredProduct` page alert fires, but the event itself is gone and nothing records which purchase it was.
- **Required change (follow-up).**
  - Store the notification (processed, `last_error = 'UNKNOWN_PRODUCT'`) so the store key is kept for a human, or answer 5xx so that
    Apple retries for about 6 days while the config is fixed.
  - Add a deployment.md rule: a product is never removed from `Products` while purchases of it exist.

### I-1 (Info): validation at `signedDate` with `RevocationMode = NoCheck`

- If an Apple intermediate were compromised and revoked but not yet expired, signatures under it would keep verifying. A backdated
  `signedDate` (≥ now − 10 d) also extends the life of an intermediate that has just expired.
- The impact is bounded by the model: a forged notification can only trigger a re-read of an existing purchase from Apple's API,
  which is validated at `now`.
- This is the same accepted posture as T-131 (FU-077). Nothing to change; record it in `security-model.md` alongside the T-131
  entry.

### I-2 (Info): column-level worker grants are table-wide, not store-specific

- `UPDATE (product_id, plan)` on `purchases` also covers Google rows.
- `INSERT` on `store_notifications` lets the worker login enqueue rows for any store, which the T-133 RTDN processor will pick up.
- No code path does either, and both processors re-read state from the store, so an injected row can't grant anything.
- When T-133 lands, confirm that its processor, like this one, refuses rows the ingest would never produce
  (`AppleNotificationProcessor` l.168-173 is the model).

### I-3 (Info): the Workers process now holds the App Store Connect In-App Purchase key

- This is needed for the re-read. It widens the set of workloads that can read that secret.
- Confirm that the worker's secrets-manager identity has read access to that one secret only, and add the worker to the
  key-rotation runbook.

### I-4 (Info): provisional PO defaults 3 and 4

From a security and privacy standpoint I agree with both:
- ignore `CONSUMPTION_REQUEST`: no usage data leaves the server;
- Apple's current state wins on `REFUND_REVERSED`: no grant verify wouldn't make.

Both remain PO decisions.

### I-5 (Info, process): CI is red on one non-security test

- `CheckConstraintTests.EveryCheckConstraintInTheSchemaHasANegativeCase` expects 52 constraints and finds 54. The new
  `ck_store_notifications_type` and `ck_store_notifications_subtype` have no entry in that inventory.
- The CHECKs themselves are exercised in `AppleNotificationStoreTests`.
- This is not a security finding, but the task can't merge until backend-ci is green.
