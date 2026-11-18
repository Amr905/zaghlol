# Backend hosting options (T-140 preparation, OQ-16 / BLK-04)

| | |
|---|---|
| Status | **Proposal for the product owner. Nothing is chosen, nothing is deployed.** |
| Date | 2026-11-18 |
| Feeds | ADR-015, `deployment.md` section 3, T-140 |
| Prepared artifacts | `backend/deploy/terraform/` (OpenTofu, GCP), `.github/workflows/backend-deploy.yml` (disabled), `.github/workflows/backend-iac-validate.yml` |

**Not legal advice. The PO must confirm every statement in section 5 with Egyptian counsel before choosing a region.**

Figures marked *(verified)* were read from the vendor's page during this research; *(estimate)* are my own arithmetic or recollection of list prices and must be re-checked in the vendor's calculator before the PO relies on them. Prices are USD per month, list price, before tax and committed-use discounts.

## 1. What the backend needs

From `deployment.md` section 3 and `backend-schema.md` section 5:

- 2+ stateless API replicas (about 0.5 vCPU / 512 MB each, scale to 6) and **one** worker (advisory-lock singletons).
- Managed PostgreSQL 17, zone-redundant HA, **PITR 14 days**, private networking only. Load: 500k installs, 100k daily syncs, about 5 req/s average and 50 req/s peak, database under 1 GB.
- **Key custody.** The backend signs entitlements and catalog payloads with ES256 keys, and keys three HMACs (`K_seat`, `K_audit`, the `install_hash` pepper). The provider must offer a KMS where the API identity can sign or MAC but never export, with **HMAC** support (`Kms:HmacKeys`) and ideally HSM protection.
- Object storage plus CDN, managed TLS, WAF, a secrets manager, OIDC-federated CI deploys.
- **Google Pub/Sub** for Play RTDN. This is provider-independent: the topic and push subscription live in a Google Cloud project and push over HTTPS (with an OIDC token) to any public endpoint (`/v1/notifications/google`), so every candidate below can receive RTDN. Hosting on GCP just keeps topic, Play API credential and KMS in one project.
- The Play Developer API credential should be workload identity (`CredentialSource=ApplicationDefault`), not a key file. This is native on GCP and possible from AWS and Azure through workload identity federation.

## 2. Candidates

| | **A. GCP europe-west3 (Frankfurt)** | **B. AWS eu-central-1 (Frankfurt)** | **C. Azure (UAE North or Germany West Central)** | **D. Budget: Hetzner (Falkenstein / Nuremberg)** |
|---|---|---|---|---|
| Containers | Cloud Run service (API), Cloud Run worker pool, Cloud Run job (migrations) | ECS Fargate (API, worker, migration task) | Container Apps | Docker on VMs |
| Managed PG 17 + HA + PITR | Cloud SQL. PG 17 is available. **PITR log retention is 1-7 days on Enterprise and 1-35 days on Enterprise Plus** *(verified)*, so the 14-day target needs Enterprise Plus | RDS / Aurora Multi-AZ, PITR up to 35 days *(estimate)* | Flexible Server zone-redundant, PITR up to 35 days *(estimate)* | **None.** Self-run PostgreSQL with Patroni or WAL-G to object storage |
| KMS with HMAC + non-exportable signing | Cloud KMS: `EC_SIGN_P256_SHA256`, `HMAC_SHA256`, software or HSM, per-key IAM | KMS: `ECC_NIST_P256` sign, HMAC keys, per-key policy | **HMAC only in Managed HSM** (`deployment.md` section 3, T-140 follow-up). Managed HSM is billed per hour per pool | None. Keys would sit in a file or in an external vault, which weakens key custody |
| Pub/Sub reachability | Native (same project) | Push to ALB over HTTPS; a small GCP project is still needed | Same as AWS | Same as AWS |
| Latency to Egypt | About 60-80 ms *(ADR-015 design estimate, to be measured)* | Same city, same estimate | UAE North: Gulf, similar order; Germany West Central same as Frankfurt | Same as Frankfurt |
| Regional risk | Frankfurt is outside the 2026 Gulf damage | Frankfurt unaffected. AWS Gulf regions: Bahrain data is permanently lost and one UAE zone is lost (links below) | UAE North is a Gulf region: conflict exposure. Not researched in detail | Single-vendor, small ops team; CX/CAX plans showed "unavailable" in October 2026 and prices rose twice in 2026 *(verified, third-party report)* |
| Fit with this repo | Closest: secrets, KMS, Pub/Sub, Play API in one identity system; `ApplicationDefault` needs no key | Good; more glue for the Google-side pieces | Poor unless the Managed HSM cost is accepted | Cheap but cannot meet the key-custody and managed-HA requirements |

