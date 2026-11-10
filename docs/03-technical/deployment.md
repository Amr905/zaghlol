# Deployment Considerations

## 1. Environments

| Env | App build | Backend | Stores | Data |
|---|---|---|---|---|
| `dev` | debug, flavor `dev` (bundle `app.zaghlol.dev`) | local Docker Compose (API + Postgres + fake price provider) or shared dev | Play internal app sharing; Xcode | Synthetic only |
| `staging` | release, flavor `staging` (`app.zaghlol.staging`) | `api.staging.zaghlol.app`; Play/App Store **sandbox** purchases; RTDN test topic; ASSN sandbox URL | Play internal testing; TestFlight internal | Synthetic test accounts |
| `prod` | release, flavor `prod` (`app.zaghlol`) | `api.zaghlol.app` | Play closed → staged production; TestFlight external → App Store phased release | Real |

**Android distribution flavors** (ADR-004):
- `prodSms` declares `READ_SMS`/`RECEIVE_SMS` and is the build submitted with the Play SMS declaration.
- `prodNoSms` omits the SMS permissions (notification + share/paste + manual + voice). It is ready to ship immediately if Play rejects or later revokes the exception (D-02, R-01).

Both builds share the same applicationId and code. A capability check hides the SMS UI in `prodNoSms`.

## 2. Mobile build & release pipeline (GitHub Actions)

```
PR:      dart format --set-exit-if-changed · flutter analyze · custom lints (no double money, no raw print)
         · unit tests (domain, parsing fixtures, registry_lint) · widget + golden tests (ar/en, light/dark)
         · Kotlin unit tests (Guard, Robolectric) · Swift unit tests (Guard) on macOS runner
main:    + integration tests on Android emulator (API 26, 34, 36) and iOS simulator (17, 26)
         + privacy_scan integration test + performance benchmarks (parse/scan/cold start) with budgets
tag vX:  build prodSms + prodNoSms AAB (signed via Play App Signing upload key from secrets)
         + iOS IPA (match/fastlane, App Store Connect API key) · upload symbols & mapping
         → Play internal track + TestFlight → manual promotion
```

**Store requirements** to track at each release:
- Play: target API 36 (Android 16) for updates after the extension window; Play Billing Library 8+ (bundled by `in_app_purchase_android` 0.5.x).
- Play: the Data safety form must match `security-model.md` §2.
- Apple: privacy nutrition labels, with **no** tracking and "data not linked to you" except purchase history for signed-in users.
- Apple: Sign in with Apple offered whenever Google sign-in is offered on iOS.
- Apple: account deletion in-app (FR-ACCT-04).

**Versioning:**
- App: semver `MAJOR.MINOR.PATCH+build`.
- `registryVersion` (SMS templates) and the bundled `catalogVersion` are recorded in the build and in About.

**Release cadence:** template updates ship in regular app releases (D-17). The target is a fortnightly release train, plus hotfix releases for parser regressions.

## 3. Backend hosting & infrastructure

**Region & provider (ADR-015, CR-03).** The design is **provider-neutral**: containers + managed PostgreSQL + KMS + object storage/CDN + a secrets manager. The recommended option, which needs product-owner and legal approval, is **a primary region in the EU (e.g. Frankfurt)**:
- **Why:** mature managed services, low latency to Egypt (≈ 60–80 ms), and an EU-level protection standard that suits the PDPL cross-border licence.
- **Gulf regions are not recommended for now:** two AWS Gulf regions have been offline since 2026 attacks.
- **The Egypt-hosted alternative** removes the cross-border permit but narrows provider choice. It stays open if the PDPC licence or legal advice requires local hosting.

**Topology:**
- API service: 2+ stateless replicas (0.5 vCPU / 512 MB each), autoscaling to 6.
- Worker service: 1 replica (singleton leases via PostgreSQL advisory locks).
- Managed PostgreSQL 17: 2 vCPU, zone-redundant HA, PITR 14 days, private networking only.
- KMS: ES256 signing keys, HMAC pepper (`install_hash`), a separate audit HMAC key (`K_audit`, support-lookup e-mails), a separate seat-key HMAC key (`K_seat`, D-55 `device_key_hash`), envelope keys.
- Object storage + CDN: catalog snapshots, the signed `.shortcut` file and store-review media.
- Managed TLS certificates; WAF/rate limiting at the edge.
- Google Cloud project for the Play Developer API service account and the Pub/Sub topic + push subscription to `/v1/notifications/google`.
- App Store Connect: production and sandbox notification URLs.

