# Error Handling, Logging & Monitoring

Constraint: the app ships **no analytics or crash SDKs** (NFR-PRIV-01). Raw SMS bodies, amounts, card digits, names, IPAs and phone numbers are never logged (NFR-SEC-03, CLAUDE.md §2.6).

## 1. App error-handling model

**Layers:**
- **Domain** functions are total. They return `Result<T, Failure>` (sealed) and never throw for expected cases. Examples: `ParseFailure.noTemplate`, `CurrencyMismatch`, `OffsetExceedsAmount`.
- **Data** wraps platform, DB and HTTP exceptions into typed `Failure`s at the boundary (`DbFailure`, `NetworkFailure{offline|timeout|server(code)}`, `PlatformFailure(code)`, `CryptoFailure`).
- **Application** decides recovery: retry, queue, review queue or user prompt.
- **Presentation** maps `Failure` → design-system patterns (design §5): inline message, banner, sheet or full-screen. It uses copy-deck keys, and the copy follows FR-L10N-04: no jokes on errors.

| Failure area | Behaviour | User sees |
|---|---|---|
| Parse fails / low confidence | Raw message kept; review item created; **never lost** (EC-08) | «مستني رأيك 👀» pill on Home |
| Guard config unreadable | Native falls back to the compiled-in registry senders; Dart re-writes config on next start | Nothing |
| Spool entry can't decrypt | Retry 3×, then quarantine + delete; diag code `SPOOL_DECRYPT_FAILED` | Settings → Capture shows "some messages couldn't be read — re-scan" (Android) |
| DB open fails (key invalidated) | Stop; don't create a new DB over the old file | Full-screen «مقدرناش نفتح بياناتك» + Restore from backup / Start fresh (keeps the old file until the user chooses) |
| DB write fails (disk full, EC-28) | Transaction rolled back; spool kept (entries retried later) | Banner «المساحة خلصت» |
| Migration fails | Restore the pre-migration copy (database-schema §4) | «التحديث ماكملش» + retry |
| Sync fails | Silent; back-off: next app open, at most 1/hour (BR-SYNC-02); after 7 days → Settings status line only (FR-SYNC-06) | Nothing on main screens |
| Signature invalid on sync | Drop the response, keep the current data, diag code, retry next day | Nothing |
| Purchase verify unreachable | `outbox(purchase_verify)` + WorkManager/BGTask retries (15 min → 6 h, until verified or 3 days pass, then keep retrying daily); Gold shown as "pending verification" (EC-44, BR-GOLD-06) | «بنتأكد من الدفع…» |
| Purchase invalid | No Gold; offer Restore & Support | Clear message |
| Restore attestation fails (`DEVICE_ATTESTATION_FAILED`) / can't attest (EC-66) | iOS: one retry with a fresh App Attest key; Android: one retry with a fresh token. Platform transient errors are retried 3× within 1 min. No restore call without a proof. Existing Gold untouched | Help message «مقدرناش نتأكد من الموبايل ده»; offer Sign in (account-linked Gold) and Support |
| Restore item `account_required` (EC-65) | No Gold on this install | «اعمل تسجيل دخول بالحساب اللي اشتريت بيه» (no account details revealed) |
| Entitlement `status: moved` | Gold off on this install | «الجولد اتنقل لموبايل تاني», with Restore / Sign in |
| Backup fails | Notification (FR-NTF-01) + Settings status; Gold schedule retries next window | «النسخة الاحتياطية ماتعملتش — جرب تاني» |
| Restore: newer backup (EC-26) / wrong passphrase / corrupt | Specific errors per design S-04 | As designed |
| Speech unavailable (EC-32) | Manual entry offered; online recognizer only with consent (ADR-010) | Explanation sheet |
| Unexpected exception | Caught by `FlutterError.onError` / `PlatformDispatcher.onError` → diag code + safe fallback screen with "Go home"; nothing sent anywhere | «حصلت مشكلة صغيرة» |

**Idempotency & recovery:**
- Ingestion is idempotent: body hash, cross-channel key, ack-after-commit.
- Catalog apply is atomic.
- Backups write to a temp name and rename after upload succeeds.
- Bulk edits are single transactions with undo.

## 2. Backend error handling

- **Problem Details** (RFC 9457) with stable `code`s (`backend-api.md` §6). A global exception handler maps unhandled errors to `500 INTERNAL` with a correlation ID; stack traces never reach clients.
- **Outbound resilience** (Polly):
  - Google Play and App Store APIs: timeout 5 s, 3 retries with jittered exponential back-off, circuit breaker. On open circuit → `503 STORE_UNAVAILABLE`, and the client keeps the purchase pending.
  - Price provider: timeout 10 s. On failure the last value is served with `stale: true` once older than 24 h.
- **Store notifications:** persist first, then ack (204/200) and process asynchronously. Processing failures retry up to 10 times, then go to a dead-letter status with an alert. A daily reconciliation job (Play `voidedpurchases.list`; App Store `Get Notification History`) fills gaps.
- **Google acknowledge deadline:** the sweeper retries unacknowledged purchases every 15 min, and alerts if any purchase is older than 48 h and still unacknowledged (refunds happen at 72 h).
- **Idempotency:** `Idempotency-Key` stored for 24 h; unique keys on purchases (`store, store_key`) and notifications (`store, external_id`).
- **Database:** EF Core transactions per command. Optimistic concurrency (`xmin`) on `purchases` to serialize notification and verify races.

## 3. Logging

