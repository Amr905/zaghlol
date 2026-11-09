# T-124 Security & privacy review

| Field | Value |
|-------|-------|
| Task | T-124 Install registration, install-token auth, rate limits, idempotency store, strict DTOs (C4) |
| Reviewer | security-privacy-reviewer |
| Date | 2026-11-09 |
| Diff | `origin/main...origin/task/T-124-install-auth` @ `65bbbef` (EF `*.Designer.cs` skipped) |
| Inputs | `docs/04-tasks/tasks/T-124.md` incl. design note (2ebbe2a), `backend-api.md` §1/§3/§4.1, SRS BR-SYNC-03, CI backend-ci run 42688793294 (green) |
| Verdict | **CHANGES_REQUESTED** (one Medium finding marked before merge) |

## Summary

The BR-SYNC-03 boundary, the credential design and the R3-6 / R2-8 logic are sound and well tested. Registration accepts exactly `installId`, `platform`, `appVersion` and the `Idempotency-Key` header, and stores only hashes. Unknown, duplicate and wrong-case members are rejected. Problem bodies never echo input. The token has 256 bits from `RandomNumberGenerator` and only `SHA-256` of it is stored. Auth is one indexed lookup with uniform 401s. Registration replay and first-use clearing are each a single conditional UPDATE, so they race safely. Idempotency records are keyed per install and bound to the body hash, and they are envelope-encrypted with an install/operation context. Only final statuses are stored. Delete tombstones the install and removes its idempotency rows in one transaction. `/v1` code can only reach the `app_rw` login, whose grants on `installs` (SIU) and `idempotency_records` (SID) are the minimum these stores need.

One finding blocks the merge: the forwarded-headers rule fails open when no proxy is configured (S-1).

## Findings

### S-1 — Medium — **before merge** — Rate-limit partitioning fails open when `ForwardedHeaders` is not configured

- **Where:** `backend/src/Zaghlol.Api/RateLimiting/ZaghlolRateLimits.cs:180-191` (clears `KnownProxies`/`KnownIPNetworks`, then adds only what config lists) and lines 82, 86 (partition = `ClientNetwork.Of(context.Connection.RemoteIpAddress)`). The repo has no `appsettings*.json` for `Zaghlol.Api`, and nothing checks the setting at startup.
- **Exploit path:** production runs behind a WAF / load balancer / CDN (`error-handling-and-observability.md` §3, lines 71/76). If a deploy omits `ForwardedHeaders:KnownProxies|KnownNetworks`, ASP.NET Core ignores `X-Forwarded-For`, which is correct for spoofing. But `RemoteIpAddress` is then the proxy's address for every client, so all users worldwide share one /24 partition. One client sending 61 `POST /v1/installs` an hour blocks registration for every new install (the `Register` bucket allows 60/h). 601 requests a minute block the whole API (`PerNetwork`), including auth-failure floods that cost nothing to send. The failure is silent: nothing logs or alerts on it.
- **Required change:** outside `Development`/`Testing`, refuse to start when both `KnownProxies` and `KnownNetworks` are empty, unless an explicit `ForwardedHeaders:DirectClients=true` (or similarly named) flag says the API faces clients directly. Add a host test like `WithoutAKmsTheHostRefusesToStartOutsideDevelopmentAndTesting`. Also add a line to the hosting/deploy checklist: the configured list must match the real hop count, because `ForwardLimit = 1` takes the right-most XFF entry. With CDN → LB → API, the LB must be the trusted proxy and must append the CDN-supplied client address, or the limit must be raised and both hops listed.

### S-2 — Medium — before T-130 / T-135 adopt `WithIdempotency` (does not block T-124) — The idempotency session holds a pooled connection across the handler

