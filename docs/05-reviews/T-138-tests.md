# T-138 test review (test-engineer)

Branch `origin/task/T-138-observability` @ 902498a. CI run 42525861682 (head_sha 902498a): `backend-ci` success. Jobs: build/format/test, alert rules (promtool), image scan, vulnerable packages, Spectral, and docker compose (including the step "Metrics are visible in the local collector") are all success. No local .NET SDK, so results are taken from the CI job list; tests were read, not run locally.

## Verdict: TESTS_INSUFFICIENT

One major gap (M1): nothing proves the real span exporter is registered after the redactor, and the harness cannot detect it.

## Acceptance criteria and follow-ups

| Criterion / follow-up | Test(s) | Would it fail if the behaviour broke? | Result |
|---|---|---|---|
| Metrics visible in the local collector | CI step "Metrics are visible in the local collector" (compose, curls :8889, greps `zaghlol_service_up` and `http_server_request_duration_seconds_count`, 60 s retry) | Yes for the metrics pipeline; fails if the collector/OTLP wiring breaks. Only one Zaghlol series is asserted; the traces pipeline (tail sampling) is not exercised | PASS (see m5) |
| Every alert exists as code, no identifier/token | `AlertRuleLintTests.EveryAlertOfTheDesignExistsOnce`, `NoLabelAnnotationOrExpressionMentionsAnIdentifierOrCredential`, `EveryAuditAlertRuleHasAnAlertOnItsExactName`, `EveryAlertHasASeveritySummaryAndDescription`, `DashboardsAreValidAndFreeOfIdentifiers`; promtool job | Yes: 29 names asserted individually, duplicates refused, a missing/renamed rule fails; the audit rule names are tied to the `AuditAlertRule` enum. Thresholds spot-checked in YAML (172800 s, 21600 s, 86400 s, 5 s etc.) are right, but no test pins them (m4) | PASS |
| Privacy word list | `TheLintCatchesForbiddenWords` (positive control on the helper: installId, purchase_token, orderId, client_ip, seat_key; negative control for innocent text) | Yes. Whole-word matching with camelCase and adjacent-pair splitting is narrower than the design's substring regex, which is sensible (`ip` would hit "description"). Scans name, labels, annotations, expr and dashboards; `synthetics.yaml` is only checked for a credential placeholder | PASS |
| Metric names in rules match defined instruments | `EveryZaghlolMetricInRulesAndDashboardsIsDefinedByTheCode` (builds `ZaghlolMetrics` + `KmsMetrics`, maps names OTLP to Prometheus incl. unit and `_total`, `Assert.NotEmpty(used)`) | Yes for metric names. Label names (`by (symbol)`, `rule="..."`) are not checked against instrument tags (m3). Built-in `http_*`/`process_*` metrics are not checked | PASS |
| Sentinel: query, path key, outbound Play URL (token and order, retry forced), `Location` | `SentinelTests` x2 fixtures: `TheSentinelAppearsInNoLogByte` (final bytes), `...InNoSpan` (name, tags, events, baggage, status, links via `Describe`), `...InNoMetricTag`, `EveryLogLineIsAllowListedJson`, `ServerSpansCarryTheRouteTemplateNotThePath`, `OutboundSpansCarryTheExplicitTemplate` | Yes for logs, tags, names. Positive controls: `EveryPlacementRanAndWasLogged` asserts each status, 2 attempts per Play route (retry handler logged), a request line per request incl. route templates and `unmatched`, plus `FrameworkCategoriesStayAtWarning` | PASS (M1 is the exception) |
| Extension: `seatKeys`, `ownershipCheck.orderId`, `Zaghlol-Time-Nonce`, `Idempotency-Key`, exceptions | Same scenario: `body` (logs `{@Body}`, `{Body}`, `{SeatKeys}` through `Sensitive<T>`), `body-throws` (message interpolates the DTO), `throws` (message holds the sentinel), `nonce` and `nonce-malformed` on the real `/t/anchored` filter, `idempotency`; `UnhandledExceptionsAreLoggedAsTypeAndStackOnly` | Yes: breaking `Sensitive<T>.ToString`, the exception-message rule or the allow-list fails them. `Idempotency-Key` goes to a stub endpoint that never reads it, so it only proves nothing logs headers (m2) | PASS |
| Production and Verbose levels | `ProductionLevelSentinelTests` (real levels, `FrameworkCategoriesStayAtWarning`, Testcontainers Npgsql unique violation `TheDatabaseUniqueViolationRanAndItsKeyIsNowhere`, Npgsql span seen) and `VerboseLevelSentinelTests` (`TheFrameworkReallyLoggedAtVerbose`: AspNetCore, `System.Net.Http.HttpClient.google-play`, `Test.Retry` present) | Yes. Verbose proves the formatter alone holds when the framework talks. DB case runs at Production only, acceptable | PASS |
| Span exporter placed after the redactor | Harness adds `AddInMemoryExporter` after `AddZaghlolApiTelemetry`; `AddProcessor(new RedactingActivityProcessor())` then `AddOtlpExporter` only in code | No. See M1 | GAP (major) |
| Metric tags | `TheSentinelAppearsInNoMetricTag` (tag values of every instrument, positive control `http.route=/test/items/{key}`); `ZaghlolMetricsTests.ATagValueThatIsNotAShortWordIsReplaced`, `SyncSizeIsTaggedByUpToDateOnly`, `PurchaseVerifyCarriesStoreOutcomeAndCode` | Yes for built-in meters; Zaghlol meter tags are exercised by unit sanitisation tests, not by requests | PASS |
| Never-logged list | `ZaghlolJsonFormatterTests.TheNeverLoggedNamesIncludeTheTimeNonceAndIdempotencyHeaders`, `NoNeverLoggedNameIsAllowListed`, `ANeverLoggedNameAsAPropertyWritesNeitherNameNorValue` (loops all 33 names as a property, a `Headers`/`RequestHeaders` dictionary), `SensitiveMembersNeverShowTheirValueThroughDestructuringOrToString`, sentinel `TheHeaderNamesInTheScenarioAreTheNeverLoggedOnes` | Yes. The name-as-property test fails if any listed name becomes allow-listed | PASS |
| FU-002 field names | `RequestCompletedUsesTheDocumentedFieldNames`, `TheSectionNamesAreAllWritable`, level, shape and `msg`-is-template tests | Yes (see m1 on "golden") | PASS |
| FU-008 query/Location never logged, route templates only | Sentinel query, unmatched route with `?x=<s>`, 303 `Location`, `ServerSpansCarry...`, `url.query`/`url.full` null | Yes | PASS |
| T-123 G3 (nonce header on the deny-list, asserted directly) | `ANeverLoggedNameAsAPropertyWritesNeitherNameNorValue` + `TheNeverLoggedNames...` + sentinel header-name test | Yes. Closed | PASS |
| T-123 code nit #9 (status mapping / SignVerify metric) | `SignVerifyMetricTests` (wrong key counted as sign_verify, unreachable KMS as sign, stable tag), `SignerTests` change | Yes. Closed | PASS |
| Monthly log key (Lead FU) | `LogPseudonymizerTests`: 16 hex, stable within a month, rotates monthly, derived from pepper with the `zaghlol-log-v1` label via `IKeyedHasher` | Yes. Choice of `KmsLogKeySource` vs ephemeral vs throw in production is untested (m6) | PASS |
| Never set `Include Error Detail` / `EnableSensitiveDataLogging` | `DatabaseRoleGuardTests` (FU-025, from T-122) covers Include Error Detail; nothing for `EnableSensitiveDataLogging` | Partly | see m7 |
| Alert signal | `AlertSignalTests`: one warn line, counter, id required, names match rules | Yes | PASS |

