# T-138 security and privacy review (backend observability)

Reviewer: security-privacy-reviewer. Branch `origin/task/T-138-observability` @ 902498a. CI backend-ci 42525861682 green.
Scope: logging, tracing, metrics, alert rules, dashboards, OTel collector, synthetics, pinned versions. I read the code, the
sentinel tests and the deploy files. I could not run the build or reach the NuGet and GitHub hosts from this sandbox (proxy 403), so the
Npgsql and OpenTelemetry advisory status is not independently re-checked.

## Verdict: APPROVED (no blocker or major). Seven Low and four Info items become follow-ups, none "before merge".

The design meets the egress promise for the fields in scope. Logs are an allow-list with per-field value shapes (`LogFieldPolicy.cs`
l.51-122), `msg` is the template and not the rendered text (`ZaghlolJsonFormatter.cs` l.34), exception text is written only for
`SafeException` (l.159-162), and spans pass through a tag allow-list (`SpanTagPolicy.cs`) before any exporter
(`TelemetryServiceCollectionExtensions.cs` l.83-88). The sentinel tests drive a unique secret through query, path, outbound URL
templates, Location, nonce, idempotency key, body, exceptions and a real Postgres unique violation, and assert it is in no log byte,
span name, tag, event, status description or metric tag (`SentinelTests.cs` l.61-104, `ObservabilityHostFixture.Describe`
includes events, baggage and links). That is a strong control.

## What I checked and found sound

- **Request log**: `RequestLogMiddleware.cs` logs method, route template (`RoutePattern.RawText`, or `unmatched`), status, duration,
  problem code, installHash. No path, query, header or IP. Replaces `UseSerilogRequestLogging`. Framework categories forced to Warning.
- **Allow-list**: unknown properties dropped; non-scalar values (so `{@Dto}`) written as `<invalid>`; `purchaseId` only on
  `audit_alert`. Order and shapes enforced. Good fail-closed default.
- **Spans**: `RedactingActivityProcessor` removes every non-allow-listed tag (url.full, url.query, http.url, db.connection_string,
  otel.status_description), nulls `url.path` and re-sets it to the route template for server spans only, renames spans from route or
  `url.template`, clears the status description, truncates tags. Outbound Play/Apple URLs carry the secret in the path; the template
  is supplied by the caller and defaults to `unknown` (`HttpRequestTelemetry.cs`), so there is no guessing from the real URL.
  `RecordException = false` on the HTTP instrumentation.
- **Sensitive<T>**: `ToString()` is `***`, no public property, so record/interpolation/Serilog destructuring show nothing. The JSON
  converter writes the bare value by design (needed to echo DTOs); it is not on any log path because the formatter drops non-scalar
  properties.
- **installHash**: HMAC-SHA256 under a monthly key = KMS-HMAC(InstallHashPepper, "zaghlol-log-v1" 0x00 yyyy-MM), held in memory, one
  KMS call a month, truncated to 8 bytes. Not joinable to `merchant_contributions.install_hash` or across months. Dev/Testing-only
  ephemeral random key; any other environment without `IKeyedHasher` throws (fails closed, `TelemetryServiceCollectionExtensions.cs`
  l.113-117).
- **Collector**: receivers bind 0.0.0.0 inside the container, but compose publishes only 8889 and only on `127.0.0.1`
  (`docker-compose.yml`); 4317/4318 are not published. `debug` exporter is `basic` (no attributes printed). Prometheus
  `resource_to_telemetry_conversion` adds only resource attributes (service name, version, environment).
- **Tail sampling**: in-app sampling is 1.0 and the collector keeps errors plus 10%. Acceptable because spans are already redacted
  in-process before OTLP export; nothing sensitive is sampled out and into the collector.
- **Alert rules and dashboards**: labels and annotations use only store, code, symbol, rule, channel; a lint test enforces the
  banned-word list. Per-purchase and per-operator alerts go through `IAlertSignal`, which logs a UUID and counts `rule` only.
- **Synthetics**: credentials are `${SYNTHETIC_*}` placeholders from the secrets manager; body is `{}`.
- **Packages**: OpenTelemetry core 1.15.3 (post NU1902), instrumentation 1.12.0, Npgsql 10.0.3. Restore treats audit advisories as
  errors and CI has a `dependency-audit` job. No analytics, crash or APM SDK added.

## Findings

### F1 Low (Medium if a future logger call misuses it): `msg` is the template, but nothing forbids interpolated templates
`ZaghlolJsonFormatter.cs` l.34 writes `logEvent.MessageTemplate.Text` verbatim. Placeholders are safe, but `logger.LogError($"verify failed for {token}")`
or `Log.Error("..." + orderId)` makes the secret part of the template and it is written. The current source has no such call (the
only `ILogger` calls are in `Observability/`), and the sentinel tests use placeholders, so this is a guard-rail gap not a live leak.
`Directory.Build.props` sets `AnalysisLevel latest-recommended`, but `.editorconfig` does not pin CA2254 (template must be static) or
CA2253/CA1848 to error.
Required change: set `dotnet_diagnostic.CA2254.severity = error` (and CA2253) in `backend/.editorconfig`; add a formatter test that a
template longer than a bound or containing a digit run of 16 or more is written as `<invalid>`, or document the rule in the backend
review checklist. Owner: T-138 follow-up FU (any C2 task that adds logging inherits the rule).

