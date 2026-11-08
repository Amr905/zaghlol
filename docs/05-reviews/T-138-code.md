# Review — T-138 Backend observability: OpenTelemetry, metrics, dashboards, alert rules (code review)

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer (Sonnet; C3) |
| Date | 2026-11-08 |
| Commit / diff | `origin/task/T-138-observability` @ 902498a vs `origin/main` (56 files). Design note 1c68de5. CI backend-ci run 42525861682: 6/6 green, including the promtool job. |
| Verdict | **APPROVED** (after round 3; rounds 1 and 2 were CHANGES_REQUESTED) |

## Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Metrics visible in the local collector | PASS | `otel-collector` compose service (contrib 0.116.1), CI step "Metrics are visible in the local collector" waits for `zaghlol_service_up` and `http_server_request_duration_seconds_count` on `:8889` |
| Every alert exists as code; no install/account/token/transaction ID (lint) | PASS with finding 1 | 28 rules in `alerts/{slo,purchases,seats,platform}.yaml`; `AlertRuleLintTests` (names, forbidden words, metric names vs instruments); promtool job. The six `audit_alert` rules can miss the first firing of a series (finding 1) |
| Sentinel: query, path key, outbound Play URL, Apple `Location` in no log, span or HTTP-logging output at production levels | PASS | `SentinelTests` (Production-level and Verbose fixtures); final log bytes, `Describe(span)` incl. tags, baggage, events, links, status; metric tags; positive controls (`EveryPlacementRanAndWasLogged`, retry attempts == 2) |
| Extension: `seatKeys`, `ownershipCheck` order ID, `Zaghlol-Time-Nonce`, `Idempotency-Key`, exception output | PASS | scenario placements `body`, `body-throws`, `nonce`, `nonce-malformed`, `idempotency`, `throws`; `{@Body}` destructuring of `Sensitive<T>`. Reflection guard for DTO member names is missing (finding 3) |
| FU-002 field names match section 3.2 | PASS | `ZaghlolJsonFormatter` writes `ts, level, msg, traceId, route, status, durationMs, installHash, code`; golden tests in `ZaghlolJsonFormatterTests`; doc updated |
| DoD | PASS | analyze/format green in CI; no UI; no money types; no SMS |

### Named follow-ups
| Item | Result |
|------|--------|
| FU-002 | Done (formatter, doc section 3.2 edited) |
| FU-008 | Done: `RequestLogMiddleware` logs the route template only; `url.query`/`url.full`/`url.path` removed; `Location` never logged; no HTTP logging (test asserts absence); framework categories at Warning |
| T-123 code nit 9 | Done: `KmsMetrics.SignVerifyOperation`, `Signer.cs`, own alert `ZaghlolSigningVerifyFailed`, `SignVerifyMetricTests` |
| T-123 test gap G3 | Done: the nonce header is sent as the sentinel against the real filter and found nowhere |
| Monthly log key | Done: `KmsLogKeySource` (`IKeyedHasher.HmacSha256Async(InstallHashPepper, "zaghlol-log-v1" 0x00 yyyy-MM)`), cached per month in `LogPseudonymizer`; Production without a KMS fails closed. `AddZaghlolKms()` is in `Program.cs`, so the Api resolves it |

## Deviations from the design note (the implementer's list was not in the tree; judged from the code)
| Deviation | Ruling | Reason |
|-----------|--------|--------|
| `RequestLogMiddleware` in `Zaghlol.Api` (not Infrastructure) | Accepted | It needs `HttpContext`; Infrastructure stays free of ASP.NET. Formatter and policy remain shared in Infrastructure |
| Scope properties instead of template parameters | Accepted | Keeps `msg` a constant template, which the allow-list formatter needs; doc updated |
| `SafeException` in Domain; Kms exceptions derive from it | Accepted | Domain is pure; messages are constants. Public `(string message)` constructors exist, so the type is a convention (nit 5) |
| Metric `zaghlol.sync.response.size` (not `.bytes`) | Accepted | The `By` unit would otherwise map to `..._bytes_bytes`; rules and dashboards use the mapped name |
| Reuse of the existing `Zaghlol.Kms` meter | Accepted | Both meters are registered; no duplicated instruments; the rules match |
| Collector-side tail sampling; the app samples at `Telemetry:SampleRatio` (default 1) | Accepted | This is what the design note says in prose. `otel-collector.yaml` has the `status_code=ERROR` plus 10 % policy. Not testable in CI (listed) |
| OTLP exporters only when `OTEL_EXPORTER_OTLP_ENDPOINT` is set | Accepted | No export attempts in tests and dev; compose sets it |
| Npgsql span events | **Accepted with finding 2** | `Activity.Events` can't be edited, so the processor can't strip them, and the sentinel test does not prove they are safe |
| Loopback fake Play server instead of a fake primary handler | Accepted | A real Kestrel on `127.0.0.1:0` exercises the real HttpClient instrumentation and the 503-then-200 retry; test-only |
| Redactor: `url.path` always removed, then set to `http.route` on server spans | Accepted | Stricter than the note; also covers client spans |
| Remaining deviations (category regex, host group, DB span name, rule wording, `errorMessage` field) | Accepted | `errorMessage` is added to `AllFields` and the doc; only `SafeException` messages reach it |

