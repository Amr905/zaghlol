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

**Migrations:** expand → deploy → contract across two releases. Migrations must be compatible with the N-1 API version, because a rolling deploy runs mixed versions.

## 4. Operations

| Topic | Plan |
|---|---|
| Backups / DR | PITR 14 days; daily logical dump to separate storage (30 days). RPO ≤ 5 min, RTO ≤ 4 h. Restore drill each quarter. If the backend is down, **the app keeps working** (NFR-BE-01); only purchases verification, cross-platform Gold and freshness are delayed. |
| Key rotation | ES256 `kid` yearly (next key embedded in the app ≥ 1 release earlier); Play service-account key replaced by workload identity federation where possible; Apple API key yearly |
| Scaling | 500k installs / 100k daily syncs fits the base topology (backend-schema §5). Scaling triggers on CPU > 60% or p95 latency. |
| Cost (indicative, base topology) | Low hundreds of USD/month (API + worker + HA Postgres + CDN + KMS), to be confirmed for the chosen provider and region |
| Incident response | On-call rota (business hours + paging for SLO burn). Breach runbook with PDPC notification within 72 h. |
| Operator tooling (D-37) | v1: `zaghlol-ops` CLI against the admin API (OIDC device flow + MFA). Later: an admin web app reusing the same API. |
| Compliance | PDPC licence (+ cross-border permit if abroad), DPO, records of processing, store privacy forms, Play SMS declaration with demo video |

## 5. Launch checklist (architecture items)

- [ ] Play SMS-permission declaration submitted; `prodNoSms` ready.
- [ ] Signed `Zaghlol.shortcut` published; setup checker verified on iOS 17 and iOS 26.
- [ ] ES256 production keys created in KMS; public keys embedded; key-rotation test passed.
- [ ] RTDN + ASSN V2 configured for prod and sandbox; reconciliation jobs green.
- [ ] Price provider contract signed (OQ-02); stale alerts tested.
- [ ] Hosting region approved and PDPL licensing done (CR-03).
- [ ] Privacy scan + data-boundary contract tests green on the release candidate.
