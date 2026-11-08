# Review — T-138 Backend observability: OpenTelemetry, metrics, dashboards, alert rules (code review)

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer (Sonnet; C3) |
| Date | 2026-11-08 |
| Commit / diff | `origin/task/T-138-observability` @ 902498a vs `origin/main` (56 files). Design note 1c68de5. CI backend-ci run 42525861682: 6/6 green, including the promtool job. |
| Verdict | **CHANGES_REQUESTED** (1 major) |

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