- **Where:** `IdempotencyStore.cs:63` opens a transaction and `pg_try_advisory_xact_lock` on an `app_rw` pooled connection. `IdempotencyFilter.cs:65-94` keeps that session open while `next(context)` runs (line 84) and until `SaveAsync` (line 94).
- **Exploit path:** the real handlers (verifyPurchase, signIn) will open their own `IAppDbContextFactory` contexts from the same Npgsql pool, and they call Google/Apple APIs, which take seconds. With N = `Max Pool Size` concurrent idempotent requests, each holds one connection and waits for a second. The pool is exhausted until `Timeout` (default 15 s), and every `/v1` request fails with 503, including auth lookups. N concurrent requests are cheap: the per-token burst is 30, and installs are free to register (60/h per /24, more over many IPv6 /56s). Under ordinary peak load this is also an outage.
- **Required change (pick one, decide in the T-130 design note):** (a) run the handler's DB work on the session's connection and transaction (pass the context through), so each request uses one connection; (b) take the lock as an "in-progress" row (`INSERT ... ON CONFLICT DO NOTHING` with `status = 0`, committed immediately) and release the connection before the handler runs; or (c) give the advisory-lock connections a separate small pool with a short acquire timeout that answers `429 Retry-After: 1`. Add a test with `Max Pool Size` set low that fires `Max Pool Size + 1` concurrent idempotent calls whose handler opens a context.

### S-3 — Low — follow-up (T-128 / T-130) — Nothing stops a stored idempotent body from holding `rotateInstallToken`

- **Where:** `IdempotencyFilter.cs:90-95` stores whatever body the handler produced. `IInstallTokenRotator` (`InstallTokenRotator.cs`) is meant to be emitted in T-128+ responses.
- **Leak path:** a verifyPurchase or signIn 200 that carries `rotateInstallToken` would be stored, envelope-encrypted, for 24 h. That breaks the "raw token never stored" rule (design note, *Install credential*; R3-6 rationale). A replay cannot hand it out, because the old token is dead after rotation, but the secret still sits at rest and is exposed to anyone holding both the DB and the KMS decrypt grant.
- **Required change:** rotation is never emitted on an idempotent operation, or the filter refuses to store (throws in Testing, 500 in production) a response type that has a `Sensitive<T>` token member. Enforce it with a reflection/architecture test.

### S-4 — Low — follow-up — A request racing DELETE can leave an idempotency row for a tombstoned install

- **Where:** `InstallStore.cs:185-195` (delete transaction) vs `IdempotencyStore.cs:134-142` (insert).
- **Path:** request A authenticates, enters the filter and runs its handler. Meanwhile `DELETE /v1/installs/me` commits and removes the install's rows. Then A inserts its record. The FK is satisfied because the tombstone row still exists. The encrypted body stays until `expires_at` (at most 24 h), after the user asked for deletion.
- **Required change:** make the insert conditional, `INSERT ... SELECT ... WHERE EXISTS (SELECT 1 FROM installs WHERE id = @id AND deleted_at IS NULL)`, or take `SELECT ... FOR SHARE` on the install row in `TryBeginAsync`. Add a test that interleaves the two.

### S-5 — Low — follow-up — Log/metric capture does not cover the 429 paths

- **Where:** `RateLimitTests.cs` asserts only status and headers. `InstallAuthTests.AuthenticatedRequestsLogAnInstallHashButNeverTheTokenOrTheId` covers 201 (the registration happens inside it), 200 and 401.
- **Gap:** the design note's test plan asks for a log-capture test on the 201/401/429 paths and checks that metric tag values are constants (T-138 code #5). Nothing asserts that a 429 log line or the `zaghlol.rate_limit.rejected` tags never carry the network or the token-hash partition key. The code is correct today: the tag is the `bucket` constant, and partition keys stay in memory.
- **Required change:** add a 429 case to the log-capture test, and a `MeterListener` assertion that `bucket` ∈ {`network`, `token`, `idempotency`}.

### S-6 — Info — The envelope context does not bind the idempotency key

`IdempotencyFilter.cs:32` binds the install and operation, not the key. Someone with DB write access could swap `response_body_enc` between two records of the same install and operation, and a replay would decrypt it. The impact is negligible: same install, and the attacker already holds DB write. Optional hardening: append `SHA-256(key)` to the context.

### S-7 — Info — The tombstone keeps `token_hash`, `platform`, `app_version`, `first_seen_at`

None of these is financial data or a usable credential, because auth filters on `deleted_at IS NULL`. `worker_rw` holds DELETE on `installs` for the existing retention purge, so the row goes in the 30-day hard purge. No change needed.

## Implementer's deviations