## Gaps

| # | Severity | Gap | Owner |
|---|---|---|---|
| M1 | **major** | Nothing proves the exporter comes after `RedactingActivityProcessor` in the real pipeline. The OTLP exporter is only added when an endpoint is set, which no test does. The harness exporter is added by the test itself and `InMemoryExporter<Activity>` keeps live `Activity` references, so even a reversed order would still show redacted tags at assertion time. Moving `AddOtlpExporter()` above `AddProcessor` would pass every test, and spans (path, query, status text) would leave unredacted. Fix: in `AddZaghlolTelemetry` tests set `OTEL_EXPORTER_OTLP_ENDPOINT` and add a recording processor (snapshots tags in `OnEnd`) both before... or resolve the `TracerProvider` and assert the processor order; or assert via a snapshotting exporter registered through `configureTracing`/after the call plus a canary tag. | T-138 |
| m1 | minor | "Formatter golden output" is a field-list/value assertion, not a byte-for-byte golden line. Acceptable for FU-002. | T-138 follow-up |
| m2 | minor | `Idempotency-Key` and the Apple callback are exercised against test stubs (no real idempotency filter or callback exists yet). Re-run the placements against the real endpoints when they land. | T-124 / T-135 / T-136 |
| m3 | minor | Rule lint checks metric names, not label names (e.g. `by (symbol)`, `store=`) against instrument tags; a renamed tag would pass. | T-138 follow-up |
| m4 | minor | No `promtool test rules` unit tests; thresholds (48 h, 6 h/24 h, 3x baseline, 0.5 quota) are correct today but unpinned. | T-140 |
| m5 | minor | The collector smoke asserts one Zaghlol series (`zaghlol_service_up`) and HTTP duration; the traces pipeline and tail sampling are not exercised (design lists tail sampling as untestable in CI). | T-140 checklist |
| m6 | minor | No test for `AddZaghlolLogPseudonymizer` source selection (KMS used when present; throws outside Development/Testing without KMS). | T-124 (wires installHash) |
| m7 | minor | No test or analyzer ban for `EnableSensitiveDataLogging`; the "reflection test over DTO assembly requires `Sensitive<T>`" from the design note is also absent (passes trivially until T-124+, but it must exist before they add DTOs). | T-124 (add the reflection test with the first DTOs) |
| m8 | nit | No canary showing the harness would catch a leak (for example asserting the sentinel is present in the raw Serilog event before formatting at Verbose). Mitigated by the Verbose fixture and `TheFrameworkReallyLoggedAtVerbose`. | T-138 optional |