### F2 Low: Npgsql span events are not stripped; the sentinel covers only the unique-violation case
`RedactingActivityProcessor.cs` cannot remove `Activity.Events` (the API has no removal) and relies on Npgsql not putting
values into them; the comment l.12 only covers instrumentations configured with `RecordException = false`, and `AddSource("Npgsql")`
(`TelemetryServiceCollectionExtensions.cs` l.78) has no such switch. The sentinel test proves that the Postgres unique-violation path
(whose `Detail` holds `Key (k)=(<value>)`) leaks nothing in Npgsql 10.0.3 events. Other server errors put values in `MessageText`
itself (for example `invalid input syntax for type uuid: "<value>"`), and a later Npgsql release could add `exception.message` or
`exception.stacktrace` events. Exploit path: a client sends a malformed value that reaches a typed parameter; the error text rides an
exported span event to the collector and the trace backend.
Required change: add a sentinel scenario with an invalid-cast Postgres error; assert events of exported spans. Defence in depth: add a
collector `transform` processor that deletes span events (or the exception event) on the traces pipeline, and re-run the sentinel on
every Npgsql bump. Owner: T-138 follow-up (test) and T-140 (production collector config).

### F3 Low: metric tag guard checks shape, not value set
`ZaghlolMetrics.Clean` (`TagValueRegex`, `^[A-Za-z0-9_:.-]{1,40}$`) accepts a 36-character UUID, a 32-character hex digest or a numeric
Apple transaction ID. The class comment says tags are "words only", but a caller that passes the wrong variable as `code`, `symbol`
or `reason` exports an identifier as a label and into Prometheus. `SetPriceAge` also grows an unbounded dictionary keyed by the
cleaned symbol, so a bad caller also raises cardinality.
Required change: validate `store` in {google, apple}, `outcome`, `channel`, `kind`, `platform` against fixed sets, `code` against
`ProblemCodes`, `symbol` against the configured symbol list; otherwise `invalid`. Owner: T-138 follow-up before the owning tasks
(T-125 and later) call the instruments.

### F4 Low: collector image is old and unpinned by digest; production receiver exposure not specified
`otel/opentelemetry-collector-contrib:0.116.1` (Dec 2024) is a tag, not a digest, and is well behind current. Receivers have no TLS or
auth and bind 0.0.0.0, which is fine only because compose publishes nothing. The README says production runs "the same pipeline".
Required change: pin by digest, bump after a check of collector advisories, and require in T-140 that OTLP uses TLS with auth or a
private network and the Prometheus port is not public. Owner: T-140 (and an FU for the bump).

### F5 Low: `db.query.text` is allow-listed
`SpanTagPolicy.cs` allows `db.query.text`. With EF Core and Npgsql parameters it holds `$1` placeholders (the processor test checks
that shape), but any raw SQL with an interpolated literal (`ExecuteSqlRaw`, string-built SQL) exports the value.
Required change: forbid string-built SQL in the review checklist (Sonar or analyzer rule `EF1002`/`CA2100` as error), or drop
`db.query.text` and keep `db.operation.name` and a table name. Owner: T-138 follow-up.

### F6 Info: log-key domain separation depends on install-ID validation (T-124)
The monthly log key is an output of the same KMS HMAC key and the same function used for `merchant_contributions.install_hash`
(`KmsLogKeySource`, `LogPseudonymizer.cs`). Separation holds only because install IDs are UUIDs and the log message begins with
`zaghlol-log-v1\0`. If T-124 accepts a free-form `Zaghlol-Install` value, a client could send the label-plus-month string as its
install ID and read the resulting hash, which is the log key. Owner: T-124 must reject any non-UUID install ID before hashing; add a
test. Cleaner: use a separate KMS key or an HKDF-style fixed prefix reserved from install IDs.

### F7 Info: pseudonymizer key failure modes
`AddZaghlolLogPseudonymizer` resolves lazily, so a production host with no KMS fails on the first authenticated request, not at
startup; and a KMS error at month rollover would throw inside the install auth handler. Owner: T-124, which should catch the error
and log `installHash` as absent (not fail the request) and add a startup check for the key source.

### F8 Info: synthetic check output
The `sync` check sends the synthetic install ID and an `Authorization` bearer header. Owner: T-140 to make sure the monitoring
provider does not retain request headers or bodies in check results, and that the synthetic install is excluded from the 10% of
real users counts and holds no Gold entitlement beyond the check.

### F9 Info: collector hardening and Sensitive<T> JSON
No `memory_limiter` processor in front of `tail_sampling` (10 s wait holds traces in memory); add it in T-140. `Sensitive<T>`
writes the plain value to JSON by design, so never use it with a serializer that feeds logs or problem details; the allow-list
formatter already prevents that for logs.

## Not testable here (T-140 checklist, as stated in the README)
Edge/WAF logging of queries and bodies, IP truncation, 30-day retention, alert delivery, production tail sampling, advisory status of
the pinned packages and image.

## Follow-ups

| ID | Severity | Item | Owner |
|---|---|---|---|
| F1 | Low | CA2254/CA2253 as errors; template bound test | T-138 follow-up |
| F2 | Low | Invalid-cast Npgsql sentinel; collector deletes span events | T-138 follow-up, T-140 |
| F3 | Low | Fixed value sets for metric tags | T-138 follow-up |
| F4 | Low | Pin collector digest, bump, TLS/auth in prod | T-140 |
| F5 | Low | Forbid string-built SQL or drop `db.query.text` | T-138 follow-up |
| F6 | Info | UUID-only install IDs before hashing | T-124 |
| F7 | Info | Pseudonymizer failure handling, startup check | T-124 |
| F8 | Info | Synthetic provider retention of headers | T-140 |
| F9 | Info | memory_limiter; Sensitive<T> JSON caveat | T-140 |
