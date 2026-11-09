# Observability as code (T-138)

| Path | What |
|---|---|
| `alerts/*.yaml` | Prometheus alert rules for every alert in error-handling-and-observability.md section 4. CI runs `promtool check rules` and the rule-file lint test (`Zaghlol.Contract.Tests`). |
| `dashboards/*.json` | Grafana dashboards: service overview, purchases / entitlements / seats, catalog and prices. |
| `synthetics.yaml` | Synthetic checks (health, sync, latest catalog snapshot). |
| `otel-collector.yaml` | The local collector used by `docker compose` (metrics on `:8889`) and the tail-sampling policy production uses. |

Rules for rule files: no label, annotation or expression may mention an install, account, token, transaction, order, e-mail,
IP address, nonce or seat key. Per-purchase and per-operator alerts are fired by the acting service through `IAlertSignal`
(`audit_alert.fired{rule}` plus one log line carrying the purchase UUID or the operator UUID).

Environment: the API and the worker read the standard `OTEL_EXPORTER_OTLP_ENDPOINT` (exporters are off when it is unset),
and `Telemetry:SampleRatio` (default `1`; the collector does the 10% sampling).

Not testable in CI (T-140 checklist): alert delivery and paging, dashboards rendering in the provider, multi-region
synthetics, edge/WAF/CDN query and body logging, IP truncation and 30-day retention in the provider's log store, and
tail-sampling behaviour in production.