## Round 2 (delta 902498a..c0288f4, backend-ci 42527311523 green per coordinator)

Scope: only M1. Read `git diff 902498a c0288f4`; not run locally (no .NET SDK).

What the delta does:
- `AddZaghlolTelemetry` gets a `configureExporters` hook, called after `AddProcessor(new RedactingActivityProcessor())` and after the `if (exportOtlp) AddOtlpExporter()` block (TelemetryServiceCollectionExtensions.cs lines 74-81).
- `ExporterOrderTests.TheRealPipelineExportsRedactedSpansWithTheOtlpEndpointSet` calls the real `AddZaghlolTelemetry` with `OTEL_EXPORTER_OTLP_ENDPOINT` set, resolves the real `TracerProvider`, and registers a `SnapshotProcessor` through the hook. The probe copies tags and status in `OnEnd` (not live refs). The test asserts that `url.full`, `url.query`, the unlisted `enduser.id` and the status text (carrying the sentinel) are absent, and that `http.request.method` is kept. This is the real setup code, not a hand-built order.
- `TheProbeCatchesAnExporterThatRunsBeforeTheRedactor` is a hand-built reversed order. It is only a negative control for the probe, and it does prove the probe sees the sentinel when it runs first. Valid as a control.

Would it fail if the OTLP exporter moved before the redactor? **No.** The probe is not the OTLP exporter. It sits at the `configureExporters` call, which stays at the end of the lambda. Moving `tracing.AddOtlpExporter()` above `AddProcessor(new RedactingActivityProcessor())` leaves the redactor before the probe, so the test still passes while the real exporter would receive unredacted spans. The test does fail if the redactor is removed or moved after the hook, which is a genuine improvement. The comment "same place as the OTLP exporter" is held only by adjacency in the source.

Residual gap M1b (major, T-138): the OTLP exporter's own position relative to the redactor is unproven.
Smallest fix: route the OTLP registration through a seam the test can replace. For example, an internal parameter or overload `Action<TracerProviderBuilder> addOtlpExporter = static t => t.AddOtlpExporter()` called where `AddOtlpExporter()` is today. The test passes the probe in its place and with the endpoint set, so moving that call above the redactor makes the probe see the sentinel and the test fail. (Alternative: build the exporter list once, `[otlp, extras]`, and add all of it after the redactor, with the test substituting the list.) A mutation check, moving the line locally and seeing the test go red, should be part of the fix.

Other delta items (not part of the round, noted only): `AnyOccurrenceSeriesExistAtZeroBeforeAnyEvent` covers the audit_alert rules and dead_letter stores; `KmsMetrics.Seed()` (five operations) has no direct test; the Play Integrity `and max(...) > 0` guard in `seats.yaml` is not pinned by a unit test (m4 already). Both minor.

### Round 2 verdict: TESTS_INSUFFICIENT

M1 is narrowed but not closed: one remaining major (M1b). Everything else stays as in round 1. After the seam fix and a passing mutation check, the verdict would be TESTS_SUFFICIENT without another full round.