| # | Deviation | Ruling | Reason |
|---|-----------|--------|--------|
| D1 | `201` of `POST /v1/installs` is not signed | **Accepted.** Fix the design note wording (Info). | `backend-api.md` §1 requires signatures only on 200s of the six anchoring operations, and §4.1 shows no "(signed)" for the 201. `ResponseSigningMiddleware.cs:67` signs only 200. The app never lets an unsigned body touch trusted time (§4.3), and the token's confidentiality comes from TLS. A forged 201 can only give the app a token that fails with 401, followed by silent re-registration. The design note's sentence "is signed by the existing response filter" should be corrected so T-128+ don't copy it. |
| D2 | Token hash = SHA-256 of the 43-char base64url text, not of the 32 raw bytes | **Accepted** | Unpadded base64url is a bijection on 32-byte inputs, so preimage resistance and collision behaviour are the same as hashing the bytes. `IsWellFormed` rejects non-canonical text before hashing (`InstallTokens.cs`), so there are no aliasing variants. |
| D3 | Transient `DbException` → `503` | **Accepted** | `GlobalExceptionHandler` logs the exception server-side only and returns a constant-title problem. Non-transient DB errors stay `500 INTERNAL`. Npgsql's `Include Error Detail` must stay off, so `PostgresException.Detail` (which could hold a `token_hash` value on a unique violation) is redacted in that log. It is already off; it is not enabled anywhere in `src/`. |
| D4 | `installHash=unavailable` when the pseudonymizer fails | **Accepted** | The value is a constant, `LogFieldPolicy` allows only Hex16 or that constant, the diag counter is untagged, the startup check fails closed outside Development/Testing, and the request is not degraded. |
| D5 | New metric `zaghlol.rate_limit.rejected` tagged by bucket name only | **Accepted** | Every call site passes a constant (`ZaghlolRateLimiters.NetworkBucket`/`TokenBucket`, `"idempotency"`). The test gap is S-5. |

## Checklist (focus areas)

| Area | Result |
|------|--------|
| BR-SYNC-03 accepted fields | Pass. `InstallRequest` has exactly 3 members, the strict policy covers unknown/duplicate/case/nested, `appVersion` is ASCII-gated before the regex, and the platform is a closed set. Nothing from headers is stored except key/body hashes. |
| Token entropy / storage / compare | Pass. 256-bit CSPRNG, hash-only storage, unique index, malformed tokens rejected with no DB hit, `FixedTimeEquals` on stored key and body hashes. |
| 401 uniformity | Pass. Missing, malformed, unknown, tombstoned and install-header mismatch all return the same body plus `WWW-Authenticate: Bearer`, and a test compares the bodies. The malformed `Zaghlol-Install` 400 shows up only after the token is valid, so it is not an oracle. |
| R3-6 replay window and race | Pass. Atomic conditional UPDATEs, 24 h window from the injected clock, tombstoned installs never reissued, the race test has exactly one winner, and no token is ever stored. |
| Idempotency isolation / body binding / envelope | Pass for T-124 scope (S-2, S-3 apply to adopters). |
| Logs / metrics / problem bodies | Pass. The token, ID, key and Idempotency-Key are never logged (test), `rotateInstallToken` is added to the deny list, problem bodies are constant, and `Sensitive<T>` is reflection-enforced. |
| Rate-limit bypass | XFF is read only via `ForwardedHeaders` with explicit proxies, `ForwardLimit=1`, and the forged-XFF test passes. **Fails open on missing config (S-1).** |
| DELETE tombstone + data removal | Pass (S-4 race is Low). |
| DB role least privilege (FU-021) | Pass. The generic factory is internal, `/v1` sees only `IAppDbContextFactory`, there is a Testcontainers `current_user` test, and the grants are minimal. |
| `EnableSensitiveDataLogging` ban, KMS exception mapping | Pass (tests present). |

## Required before APPROVED

1. **S-1:** fail-closed startup check for the forwarded-headers configuration outside Development/Testing, plus a test.

S-2 must be resolved in the T-130 design note before any production route uses `WithIdempotency`. S-3…S-5 are follow-ups for the Lead to file. S-6 and S-7 need no action.