Gulf and Egypt notes:

- **Egypt hosting.** ADR-015 records that no hyperscaler has an Egypt region. A local provider would remove the cross-border permit (section 5) but I did not research any local provider's managed PostgreSQL, KMS or Pub/Sub reachability; treat it as an open option that needs its own research if counsel requires it.
- **AWS Gulf regions: do not use.** [The Register, 2 March 2026](https://www.theregister.com/2026/03/02/amazon_outages_middle_east/) and [Help Net Security, 17 September 2026](https://www.helpnetsecurity.com/2026/09/17/aws-middle-east-outage-permanent-data-loss-bahrain-uae/) report that me-south-1 (Bahrain) customer data and resources are permanently lost and that me-central-1 (UAE) lost one availability zone for good, with restoration "in the coming months".
- **GCP Doha (me-central1).** Cloud Run lists it as a Tier 2 region *(verified)*. I found a [report](https://rallies.ai/news/iran-warns-of-strikes-on-googles-middle-east-facilities-raising-cloud-risks) that Iran warned of strikes on Google's Middle East facilities and did not find a damage report; I would not put a payments-adjacent service there until the situation is clear.
- **Egypt's own connectivity is a single corridor.** [Kentik](https://kentik.com/blog/outage-in-egypt-impacted-aws-gcp-and-azure-interregional-connectivity) documented an outage in Egypt that degraded AWS, GCP and Azure interregional connectivity. Any region outside Egypt shares this risk; the app already works offline (NFR-BE-01), so it costs freshness, not function.

## 3. Monthly cost, expected load

Base topology, prod, list prices. Staging is about 40 % of prod.

| Item | A. GCP Frankfurt | B. AWS Frankfurt | C. Azure | D. Hetzner |
|---|---|---|---|---|
| PostgreSQL, 2 vCPU, HA | **$205** Enterprise at Iowa list *(verified rates: HA vCPU $60.30, HA memory $10.22 per GiB, SSD $0.34 per GiB; Frankfurt is higher, so plan about $230)*. Enterprise Plus for 14-day PITR: about $330-380 *(estimate)* | about $125 *(estimate)* | about $250 *(estimate)* | about 2 x EUR 19.49 for two CPX22 plus backups: EUR 55 *(CPX22 price verified, third-party)* |
| API (2 always-on, 1 vCPU / 512 Mi) | about $30 with request-based billing and idle min instances *(rates verified: $0.0000025 per idle vCPU-second; Frankfurt is Tier 2, so add 20-30 %)* | about $36 *(estimate)* | about $40 *(estimate)* | 1-2 x EUR 19.49 |
| Worker (1 always-on) | about $55 (instance-based, $0.000018 per vCPU-second plus memory) *(rates verified)* | about $18 *(estimate)* | about $20 *(estimate)* | EUR 19.49 |
| Load balancer + WAF | about $40-50 *(estimate)* | about $40 (ALB + WAF) *(estimate)* | about $40 *(estimate)* | EUR 7.49 LB11 *(verified)*, no WAF |
| KMS keys (2 signing, 3 HMAC, 1 envelope) | about $10 *(verified: $1.00 per HSM HMAC key version, about $2.50 per EC HSM key version)* + operations | about $6 + operations *(estimate)* | **Managed HSM pool: on the order of $2,000+ per month** *(estimate; check the calculator)* | not available |
| KMS operations | Every sync response is signed: about 3 M signatures a month. At $0.03 per 10,000 (software) this is $9; the HSM operation rate was not legible on the page *(verified, garbled)*, and at $0.15 per 10,000 it would be about $45. **Use a software-protected key for the high-volume Sync key if cost matters** | similar order *(estimate)* | included in the pool | n/a |
| Object storage + CDN, secrets, Pub/Sub, registry, logs | about $15-25 *(estimate)* | about $25 plus NAT about $35 *(estimate)* | about $25 | about EUR 10 |
| **Prod total** | **about $330-450 (Enterprise) / $430-560 (Enterprise Plus)** | **about $300-350** | **about $2,400-2,700** | **about EUR 110-130 + an external KMS** |

Reading the table: GCP and AWS land in the same band. Azure is ruled out by the HMAC-needs-Managed-HSM rule unless the PO accepts a software HMAC key. Hetzner is cheapest but cannot satisfy managed HA or key custody. The total is above the "low hundreds" in `deployment.md` section 4 mostly because of HA PostgreSQL; staging with a zonal instance is about $150-200.

## 4. Recommendation (for the PO to accept or reject)

**Option A: GCP `europe-west3` (Frankfurt), one project per environment.** Reasons:

1. Cloud KMS covers every key type in the design (ES256 signing, HMAC, envelope) with per-key IAM and no export, and HSM protection is a one-line switch.
2. RTDN, the Play Developer API (`ApplicationDefault`, no key file) and Play Integrity sit in the same identity system, so neither a service-account JSON key nor a cross-cloud federation is needed.
3. Cloud Run keeps operations small: one image, API as a service, worker as a worker pool, migrations as a job.
4. It follows ADR-015 (EU region, provider-neutral modules) and keeps option 2 (Egyptian hosting) open.

Runner-up: AWS `eu-central-1`, a little cheaper, more glue for the Google pieces. The modules are split so a second provider can be added beside `modules/` without touching the application.

**Decisions the PO must make before T-140 resumes**

1. Provider and region (A recommended).
2. PITR: pay for Enterprise Plus (14 days, as specified) or accept Enterprise (7 days) plus the daily logical dump for 30 days.
3. Sync signing key protection: HSM everywhere (default in the modules) or software for the high-volume key.
4. The data-protection route in section 5 (this gates the region).

**Gaps found while preparing (for the design note)**

- The cloud KMS adapter for `ISigningKeyProvider`, `IKeyedHasher` and `IEnvelopeCipher` does not exist yet (T-140 follow-up); `Kms:Provider=GcpKms` is a placeholder name. Nothing in app code was touched.
- `Signing:Keys:<n>:PublicJwk` must equal the KMS public key. Terraform outputs the pinned key-version references; deriving the JWK (x, y) from the PEM is a post-apply step still to be written.
- `Kms:HmacKeys:SeatCheck` cannot be computed by Terraform; `scripts/seat-check.sh` does it once and the result goes into `kseat_check_hex`.
- Cloud Run's request log contains the query string; the environment module excludes it from logging and the load balancer backends have logging off. The "sentinel query string" smoke test in the AC is still to be run in staging.
- `ForwardedHeaders` behind the Google load balancer: the default `KnownNetworks` are my best reading of Google's ranges and **must be verified in staging** from two client networks.
- A Cloud Run worker pool cannot run the exec heartbeat probe; liveness for the worker relies on platform restarts plus the existing alert rule.
- `google_cloud_run_v2_worker_pool` and `default_uri_disabled` need a recent provider (pinned `>= 6.40, < 8.0`). `tofu validate` could not run in my sandbox (provider registry blocked), so the new `backend-iac-validate` workflow is the first real validation.

## 5. Data protection: Egypt PDPL (Law 151 of 2020)

**Not legal advice; PO to confirm with counsel.** This is a reading of public translations and law-firm notes, not of the Arabic official text.

**What the backend holds.** No financial data. It does hold: a pseudonymous install ID, platform and app version, purchase tokens and store transaction IDs, an optional account (provider subject ID, optionally an e-mail), HMAC-pseudonymised hashes and opt-in merchant contributions (`backend-schema.md` section 1). The law defines personal data as data relating to an identified or identifiable natural person, directly or indirectly ([Law 151 of 2020, unofficial English text, Article 1](https://eg.andersen.com/wp-content/uploads/2026/02/Law-No.-151-of-2020.pdf)). An install ID that can be linked to a purchase and an optional e-mail should be assumed to be personal data until counsel says otherwise.

**What the law says** (article numbers per the Andersen unofficial translation; verify against the official gazette text):

- **Article 14:** personal data collected or prepared for processing may not be transferred to a foreign country unless the destination gives protection at least equal to the law's, and the Personal Data Protection Centre (PDPC) licenses or authorises the transfer.
- **Article 15:** without that level of protection, transfer may still be allowed on listed grounds, including the data subject's explicit consent, legal claims, international judicial cooperation and performance of a contract.
- **Article 26:** the PDPC issues licences or permits to controllers and processors; the executive regulations cap the fees. Processors must obtain a licence or permit (Article 5).
- **Article 42:** violating the transfer provisions (Articles 14, 15, 16) carries imprisonment of at least three months and/or a fine of EGP 500,000 to 5,000,000.

**Executive regulations and timing.**

- Decision 816 of 2025 was issued on 1 November 2025 with a one-year compliance period; [Baker McKenzie (7 October 2026)](https://www.bakermckenzie.com/en/insight/publications/2026/10/egypt-personal-data-protection-law-update) says it expires on **31 October 2026, so it has already ended** at the date of this note, and the PDPC now has an electronic portal for accreditation, licences and permits. See also [CMS](https://cms.law/en/are/legal-updates/egypt-s-pdpl-executive-regulations-issued-one-year-compliance-countdown-begins) (cited by ADR-015).
- The portal needs Digital Egypt authentication tied to an Egyptian National ID, so a foreign entity needs a duly authorised **local representative** to file (Baker McKenzie, same note).
- Per [Legal 500 (cross-border guide)](https://www.legal500.com/guides/hot-topic/strategic-challenges-and-opportunities-in-cross-border-data-transfers-under-egypts-personal-data-protection-regime): transfers are authorised by destination and are time- and purpose-limited (typically up to a year); the regulations take an adequacy-oriented approach and contemplate PDPC-approved standard contractual clauses and transfer impact assessments; a registered DPO is a prerequisite; the PDPC should decide within 90 working days of complete documents, and silence counts as rejection.

**What this means for the choice (my reading, for counsel to test).**

| Route | Effect |
|---|---|
| Hosted outside Egypt (EU region, recommendation) | Controller licence **plus** a cross-border permit for the transfer, with a destination-specific scope and renewal. The EU's protection level should help the adequacy argument but is not guaranteed. |
| Hosted in Egypt | No cross-border permit, but the licence still applies; narrower provider choice and more operations (no verified managed KMS/PG offer found). |

Questions for counsel: (1) whether pseudonymous install IDs and store purchase tokens are personal data here; (2) whether the Zaghlol entity is an Egyptian controller and who the local representative is; (3) whether data that never originates from a filing in Egypt (store-held purchase records fetched through Google and Apple APIs) counts as "collected in Egypt"; (4) permit duration, fees and the timeline against launch; (5) whether the explicit-consent ground (Article 15) is acceptable instead of, or while waiting for, the permit; (6) breach notification (`deployment.md` section 4 assumes 72 hours).

## 6. What was prepared (undeployed)

All of it lives under `backend/deploy/terraform/` (see its README):

- `modules/{network,database,kms,pubsub,app,edge,environment}` and `envs/{staging,prod}`: variables only, no secrets, `backend "gcs"` configured with `-backend-config` at init, no state credentials.
- KMS: per-key bindings only (never on the ring or project); HMAC and signing keys have `prevent_destroy` and no rotation period; no role that can export material.
- `scripts/seat-check.sh`, the Secret Manager shells (empty), Pub/Sub topic and push subscription as specified in `deployment.md` section 3.
- Dockerfile review: the multi-stage build, chiseled non-root runtime (UID 1654) and one-image/two-process layout fit Cloud Run as is; migrations run as `dotnet /app/worker/Zaghlol.Workers.dll --migrate` (a Cloud Run job). The image build was not run here (no Docker daemon in the sandbox); `backend-ci` builds it.
- `backend-deploy.yml`: `workflow_dispatch` only, `environment:` protection, Google OIDC, gated by the repository variable `BACKEND_DEPLOY_ENABLED` (unset means the job is skipped), apply is off by default, prod requires an image digest that staging already ran.

Validation status: `tofu fmt -check -recursive` passes locally (OpenTofu 1.10.6). `tofu validate` could not be run locally; it runs in `backend-iac-validate` on GitHub.
