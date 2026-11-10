# T-136 — Security & privacy review

| Field | Value |
|-------|-------|
| Task | T-136 Operator auth (OIDC + MFA), roles, audit log, support lookup (C4) |
| Reviewer | security-privacy-reviewer (Opus) |
| Diff | `origin/main...origin/task/T-136-operator-auth` @ `7f8067c` |
| Date | 2026-11-10 |
| Verdict | **CHANGES_REQUESTED** (one Medium, marked before merge) |

Scope read: `backend/src/**` in the diff, `backend/deploy/db/seed-operator.sql`, the validator, endpoint and startup-check tests, and the T-136 design note. Local CI for the branch is PASS (build, format, test).

## Summary

The token validator matches the design note closely and fails closed on every defect I tried:
- Only RS256 and ES256 are allowed, checked before any key lookup (`OidcOperatorTokenValidator.cs:113-117`). `kid` is required (`:119`).
- Keys come only from the pinned JWKS. `KeyFits` checks the key type against `alg` (`:205-210`), which stops `none`, HS256 keyed with the public key, and RSA/EC confusion. `jku`, `x5u` and `jwk` in the header are never read.
- Issuer and audience use ordinal exact matching on top of the library's own checks (`:167-175`).
- `exp`, `iat` and `nbf` must be JSON integers taken from the signed payload. The 60 s skew, the `exp - iat <= 3600` limit and the "`iat` not in the future" rule are all checked (`:177-187`). `Problem()` caps `MaxLifetimeSeconds` at 3600, so config can't loosen the limit.
- `amr` is required. `sub` is the only identity key. Roles come only from the `operators` row (unknown roles are dropped and counted). The 30 s positive/negative cache is bounded at 1000 entries.
- Every refusal returns a single 401 body. Only a fixed reason word is logged, never the token.
- Discovery and the JWKS are HTTPS only, and the discovered `issuer` must equal the configured one. Fetches have a 10 s timeout and a 64 KiB cap. The JWKS is limited to 50 keys, and private (`d`) or non-`sig` keys are skipped.
- The startup check stops the host outside Development/Testing if `Enabled=false`, the settings are invalid, `TestIssuer` is on, or discovery/JWKS can't be fetched at boot.
- No bypass validator ships. `FakeOidcIssuer` lives under `tests/` only, and no `src` code honours `TestIssuer` beyond refusing it.

Audit and support lookup follow BR-SYNC-03 and the design note:
- `AuditEntry` is a closed hierarchy (private-protected constructor, sealed records).
- `EmailPseudonym` can only be built from a 32-byte MAC. The e-mail is HMAC'd with `KeyedHashKey.Audit` and appears only as a bound SQL parameter. The tests cover the log/span/DB-scan checks.
- Relations to other installs are computed as booleans in SQL, so no other install ID, token, order ID or transaction ID is selected.
- The audit insert runs in the same transaction as the write and throws on failure. The catalog and flag stores now use the shared writer inside their transactions.
- `seed-operator.sql` uses psql `:'var'` literal quoting (no injection), validates roles against the six known values, refuses an `@` in `sub`, and never re-enables a disabled operator.

New dependency: `Microsoft.IdentityModel.JsonWebTokens` 8.23.0 is the current listing on nuget.org. It is Microsoft's maintained library, has no telemetry egress, and is outside the known advisory ranges (CVE-2024-21319 affected < 7.1.2). It is acceptable.

## Findings

### S-1 (Medium, **before merge**): an unauthenticated client can block every JWKS refresh by aborting its own request

- **Where:** `OidcKeyCache.cs:103-111` sets `lastAttempt = now` *before* the fetch, and the fetch runs on the caller's token. `FindAsync` (`:50`, `:65`) passes the request token, which is `Context.RequestAborted` (`OperatorAuthentication.cs:126`). In `:115` the `catch` filter lets `OperationCanceledException` through when the caller's token is cancelled. So an aborted attempt still uses up the 5-minute window, and the keys stay as they were.
- **How it is exploited:** an anonymous client sends a bearer token with a made-up `kid` (no valid signature needed) and closes the TCP connection a few milliseconds later. This triggers the forced refresh, the abort cancels the discovery GET, and `lastAttempt` is now stamped. The client repeats about once a second; the pre-auth `/24` bucket allows that. Whenever the window reopens, the attacker's request is very likely the first one in, because operator traffic is sparse. The 24 h scheduled refresh goes through the same throttled `RefreshAsync`, so it is starved too. Effects:
  1. After an IdP key rotation, tokens signed with the new key are refused (operator lockout).
  2. After 7 days the last good keys expire and every operator is refused.
  3. Worst case: if the IdP removes a **compromised** signing key, the API keeps trusting it for up to 7 days instead of ≤ 24 h. A stolen IdP key then keeps working against `/admin/v1`, still subject to the `operators` row and `amr`.