Package pins verified in `backend/Directory.Packages.props`: OpenTelemetry.Extensions.Hosting and Exporter.OpenTelemetryProtocol 1.15.3, Exporter.InMemory 1.15.3 (test), Instrumentation.AspNetCore/Http/Runtime 1.12.0, collector-contrib 0.116.1, prom/prometheus v3.5.0. No temporary CI leftovers: `backend-ci.yml` gains only the `alert-rules` job and the collector smoke step.

## Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | **major** | `backend/src/Zaghlol.Infrastructure/Observability/ZaghlolMetrics.cs:42,50` (and `deploy/observability/alerts/seats.yaml:43-90`, `purchases.yaml:38`) | The "any occurrence" alerts (`dispute_frozen_refusal`, `support_unfreeze`, `seat_rebind_over_cap`, the operator rules, `ZaghlolNotificationDeadLetter`) use `increase(counter[10m]) > 0`. A labelled counter series does not exist until its first `Add`, and Prometheus `increase()` needs a prior sample, so the first firing of each series per process (each restart gives a new `service.instance.id`, hence a new series) is never seen. For rare events that is the case that matters: the first `support_unfreeze` goes unalerted | Create every known series at 0 when `ZaghlolMetrics` is built: `alertFired.Add(0, rule)` for the six rule names, `deadLetter.Add(0, store)` for the known stores, and the same for `moveCooldownRefused`/`attestationFailure` if the baseline alerts should see the first event. Add a `MeterListener` test that the series exist with value 0 before any call. Re-review: delta only |
| 2 | minor | `TelemetryServiceCollectionExtensions.cs:68`, `RedactingActivityProcessor.cs:18` | `AddSource("Npgsql")` brings Npgsql's own `exception` span event (`exception.message`, `exception.stacktrace` = `ex.ToString()`), which `RecordException=false` does not control and the processor can't remove. Today the text carries no row values only because `Include Error Detail` is rejected at startup (FU-025). The sentinel DB case passes for that reason, so the test does not prove the span path | Add a final-export guard that drops span events (wrap the exporter in a small `BaseExporter<Activity>` filter, or export through a copy), plus a test that sets a sentinel in an Npgsql exception event. Owner: T-138 follow-up, to be done before T-140 wires the real exporter |
| 3 | minor | design note, "Sensitive DTO members" | The reflection test over the API assembly (a DTO member named `orderId`, `seatKeys`, `purchaseToken`, `signedTransaction(s)`, `idToken`, `nonce`, `attestation`, `assertion`, `code`, `refreshToken` must be `Sensitive<...>`) is not in the diff | Add it (it passes trivially now). Owner: T-124, the first task that adds DTOs |
| 4 | minor | `alerts/seats.yaml:31-34`, `ZaghlolMetrics.cs:34` | `ZaghlolPlayIntegrityQuotaHigh` divides by `max(zaghlol_play_integrity_daily_quota)`; the gauge reports 0 until configured, so any call volume gives `+Inf > 0.5` and a false alert | Guard with `and max(zaghlol_play_integrity_daily_quota) > 0`, or do not emit the gauge while unset. Owner: T-138 follow-up |
| 5 | minor | `ZaghlolMetrics.cs:116`, `Domain/SafeException.cs` | Metric tag values accept any `[A-Za-z0-9_:.-]{1,40}` string, which includes a 40-character token. Callers pass constants today, so it holds by convention. `SafeException` subclasses likewise take a free `message` argument | Document both as "callers pass constants" in the owning tasks' review checklists; consider an analyzer later. Owner: T-124 / T-125 reviews |
| 6 | minor | `ZaghlolMetrics.cs` (histograms `sync.response.size`, `notification.processing_lag`) | The default OTel histogram buckets (...1000, 2500...) make the 2 KB p95 alert and the 900 s lag alert coarse (interpolated across a wide bucket) | Add `MetricStreamConfiguration` views with explicit boundaries (e.g. 256, 512, 1024, 2048, 4096 B). Owner: T-138 follow-up or T-140 |
| 7 | nit | `SignVerifyMetricTests.cs:35` | The comment points at `alerts/platform.yaml`; the rule is in `alerts/purchases.yaml` | Fix the comment |
| 8 | nit | `RequestLogMiddleware.cs` | A client abort is logged as status 500 when the failure is `OperationCanceledException` (`failed` flag forces 500) | Log 499-style `unmatched`-safe status or skip; optional |

## Checklist
- [x] `dotnet build` analyzers clean (CI green)
- [x] Tests added and passing in CI (not re-run locally)
- [x] RTL + LTR: n/a (backend)
- [x] No hard-coded user-facing strings
- [x] No `double` money, explicit currency (no money in this task)
- [x] No sensitive data in logs (allow-list formatter; sentinels pass; see findings 2 and 5 for residual risk)
- [x] Stays within the task's scope (the Kms edits are the named T-123 nit; `ApiTests` is updated for the new log shape)

