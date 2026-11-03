# ADR-021: Measuring success metrics without analytics (answers OQ-01)

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | error-handling-and-observability §5 |

## Context
NFR-PRIV-01 forbids analytics SDKs. SM-01…07 still need some measurement.

## Options considered
1. **No measurement beyond store consoles** — Zero privacy impact; blind on activation.
2. ****Backend aggregate counters derived from existing calls + store consoles + CI parse accuracy + opt-in surveys**** — No new data collected; only daily counts.
3. **Privacy-preserving telemetry (e.g. randomized response)** — Better insight; adds a data flow the privacy promise doesn't cover.

## Decision
**Option 2:** `daily_active_counts` (distinct installs syncing per day/platform/version), purchases by plan, catalog adoption, plus store console retention and the fixture-corpus accuracy.

## Consequences
Activation (SM-01) can only be approximated (e.g. installs that reach a first sync). An optional, explicit "share capture health" feature could be proposed later as a separate decision.