### 3.1 App (local only)
- **`diag_log`** table, a ring buffer: 7 days or 2,000 rows. It stores `{at, level, code, fields}`, where `fields` comes from a typed allow-list: counts, durations, template IDs, institution codes, error codes, app/registry/catalog versions, HTTP status. No free-text strings.
- **Settings → About → «بيانات تشخيص»** lets the user view and **share** the diag log as a text file via the share sheet, for support. Leaving the phone is user-initiated (NFR-PRIV-02b). The shared text is regenerated from codes, so it can't contain message text.
- **Crashes:** only the stores' built-in reporting is used (Play Console Android vitals, Xcode Organizer / App Store Connect crash logs; SM-05). Release builds are obfuscated (`--obfuscate --split-debug-info`), with symbols kept in CI artifacts for symbolication. Exception messages from parsing/DB layers never include data, which is enforced by a `SafeException` base class and a lint rule.

### 3.2 Backend
- **Structured JSON logs** (Serilog → OpenTelemetry → provider log store), with fields `ts, level, msg, traceId, route, status, durationMs, installHash, code`.
  - Never logged: request or response bodies, tokens, ID tokens, purchase tokens (only `sha256[:8]`), Play Integrity tokens or decoded verdict payloads, App Attest assertions, attestation objects or key IDs, e-mails, or full IPs (truncated before ingestion). Attestation failures are logged as a reason code only (`hash_mismatch`, `stale`, `replayed`, `app_unrecognized`, `no_integrity`, `counter`, `key_unknown`, `chain`).
  - **Query strings are never logged** (FU-008). `route` is the matched route template (`/admin/v1/catalog/draft/{entity}/{id}`), never the raw path or the query. This applies to our request logging, OpenTelemetry HTTP spans (`url.query` and `url.full` are dropped, and `url.path` is replaced by the template), the reverse proxy / load balancer / CDN access logs we configure (query logging off), and exception messages. `Location` response headers are never logged, because the Apple callback's `Location` carries tokens. The API contract backs this up: no endpoint takes personal data or credentials in a query string (`backend-api.md` §1).
  - **Default and framework log sources:**
    - The `Microsoft.AspNetCore.Hosting.Diagnostics`, `Microsoft.AspNetCore.Server.Kestrel`, `Microsoft.AspNetCore.Routing` and `System.Net.Http.HttpClient` categories are set to `Warning` in every environment, or filtered by a Serilog enricher that drops `QueryString`, `Path`, `RequestUri` and `Uri` properties. At `Information` these categories log full request and outbound URLs.
    - `HttpLogging` / `UseHttpLogging` is off. If it is ever enabled, it must use an explicit allow-list (`Method`, `StatusCode`, `Duration`) with `RequestPath`, `RequestQuery`, headers and bodies excluded.
  - **Outbound calls:** Play v2 URLs carry the purchase token in the path (`…/purchases/productsv2/tokens/{token}`, `…/subscriptionsv2/tokens/{token}`), and App Store URLs carry transaction IDs. Outbound OpenTelemetry spans and logs use a redacted URL template (`…/tokens/{token}`, `…/transactions/{id}`) set by a `HttpClient` enrichment/filter. `url.full`, `url.query` and the raw path are dropped. Polly retry logs carry the template only.
  - **Edge:** the WAF / load balancer / CDN logs no query strings. Request-body logging or inspection-sample capture is disabled or redacted for `/v1/apple/*` and `/v1/notifications/*`, where bodies hold ID tokens, codes and signed payloads.
  - **Test (T-138):** a sentinel string is placed in the query, in a path key, in an outbound Play URL (through a fake Play handler) and in the Apple callback's `Location`. The test asserts that the sentinel appears in none of the captured logs, spans or HTTP-logging output, with all categories at their production levels.
  - Retention: 30 days (NFR-PRIV-06).
- **Audit log:** operator actions in the `audit_log` table, retained 3 years.
- **Tracing:** OpenTelemetry traces for API and workers, sampled at 10% in production (100% on errors).

## 4. Monitoring & alerting (backend)

| Signal | Metric | Alert |
|---|---|---|
| Availability | Synthetic check `GET /v1/health` + `POST /v1/sync` (test install) every 1 min from 2 regions | 3 consecutive failures → page |
| SLO 99.5% monthly (NFR-BE-02) | Successful `/v1/*` ratio, excluding 4xx | Burn-rate alerts (2% in 1 h, 5% in 6 h) |
| Latency | p95 `/v1/sync` < 300 ms, `/v1/purchases/verify` < 2 s | p95 over target for 15 min |
| Purchases | verify success/failure by `code`; unacked count; time-to-ack | Any unacked > 48 h; failure rate > 5% |
| Store notifications | ingest rate, processing lag, dead-letters | Lag > 15 min; any dead-letter |
| Prices | age of newest quote per symbol | Older than 6 h → warn; 24 h → page |
| Catalog | publish events; full-snapshot CDN 2xx | Snapshot 404 |
| Sync payload | response size histogram | p95 > 2 KB for up-to-date clients |
| Security | 401/403 rate, rate-limit hits, admin logins, flag changes | Spike alerts; every flag change posts to the ops channel |
| Capacity | CPU, memory, DB connections, DB storage | > 80% sustained |

Dashboards: one service overview, one purchases/entitlements view, one catalog & prices view.

## 5. Product health without analytics (OQ-01, ADR-021)

- **Backend aggregates only:** daily distinct active installs per platform and app version, derived from sync calls (`daily_active_counts`); purchases by plan; catalog version adoption; contribution volume.
- **Activation, retention and parse accuracy** (SM-01…04) come from store consoles (installs, uninstalls, retention cohorts on Play), opt-in in-app surveys (planned UX item), and the fixture-corpus parse accuracy measured in CI (SM-03).
- **No per-user event stream exists**, and none can be added without changing NFR-PRIV-01.
