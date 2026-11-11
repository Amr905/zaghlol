# T-133 security and privacy review (Google RTDN push endpoint, processor, voided reconciliation)

Reviewer: security-privacy-reviewer (Opus), 2026-11-11. Branch `origin/task/T-133-rtdn` @ a074d37. The diff is against
`origin/task/T-133-design-note`; I skipped the EF Designer file. Inputs: `docs/04-tasks/tasks/T-133.md` (design note §0–§11,
implementation notes, deviations 1–10, provisional PO defaults), CLAUDE.md non-negotiables 1 and 2a, and the T-134 security review
(the shared inbox, advisory lock and processor pattern were reviewed there).

I read all the new and changed non-Designer source:
- `PubSubPushAuthentication`, `OidcKeyCache`/`OidcJwksCache` and `GoogleNotificationEndpoints`;
- `PlayNotificationIngest`, `PlayNotificationProcessor`, `PlayReconciliationJobs`, `PlayStateMapping.Settle`, `PlayNotificationStore`
  and `PlayDeveloperApiClient`;
- the `PurchaseWriter` and `PlayAckSweepStore` changes, the rate limiter, `PlayRtdnOptions`, the migration and its `Down`, the grant
  matrix and `GrantTests`, the alert rules, and the main auth and ingest tests.

Evidence:
- backend-ci 43017903978 on `ci/T-133` was green, as the implementation notes report. I did not re-check it.
- Locally (no Docker) I ran the Api tests matching `GoogleNotificationAuth|GoogleKeysUnavailable|GoogleEnvelope|OidcKeyCache|Operator`.
  138 passed. The 31 that failed all need PostgreSQL through Testcontainers: the operator and flag endpoint tests, which can't run
  in this workspace. No RTDN auth test failed.

## Verdict: APPROVED

There are no Critical or High findings, and none is marked "before merge".

**M-1 must be fixed before go-live.** It is a revenue leak (Gold kept), not a grant path or a privacy leak. It needs either a Play
API failure lasting at least about 30 h or a persistent failure on one row, and either case already pages through the dead-letter
alert. The Lows and Infos are follow-ups.

## What I checked and found sound

**Push authentication (`PubSubPushAuthentication.cs`)**
- **Auth before body:** the handler reads only `Request.Headers.Authorization` (l. 298) and never reads `Request.Body`. `IngestAsync`
  reads the body only after `RequireAuthorization(pubsub-push)` (l. 93, 104). The pipeline order is the per-network limiter →
  `UseAuthentication` → `UseAuthorization` (`ApiPipeline.cs` l. 75–77). The default InstallToken scheme returns `NoResult` without a
  DB lookup on endpoints that lack its metadata, so a forged push costs no database round trip.
- **Token checks, in order:** exactly one header of at most 4 096 characters, the `Bearer ` prefix, three segments in printable
  ASCII. Then `alg == RS256` (l. 96); the `kid` resolved only through `GoogleKeyCache`, which holds RSA keys only (l. 41–42, 113); and
  `ValidAlgorithms = [RS256]` with one fixed `IssuerSigningKey` (l. 118–133). Header keys (`jku`, `jwk`, `x5u`, `x5c`) are never used.
  The claims come from the signed payload with exact JSON types (l. 156–211):
  - `iss` is one of the two Google forms, compared ordinally;
  - `aud` is a single string equal to the configured audience (an array is refused);
  - `email` is an ordinal case-sensitive match;
  - `email_verified` must be the JSON value `true`;
  - `exp > now − 60 s`;
  - `iat` is required and `≤ now + 5 min`.
  
  `nbf` is not checked; Google's push tokens don't carry it.
- **Responses give no oracle:** every refusal is one generic `401 UNAUTHORIZED` with no detail. 503 comes only when no usable key set
  exists (l. 110, 316–321), which is the outage case, not a per-token signal.
- **Key cache:**
  - The discovered `issuer` must equal `https://accounts.google.com`, and `jwks_uri` must be https.
  - The 24 h refresh, the unknown-`kid` refresh (at most once per 5 min, shared) and the 7-day last-good window match the note.
  - Fetches run on their own token, so an aborting caller can't burn the throttle window.
  - Responses are size-capped with a 10 s timeout.
  - Keys unavailable → 503 + `Retry-After`, never accept.
  - Egress goes only to `accounts.google.com` and the discovered Google JWKS host.
