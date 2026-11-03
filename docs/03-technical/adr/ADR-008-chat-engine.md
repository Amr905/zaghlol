# ADR-008: Ask Zaghlol chat engine

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | domain-algorithms §10 |

## Context
D-06: offline rules/templates engine, no LLM (OOS-05). Must answer the FR-CHAT-01 intents in Egyptian Arabic and English and never fabricate numbers.

## Options considered
1. **Keyword/regex intent grammar + slot filling + SQL query templates + answer templates** — Deterministic, offline, testable, small.
2. **Small on-device intent classifier (TFLite) + slots** — Better recall on phrasing variety; needs training data and model maintenance.
3. **Cloud or on-device LLM** — Excluded by D-06 and privacy.

## Decision
**Option 1.** The grammar lives as data (`chat_grammar.json`) with weighted patterns per intent. Unknown questions get suggestion chips.

## Consequences
Coverage grows by adding patterns from user-reported misses (no telemetry, so via support and the diag share). Can be upgraded to option 2 later behind the same interface.