- **Required change:**
  - Do the fetch on a token that is independent of the request, for example the host's `ApplicationStopping` linked with the 10 s IdP timeout. The caller can stop *waiting* for the result, but must not cancel the fetch.
  - Alternatively, stamp `lastAttempt` only when an attempt actually completes (success or IdP failure) and not when the caller cancels.
  - Add a test: an unknown-kid validation whose token is cancelled mid-fetch, followed by a rotated-key validation after the throttle window, must succeed.

### S-2 (Low, follow-up): `Profile=Google` passes the startup check, then silently refuses every operator

- **Where:** `OperatorAuthOptions.Problem()` and `OperatorAuthStartupCheck.cs`. Google ID tokens carry no `amr`, so the `mfa` rule at `OidcOperatorTokenValidator.cs:189-193` refuses all of them (and `nbf` is not guaranteed either).
- **Rating:** this is fail-closed, so it is not exploitable. But it is exactly the "silent reject-all" that design note §4 wants turned into a boot failure. It also creates pressure to weaken `AcceptedAmr` later. There is no Google value that proves MFA, so any value added to `AcceptedAmr` would be a downgrade.
- **Required change (with Q1):** outside Development/Testing, refuse `Profile=Google` at startup with a constant message until the PO decides the MFA-signal rule for Google. Record in T-137's runbook that `AcceptedAmr` may only list values that prove a second factor.

### S-3 (Low, follow-up): Entra's default access-token lifetime exceeds the 1 h limit

- **Where:** `OidcOperatorTokenValidator.cs:184` (`exp - iat > MaxLifetimeSeconds`), which `Problem()` caps at 3600.
- **Detail:** Entra assigns access tokens a random 60–90 minute lifetime by default, and 20–28 h for CAE-enabled organisations. Most Entra tokens would therefore be refused. This also fails closed, so it is correct security behaviour.
- **Required change (with Q1/R4-6 evidence):** if Entra is chosen, record a token-lifetime policy of ≤ 60 min (and CAE off for these clients) on the `zaghlol-ops`/admin-app registrations in T-136's evidence section. Also confirm the Entra token version in use actually carries `amr`. Do not raise `MaxLifetimeSeconds`.

### S-4 (Low, follow-up; gate for T-186): Advisory mode keeps `support_agent`/`support_lead` without proof of phishing-resistant MFA

- **Where:** `OidcOperatorTokenValidator.cs:75-84`; the default `PhishingResistantMode=Advisory`.
- **Detail:** the PO accepted this ("decide later"), and nothing in T-136 needs these roles: the lookup only needs `support_viewer`. But T-186's `seat:move`, `purchase:detach` and `purchase:unfreeze` change paid entitlements. An operator phished with a TOTP/push second factor would get those writes in Advisory mode.
- **Required change:** add an acceptance criterion to T-186: its write endpoints don't go live in production until either (a) `Enforced` is configured, or (b) the IdP conditional-access policy name and its export are recorded in T-136/T-137 (R4-6, R3-9).

### S-5 (Low, follow-up): operator provisioning and role changes leave no audit trail

- **Where:** `deploy/db/seed-operator.sql`. The `INSERT ... ON CONFLICT DO UPDATE SET roles` and the documented `UPDATE ... disabled_at` write nothing to `audit_log` or anywhere else.
- **How it can be abused:** anyone with `migrator` credentials can quietly grant themselves `support_lead`, act, and revoke it again. The only trace of the grant is the actions themselves.
- **Required change:** in T-137, have the seeder write an audit row (or a migrator-only `operator_grant` record), or enable pgaudit on `zaghlol.operators`. The runbook should require two-person review of `migrator` runs.

### S-6 (Info): ID tokens of the CLI/admin clients are accepted as API bearer tokens

- **Where:** `Audiences` is documented as the client IDs (`zaghlol-ops`, admin app), and `typ` is deliberately not checked. Any ID token issued to those clients is therefore a valid API credential. ID tokens tend to be handled more loosely by front-ends (stored in the browser, passed to other components).
- **Mitigations already in place:** `amr`, the ≤ 1 h lifetime and the `operators` row.
- **Suggestion:** when the IdP is chosen, prefer a dedicated API audience (access tokens). If ID tokens stay, keep the admin app's ID token out of browser storage.

### S-7 (Info): the lookup counter can't spot one operator enumerating

- **Where:** `SupportAdminEndpoints.cs:62` always tags `support_lookup_total` with `support_viewer`.
- **Detail:** the counter has no per-operator dimension, so the "enumeration alert" only sees the global rate. The per-operator lookup bucket (20/min, chained with the 10/min general bucket) and the `audit_log` rows still limit and record it.
- **Suggestion:** add an alert on `audit_log` lookups per operator per hour (log-based alert, T-137), or tag the counter with the operator's highest support role.