- **Fail-closed config:**
  - `GoogleRtdnStartupCheck` stops Production without `Audience`/`PushServiceAccount`.
  - In other environments a missing value → `not_configured` → 401, never accept.
  - A malformed value stops every host (`PlayRtdnOptions`).
  - Error messages name the key, never the value.

**Separation from operator auth (T-136)**
- The two caches are separate singletons with separate HTTP clients. `GoogleKeyCache` has a fixed Google issuer; `OidcKeyCache` uses
  `OperatorAuth:Issuer`.
- The push validator uses only `GoogleKeyCache` and requires `aud` = the push URL and `email` = the push service account.
- The operator validator requires its own issuer, `ValidAudiences` and MFA.
- The push principal carries only `Name=pubsub` and no operator or install claim. Its scheme is never the default; only the RTDN
  route names it.
- So a Google push token can't satisfy an operator policy, and an operator token fails at least `iss` or `aud`/`email` here. There is
  no explicit test for this (I-3).

**Unauthenticated cost**
- Rate limit: `notifications-google`, 1 200/min per /24, in its own partition.
- A forged request costs at most one RSA verification and possibly a throttled JWKS refresh.
- It never makes a DB write, a Play call or a body read.

**Ingest and storage (`PlayNotificationIngest.cs`)**
- Every outcome after authentication is 204, except a DB failure (503).
- What is checked before decoding:
  - `messageId` matches `^[A-Za-z0-9_-]{1,100}$` with no `:`, so it can't collide with the `voided:`/`sweep:` keys;
  - `publishTime` is within the window;
  - `data` is at most 16 KB decoded.
- The DTOs have no catch-all member. Duplicate members are refused and names are case-sensitive.
- `type` comes from a fixed vocabulary; Google's raw values are never written. `product_id` is set only for catalog SKUs.
- Only the extracted columns plus the SHA-256 of `data` are stored.
- The request path makes no Play call.

**The payload is never the source of state (`PlayNotificationProcessor.cs`)**
- Step 0 refuses any shape the ingest never produces (l. 141–162), and the CHECK `ck_store_notifications_google_shape` backs this
  up.
- The worker never inserts a purchase.
- The kind comes from the stored `product_id`. Play's re-read must contain that product (`CONTRADICTION` otherwise), and the
  environment must match.
- Unknown state, 4xx/5xx and 410 write nothing.
- The write is guarded by `last_verified_at < @read_at` under `FOR UPDATE` (`PlayNotificationStore.cs` l. 32–40, 129–204).
- `PlayStateMapping.Settle` (l. 97–111) returns any non-`expired` read unchanged. The payload type only chooses between two
  non-entitling labels (`refunded`/`revoked` vs `expired`), so a forged or replayed `VOIDED_PURCHASE`/`REVOKED` can't grant or keep
  Gold.
- The refund floor holds an entitling read for 40 min and then applies Play's answer.
- `Settle` in `PurchaseWriter` and `PlayAckSweepStore` only stops an `expired` read from erasing a refund label. An entitling read
  still wins, so this is not a grant path.

**Duplicates, replay and order**
- Duplicates are handled by `ON CONFLICT (store, external_id) DO NOTHING`.
- Out-of-order and late messages converge on Play's answer through the monotonic guard.
- A replayed bearer (valid for up to 1 h, not bound to the body) can only enqueue re-reads of stored tokens. This is accepted in the
  design (§8); see L-2 for a narrow side effect.

**Worker DB rights**
- No grant changed (the `GrantMatrix` is untouched).
- The Google statement writes only `state`, `expires_at` and `last_verified_at`, with `store = 'google_play'` in its `WHERE`.
- `GrantTests` adds negatives showing that `worker` can't `UPDATE purchases.install_id` or `purchase_seats`. The existing negative for
  `INSERT INTO purchases` still holds.
- Seats and the binding and payment columns can't be touched.

**Voided job**
- `type=1`, a bounded window and `maxResults=1000`; at most 10 pages, so a looping `nextPageToken` stops; the page token is
  URL-escaped.
- The DTO reads exactly three fields plus the page token.
- `orderId` is validated and only stored as part of a SHA-256 key. Unknown tokens are never stored.
- It runs on the worker `Notification` lane, under the ack reserve.

**Logs, metrics, spans and alerts**
- Logs carry only counts and exception type names.
- Every metric tag comes from a fixed set (`outcome`, `kind`, `type` = lower-case vocabulary/`test`/`other`, `step`, `store`, `age`).
- The Play client uses URL templates (`VoidedListTemplate`).
- No tag, log or alert carries a token, `messageId`, `orderId`, subscription path, e-mail or JWT text. The alert-lint word rule is
  respected (deviation 10).