**KMS and key-ring configuration (T-123).** The API reads its key ring from configuration that the IaC (T-140) writes next to the KMS keys; there is no `signing_keys` table, so a database write can never change the signer.
- `Kms:Provider`: `Local` is allowed only in `Development`/`Testing` (throwaway keys from `backend/tools/dev-keys.sh`, read from `Kms:Local:KeyDirectory`); the cloud adapter arrives with T-140. Any other environment without an adapter refuses to start.
- `Signing:Keys:<n>:{Kid, Purpose (Sync|Entitlement), Status (Next|Active|Retired), KeyRef, PublicJwk:{Kty, Crv, X, Y}}`: exactly one `Active` key per purpose; kids match `^[se][0-9]{4}[a-z]$` (`s` = Sync: response headers and catalog `.sig`; `e` = Entitlement: JWS tokens); each key has its own KMS key. At startup every JWK must equal the KMS public key and each active key must pass a sign-then-verify probe, or the process exits non-zero and readiness never goes green.
- `Kms:HmacKeys:{Seat, Audit, InstallHashPepper}`: key references of the three HMAC keys (`IKeyedHasher`). On Azure only Managed HSM offers HMAC.
- `Kms:Envelope:KeyRef` (new envelopes) and `Kms:Envelope:PreviousKeyRefs:<n>` (older key-encryption keys that may still decrypt). Envelope format v1: `0x01 ‖ u8 len(keyRef) ‖ keyRef ‖ u16be len(wrappedDek) ‖ wrappedDek ‖ nonce(12) ‖ ciphertext ‖ tag(16)`, AES-256-GCM with a fresh data key per record and associated data `"zaghlol-env-v1" ‖ 0x00 ‖ context`.
- KMS calls time out after 2 s with one retry; a signing outage answers `503 UPSTREAM_UNAVAILABLE` with `Retry-After: 5`.
- Managed PostgreSQL: set `log_error_verbosity = terse` so a CHECK failure's DETAIL (row values) never reaches server logs, and never set `Include Error Detail` on a connection string (the API and migrator refuse it; FU-025).

**Forwarded headers and the client address (T-124).** The per-network rate limits (`RateLimits:*`) group clients by the /24 (IPv4) or /56 (IPv6) of the address that ASP.NET Core `ForwardedHeaders` resolves. `X-Forwarded-For` is trusted only from listed proxies; if none is listed behind a load balancer, every client looks like the load balancer and the whole service shares one bucket, so one client could block registration for everyone.
- `ForwardedHeaders:KnownProxies:<n>` (IP addresses) and/or `ForwardedHeaders:KnownNetworks:<n>` (CIDR, e.g. `10.0.0.0/16`): the addresses of the hop directly in front of the API.
- `ForwardedHeaders:NoProxy=true`: set this instead only when clients connect to the API directly (no load balancer, CDN or WAF in front).
- Outside `Development`/`Testing` the API **refuses to start** unless at least one proxy entry is listed or `NoProxy=true` is set (`ForwardedHeadersConfigurationException`).
- `ForwardLimit` is 1: the API takes the right-most `X-Forwarded-For` entry. The list must match the real hop count. With CDN → load balancer → API, list the load balancer and make it append the client address the CDN supplied (or raise the limit and list both hops); otherwise every client again shares the CDN's address.

**Price worker (T-127).** `Prices:Providers` is a comma-separated list of provider names in priority order (`fake`, later `local_gold`, `fx`, `spot_gold`). It is empty by default, so the worker fetches nothing and the sync `prices.stale` turns true after 24 h. `fake` is for development and staging only; the worker refuses to start with it in Production. `local_gold`, `fx` and `spot_gold` have no adapter yet (BLK-03, D-41): naming one stops startup. When the adapters exist, their credentials come from the secrets manager (environment variables `Prices__<Provider>__*`), never from a file. `Prices:IntervalMinutes` (default 60, minimum 1) sets the fetch period. The worker needs the `Worker` connection string; the API needs `App` and `Admin` (already required).

**Contribution aggregation (T-129).** The worker runs `ContributionAggregatorService` at start and every `Contributions:IntervalMinutes` (default 60, at least 1; not a secret). Each run, in one transaction on the worker login, deletes raw `merchant_contributions` rows older than 180 days, rolls the rest up into `contribution_aggregates` (`ready_for_review` at 5 distinct installs, A-48), and deletes the raw rows of promoted and rejected aggregates. It needs no new secret, grant or migration. Metric `zaghlol.contribution.events{event=ready|promoted|rejected|purged_decided|purged_expired}` (counts only); a failed run is logged by exception type only. Operators need the `catalog_editor` role for the queue and the two decisions.

**Daily sync (T-128).** `Sync:ThrottleWindow` (a `TimeSpan`, default `24:00:00`) is the server-side window between two effective syncs of one install; `Sync:MaxDeltaOps` (default 2000) is the largest catalog delta sent inline, above which the answer is `mode: full`. Both must be positive or the API refuses to start. Neither is a secret. The contribution `install_hash` uses the existing `Kms:HmacKeys:InstallHashPepper` key (HMAC of `"zaghlol-install-hash-v1" ‖ 0x00 ‖ installId`); a KMS outage drops that call's intake (the app resends) without failing the sync. The migration `AddInstallLastSyncAt` adds `installs.last_sync_at` (nullable, no backfill: `NULL` = never synced, so every install's next sync is allowed) and the `zaghlol.count_daily_active` function (EXECUTE for `app_rw` only); the migration `CountDailyActiveServerDay` replaces it with a two-argument form that uses the database's UTC date and accepts only `android` or `ios` (no data change).

