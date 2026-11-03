# ADR-019: Minimum OS versions (answers OQ-03)

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | NFR-COMP-01 |

## Context
NFR-COMP-01 proposed Android 8.0+ and iOS 17+. iOS 17 is needed for Shortcuts automations that run immediately. Play requires recent target APIs (API 36) for updates.

## Options considered
1. **Android 8.0 (API 26) / iOS 17** — Wide Egyptian device coverage; meets the automation needs.
2. **Android 10 (API 29) / iOS 18** — Simpler testing; cuts off more older devices common in Egypt.

## Decision
**minSdk 26, targetSdk 36; iOS deployment target 17.0.** Features that need newer APIs degrade gracefully: on-device speech (API 31+), recents-screenshot API (33+), iOS 26 SpeechAnalyzer.

## Consequences
The device matrix includes API 26 and iOS 17 (testing-strategy §3).