- Dead-letter rows hold only the constant `last_error`. `store_key` (the purchase token) sits in `store_notifications` as it already
  does in `purchases` (T-134 schema); this is not a new exposure.

**BR-SYNC-03**
- The endpoint receives only Google's notification; the app sends nothing new.
- `ReviewRefund` is never called, so no usage data about the user goes to Google (PO question 4 default; I support it).

## Findings

### M-1 (Medium, before go-live): a dead-lettered row is never redriven, so Gold can outlive the subscription or a refund

- `PlayNotificationStore.cs` l. 64–75 (`ExpiredSql`): any existing `sweep:<id>:<epoch>` row excludes the purchase from the sweep,
  whether that row is pending, done or dead-lettered.
- The voided job's insert is `ON CONFLICT DO NOTHING` (`PlayReconciliationJobs.cs` l. 129–145), and the 30-day window lies inside the
  90-day retention, so a void is enqueued only once.
- `PlayNotificationProcessor.cs` l. 288–295 dead-letters at 10 attempts (about 30 h).
- `v_entitlements` checks only `state` (`InitialCreateSql.cs` l. 12–15).
- Nothing in the codebase redrives a dead-lettered row, and `error-handling` §2 names no runbook.

**Leak path:**
1. Play Developer API calls fail for about 30 h or more. Causes: a revoked or rotated service-account key or IAM change
   (`STORE_AUTH`), a Play outage (`STORE_ERROR`), or a per-purchase persistent `NOT_FOUND`, `UNMAPPED` (a new Play state value) or
   `CONTRADICTION`.
2. During that time every RTDN row, sweep row and voided row of the affected purchases reaches attempt 10 and is dead-lettered.
3. After that:
   - A subscription that expired in that period stays `active`/`canceled_active`. Its sweep key exists, so it is never re-swept, and
     once `expires_at` is older than 7 days it also leaves the sweep window.
   - A lifetime purchase refunded in that period stays `active`. Its `voided:` key exists, so the daily job never enqueues it again.
4. Gold is then kept indefinitely. The only exception is a later verify or restore from the app, and a lapsed or refunding user has
   no reason to trigger one.

The dead-letter page tells ops that something failed, but there is no tool to put the row back. The design note states this
"dead-lettered not re-enqueued" choice to avoid head-of-line blocking (FU-098 code 3). The trade-off turns a recoverable outage into
a permanent entitlement error.

**Required change (follow-up, before go-live):**
- Let the expiry sweep re-enqueue a purchase whose sweep row for that expiry was dead-lettered at least 24 h ago. For example, add a
  generation suffix `sweep:<id>:<epoch>:<n>`, update the CHECK and `TryParseSweep`, and refuse it in step 0 when the suffix is not
  the next one.
- Let the voided job re-enqueue a void whose `voided:` row was dead-lettered (the same generation idea, or a `processed_at`/
  `last_error` check before the insert).
- Alternatively, add an operator redrive (`ops_rw`, audited) and a runbook entry; a runbook alone is weaker.
- Add tests:
  - a sweep row dead-lettered 25 h ago → the next sweep enqueues a new row → a Play `EXPIRED` read → `expired`;
  - the same for a voided lifetime purchase → `refunded`.

### L-1 (Low): anyone with a Google account can trigger the `ZaghlolRtdnAuthConfig` page

`purchases.yaml` l. 160–162 pages on more than 5 `bad_audience|bad_sender|keys_unavailable` per 15 min, sustained for 15 min.

**How:** any Google or GCP principal can mint a Google-signed OIDC token for any audience, for example
`gcloud auth print-identity-token --audiences=https://api.zaghlol.app/v1/notifications/google`. That token passes `alg`, `kid`, the
signature, `iss` and `aud`, and fails only at `email` → `bad_sender`. About one request every 2–3 minutes, from any network, well
under the rate limit, keeps the page firing.

**Effect:** on-call fatigue, and the attacker's noise hides a real configuration drift. It also confirms that the `email` check is the
only control separating our endpoint from every Google account. That check is correct and tested
(`EveryForged…(email_other, email_case)`).

**Required change (follow-up):** page only when genuine traffic has stopped, for example
`… > 5 and on() sum(increase(zaghlol_rtdn_auth_total{outcome="ok"}[1h])) == 0`, plus the existing `rtdn.recovered` warn. Keep the
raw count as a warn. `keys_unavailable` can keep paging alone: an outsider can't cause it.