### S-8 (Info): `K_audit` and the install-hash pepper are not checked to be different keys

- **Where:** `KmsSettings.cs` (pre-existing, T-123). `Kms:HmacKeys:Audit` and `Kms:HmacKeys:InstallHashPepper` can point to the same `keyRef` without any error. Design note §6 requires them to be separate.
- **Suggestion:** refuse duplicate HMAC `keyRef`s at startup, the same way the signing-key ring already refuses duplicates.

## Checklist

| Check | Result |
|-------|--------|
| alg allow-list RS256/ES256; `none`/HS*/header keys refused | Pass |
| `kid` required; keys only from pinned JWKS; key type matches alg | Pass |
| exact `iss`/`aud`; discovered issuer equals configured | Pass |
| `exp`/`iat`/`nbf` required; 60 s skew; ≤ 1 h lifetime; `iat` not future | Pass |
| `amr` MFA required; `sub`-only identity; roles from DB only; 30 s revocation | Pass |
| JWKS HTTPS only; size/time/key-count caps; throttled forced refresh; last-good ≤ 7 d | **Fail (S-1)**: throttle can be consumed by aborted requests |
| Uniform 401; token never logged | Pass |
| Startup fail-closed outside Dev/Testing; TestIssuer refused; no bypass validator | Pass (S-2 gap for Google) |
| Audit writer: closed types, same transaction, failure fails the write | Pass |
| E-mail lookup audited only as HMAC(K_audit) pseudonym; not in logs/spans | Pass (S-8 key-separation hardening) |
| Lookup minimisation (no tokens, order/transaction IDs, other installs' IDs, nothing financial) | Pass |
| Lookup rate limit; no bulk endpoint | Pass (S-7) |
| `seed-operator.sql` injection-safe; can't re-enable disabled operators | Pass (S-5 audit gap) |
| New NuGet dependency | Pass |

## Verdict

**CHANGES_REQUESTED**: fix S-1 before merge (the re-review on Sonnet covers the `OidcKeyCache` delta and the new test only). S-2 to S-8 become follow-ups; S-4 is a go-live gate for T-186.

## Re-review (delta): `git diff 7f8067c 9467383`

Scope: `OidcKeyCache.cs`, `OperatorAuthOptions.cs`, `FakeOidcIssuer.cs` and the two test files. Reviewed on Sonnet. CI (backend-ci 42794656371) and the PC runner are reported green.

### S-1: resolved

- **Caller cancellation cannot cancel the fetch.** `RefreshAsync` starts the fetch with `Task.Run(..., CancellationToken.None)`. `RunRefreshAsync` uses `FetchCancellation()`, which links `ApplicationStopping`, the cache's own `disposed` token and a 10 s `IdpTimeout`. No request token reaches it. The caller only does `task.WaitAsync(cancellationToken)`, so an aborting client stops waiting and nothing else.
- **An aborted request cannot burn the window.** `lastAttempt` is now stamped by `MarkAttempt` only after a fetch finishes (success, or a real failure including the 10 s timeout). Shutdown is not recorded. The attacker's forced refresh now runs to completion and loads the real keys, so the repeated-abort attack in S-1 no longer starves the 24 h refresh or a key rotation.
- **Single-flight.** The in-flight check, the throttle check and the assignment of `inflight` all happen under `lock (sync)`. `MarkAttempt` runs inside the task before it completes, so there is no gap where a completed refresh has not yet stamped the window and a second one could start. Concurrent unknown-`kid` callers join the same task.
- **No new DoS found.**
  - Refresh storm: at most one fetch per 5-minute window, and only one at a time.
  - Unbounded wait: a joiner waits at most the 10 s fetch timeout, and its own token still ends the wait early. `RunRefreshAsync` never throws, so there are no unobserved task faults. If `disposed` is already disposed, the resulting exception is caught and logged.
  - Residual (Info, no action): while a slow IdP is being fetched, unknown-`kid` requests that arrive in that window wait up to 10 s. This happens at most once per 5 minutes, and the pre-auth rate buckets still apply.
  - `LoadAsync` (startup only) is not part of the single-flight, which is acceptable.
- **Tests.** The three new tests cover the cases requested in S-1: abort mid-refresh then rotation after the window, repeated aborts not starving the daily refresh, and concurrent unknown `kid`s sharing one refresh. I read them and the `FakeOidcIssuer` support code; I did not re-run them.

### S-2: done

`OperatorAuthOptions.Problem()` now returns a reason for `Profile=Google` before any other check, so the existing startup check fails the boot outside Dev/Testing. Fail-closed behaviour is unchanged and `AcceptedAmr` is not weakened. A startup test and an options unit test cover it.

### Verdict

**APPROVED** (security). S-3 to S-8 stay as follow-ups as before; S-4 remains a go-live gate for T-186.