## Notes for the Lead
- Only finding 1 triggers another round (delta re-review: `ZaghlolMetrics` and its test). Findings 2 to 8 become FUs with the owners in the table; finding 2 should be done before T-140.
- The security reviewer should look at finding 2 and the `Sensitive<T>` and `SafeException` conventions.
- Architecture conforms to `project-structure.md`: domain pure, the formatter and telemetry in Infrastructure, HTTP-specific code in Api, workers share the Infrastructure code.

## Round 2 (delta `902498a..c0288f4`, backend-ci 42527311523 green)

**Verdict: CHANGES_REQUESTED.** Major #1 is not shown to be fixed in production, only in the unit test. I could not run .NET here, so this is from reading the code and the registration order.

| Item | Result |
|------|--------|
| #1 (major) series absent until first event | **Open (re-raised, same severity).** The seeding itself is right (`ZaghlolMetrics.SeedSeries`: six `audit_alert.fired` rules and `dead_letter` for play and apple; `KmsMetrics.Seed()` for five operations). The problem is when it runs. A `Counter.Add(0)` made before a `MeterListener` exists is dropped. `ZaghlolMetrics` is constructed when the hosted services are resolved, and `MetricsStarter.StartAsync` calls `KmsMetrics.Seed()`. `MetricsStarter` is registered (`TelemetryServiceCollectionExtensions.cs:48`) before `services.AddOpenTelemetry()` (`:56`), so it starts before OpenTelemetry's own hosted service builds the `MeterProvider`. Every zero is then recorded with no listener and lost, and the first real `Add(1)` creates the series, which is the original bug. After a restart the new `service.instance.id` series behaves the same way. `AnyOccurrenceSeriesExistAtZeroBeforeAnyEvent` attaches its `MeterListener` before `new ZaghlolMetrics()`, so it does not model production. The CI smoke step only checks `zaghlol_service_up` (an observable gauge) and so does not catch it either |
| #4 quota guard | PASS (`... and max(zaghlol_play_integrity_daily_quota) > 0`; the promtool job is green) |
| #7 comment | PASS (`purchases.yaml`) |
| #8 client abort | PASS (`RequestAborted` plus status >= 500 logs 499, `ClientClosedRequest`). Nit: no test for it |
| #2 Npgsql events | Stays a follow-up as agreed (T-138 follow-up, before T-140) |
| `ExporterOrderTests` / `configureExporters` hook | Fine: the hook sits at the OTLP exporter's position, after the redactor, with a negative control |

### Required change for #1
1. Guarantee that the `MeterProvider` exists and is listening before anything is seeded. Simplest: `MetricsStarter(MeterProvider provider, ZaghlolMetrics metrics)` (resolving the provider first builds it with its `AddMeter` subscriptions), then seed in `StartAsync`. Remove the reliance on the constructor `Add(0)`, or keep it only as a second line.
2. Add a test through `AddZaghlolTelemetry` (the real DI path, as in `ExporterOrderTests`): start the hosted services, force a metric collect with an in-memory metric exporter (`OpenTelemetry.Exporter.InMemory`, already referenced) and assert zero-valued data points for `zaghlol.audit_alert.fired{rule=...}` (six), `zaghlol.notification.dead_letter{store=play|apple}` and `zaghlol.kms.unavailable{operation=...}` (five) before any event. Alternatively assert the same with a CI step that curls `:8889/metrics` for `zaghlol_audit_alert_fired_total{rule="support_unfreeze"} 0`.
3. Re-review: delta only.

## Round 3 (delta `c0288f4..4020b9e`, backend-ci 42528633775 green)

**Verdict: APPROVED.** Major #1 is fixed.

- `MetricsStarter(MeterProvider provider, ZaghlolMetrics metrics)` takes the provider first, so DI builds the `MeterProvider` and its `AddMeter` subscriptions before any seed. `StartAsync` then calls `metrics.SeedSeries()` and `KmsMetrics.Seed()`. The constructor seeding is gone. A new process (a restart) seeds its new series at 0 and exports them from the first collection, so the first real event is an increase from 0.
- `SeededSeriesTests` goes through `AddZaghlolTelemetry` and the hosted services with an in-memory metric exporter. It asserts zero data points for the six audit rules and the play and apple dead-letter stores. For the process-wide KMS counter it asserts existence only, which is right because a parallel test may have moved a series. It replaces the old listener-first test that did not model production. `SeedCreatesEveryOperationSeriesAtZero` covers `KmsMetrics.Seed()`.
- The compose smoke step now requires `zaghlol_audit_alert_fired_total{... rule="support_unfreeze" ...} 0` on the collector. The coordinator reports a mutation run (42528424746) in which seeding before the provider existed failed both the test and the smoke step; I did not re-run it.
- The `addOtlpExporter` seam replaces `configureExporters`. It still sits after the redactor and only when the endpoint is set, and `ExporterOrderTests` still has its negative control.

Remaining items are follow-ups only (no re-review): #2 Npgsql span events (before T-140), #3 DTO reflection test (T-124), #5, #6, and a test for the 499 path.