### L-2 (Low): `messageId` dedupe ignores the digest, so a pre-claimed ID silently swallows a genuine message

The insert is `ON CONFLICT (store, external_id) DO NOTHING`, and the outcome is `duplicate` whatever the `payload_digest`.

**How:** a holder of a valid push token can insert rows under `messageId` values it chooses, each with any well-formed `data` (for
example `TEST`). This means a token replayed within its 1 h life (the bearer is not bound to the body), or anyone with `actAs`/
`TokenCreator` on the push service account (I-1). A later genuine Pub/Sub message with the same ID is then acknowledged as
`duplicate` and dropped.

**Effect:** limited. The re-read model and the sweeps fill most gaps, except as described in M-1.

**Required change (follow-up):** when the conflict row's `payload_digest` differs, count `outcome=duplicate_mismatch` (new fixed tag)
and warn. Do not store anything more.

### I-1 (Info): the push service account is the trust root

Whoever can mint tokens as `Rtdn:PushServiceAccount` can push. For PO question 2 / T-140 IaC:
- grant `roles/iam.serviceAccountTokenCreator` on `zaghlol-rtdn-push` only to the Pub/Sub service agent;
- give no human, CI or deploy principal `actAs` or `TokenCreator` on it;
- give it no roles of its own;
- alert on `GenerateIdToken` audit-log entries for it from any other principal.

The topic must allow `roles/pubsub.publisher` only for `google-play-developer-notifications@system.gserviceaccount.com`. This is
already listed in deployment.md; tick it in the T-140 checklist.

### I-2 (Info): no cap on token lifetime (`exp − iat`)

`CheckClaims` (l. 199–207) bounds `exp` from below and `iat` from above, but not the lifetime. The operator validator caps it. Google
push tokens live 1 h. A cap of `exp − iat ≤ 3 600 s + 60 s` would bound the replay window should a token with a longer lifetime ever
be signed. This is cheap; add it with a test.

### I-3 (Info): no test that the push and operator schemes reject each other's tokens

The separation is structural (see above), but a future change could break it silently: for example a default scheme change, or
`OperatorAuth:Issuer` set to `https://accounts.google.com` with the push URL in `Audiences`.

Add three things:
1. A valid push token on an operator endpoint → 401.
2. A valid MFA operator token on `/v1/notifications/google` → 401.
3. An `OperatorAuthStartupCheck` refusal when `OperatorAuth:Audiences` contains `Rtdn:Audience`.

### I-4 (Info): the per-/24 bucket is shared with other tenants of Google's push egress ranges

Pub/Sub push comes from Google-owned ranges that other GCP tenants' outbound traffic may share. A tenant on the same /24 can use up
the 1 200/min bucket with forged requests. The resulting 429s are nacks, which back off the whole subscription and delay genuine
RTDNs. Nothing is lost: retention is 7 days, and the sweeps cover gaps. The same applies to Apple's bucket.

Watch `zaghlol.ratelimit{bucket=network}` on this route after launch. If it bites, consider exempting authenticated-shape requests
from the per-/24 bucket while keeping a global cap. No change now.

## Answers to the brief's focus points

| Focus | Result |
|---|---|
| OIDC validation (issuer, audience, `email` + `email_verified`, `alg` pinning, `exp`/`iat` skew, `nbf`) | Sound. `nbf` is not sent by Google; I-2 for lifetime. |
| Key fetch, caching, rotation; keys unavailable → 503 | Sound. |
| Auth before body; no oracle | Sound. |
| Rate limiting and forged-traffic cost | No Play call, DB write or body read for forged traffic; L-1, I-4. |
| RTDN payload never trusted for entitlement state | Sound: only the non-entitling label. |
| Replay, duplicate, out-of-order (`messageId`) | Sound; L-2. |
| Worker DB rights (no new grants; no purchase insert, seat move or binding write) | Confirmed by code and `GrantTests`. |
| Refund/revoke can't grant or keep Gold | Can't grant; M-1 is a keep-Gold-on-outage path. |
| Voided job paging and token safety | Sound. |
| No PII, tokens, order IDs or e-mails in logs, labels, spans, alerts or dead-letter rows | Sound. |
| `OidcKeyCache` generalisation vs T-136 | Separated; I-3 for a test. |
| Config fail-closed in Production | Sound. |
| Outbound egress Google only | `accounts.google.com`, the discovered JWKS host, `androidpublisher`. |