**Ops channel for flag changes (T-126).** `OpsChannel:WebhookUrl` is an incoming-webhook URL (Slack, Google Chat or Teams; body `{"text": "..."}`) that receives one message per feature-flag change. The URL is a credential: set it from the secrets manager (environment variable `OpsChannel__WebhookUrl`), never in a file in the repository. It must be an absolute `https` URL or the API refuses to start (the value is not echoed). Unset, nothing is posted. A failed post is logged by exception type only and never fails the change, which is already committed and audited.

**Infrastructure as code:**
- OpenTofu modules per environment under `backend/deploy/`.
- Secrets are referenced, never stored.
- CI deploys with OIDC federation (no static cloud keys).

**Backend pipeline:**
```
PR:   dotnet build -warnaserror · format · unit + integration tests (Testcontainers Postgres) · OpenAPI contract tests
      · SCA + container scan
main: build image (distroless, non-root) → push → deploy staging → EF migration job → smoke tests (sync, verify sandbox)
tag:  promote the same image digest to prod → migration job (expand/contract, backward compatible) → rolling deploy
      → synthetic checks → automatic rollback on failed health
```

**Migrations:** expand → deploy → contract across two releases. Migrations must be compatible with the N-1 API version, because a rolling deploy runs mixed versions. A CHECK added to a table that already holds rows is validated against them: the FU-018 CHECKs on `merchant_contributions` and `bank_requests` (AddPriceFeedColumns) were added while both tables were empty. Since T-128 the sync writes them, so a later migration that tightens one of their CHECKs must first delete or migrate the rows that would fail it (or add the constraint `NOT VALID` and validate after the cleanup).

## 4. Operations

| Topic | Plan |
|---|---|
| Backups / DR | PITR 14 days; daily logical dump to separate storage (30 days). RPO ≤ 5 min, RTO ≤ 4 h. Restore drill each quarter. If the backend is down, **the app keeps working** (NFR-BE-01); only purchases verification, cross-platform Gold and freshness are delayed. |
| Key rotation | ES256 `kid` yearly (next key embedded in the app ≥ 1 release earlier); Play service-account key replaced by workload identity federation where possible; Apple API key yearly |
| Scaling | 500k installs / 100k daily syncs fits the base topology (backend-schema §5). Scaling triggers on CPU > 60% or p95 latency. |
| Cost (indicative, base topology) | Low hundreds of USD/month (API + worker + HA Postgres + CDN + KMS), to be confirmed for the chosen provider and region |
| Incident response | On-call rota (business hours + paging for SLO burn). Breach runbook with PDPC notification within 72 h. |
| Operator tooling (D-37) | v1: `zaghlol-ops` CLI against the admin API (OIDC authorization code + PKCE with a loopback redirect, MFA; the device-code grant is disabled for its client, R3-9). Later: an admin web app reusing the same API. Operator auth settings (T-136): `OperatorAuth:Enabled=true`, `Profile` (`Entra`, `Google` or `Generic`), `Issuer` (https, exact `iss`), `Audiences:0..n` (the `zaghlol-ops` and admin-app client IDs), optional `Algorithms` (subset of RS256/ES256), `AcceptedAmr` (default `mfa`), `PhishingResistantMode` (`Advisory` default, `Enforced` with `RequiredAcrs` = the Entra authentication-context ID), `ClockSkewSeconds` 60, `MaxLifetimeSeconds` 3600, `JwksRefreshHours` 24, `OperatorCacheSeconds` 30. Public values only; outside Development/Testing the API refuses to start unless these are complete and the IdP's discovery document and JWKS load at boot. The e-mail pseudonym key `K_audit` is `Kms:HmacKeys:Audit`. Operators are provisioned by `backend/deploy/db/seed-operator.sql` run as `migrator`. |
| Compliance | PDPC licence (+ cross-border permit if abroad), DPO, records of processing, store privacy forms, Play SMS declaration with demo video |

## 5. Launch checklist (architecture items)

- [ ] Play SMS-permission declaration submitted; `prodNoSms` ready.
- [ ] Signed `Zaghlol.shortcut` published; setup checker verified on iOS 17 and iOS 26.
- [ ] ES256 production keys created in KMS; public keys embedded (JWKS from `EcPublicJwk.ToJwks`); key-rotation test passed; `log_error_verbosity = terse` on the managed PostgreSQL.
- [ ] `ForwardedHeaders:KnownProxies`/`KnownNetworks` set to the load balancer in front of the API (or `ForwardedHeaders:NoProxy=true` if there is none), matching the real hop count; the per-network limit checked from two client networks in staging.
- [ ] RTDN + ASSN V2 configured for prod and sandbox; reconciliation jobs green.
- [ ] Price provider contract signed (OQ-02); stale alerts tested.
- [ ] Hosting region approved and PDPL licensing done (CR-03).
- [ ] Privacy scan + data-boundary contract tests green on the release candidate.
