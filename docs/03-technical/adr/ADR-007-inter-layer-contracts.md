# ADR-007: Platform channel generation (Pigeon) and domain packaging

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | platform-channels.md |

## Context
Several native contracts (capture, spool, OCR, iCloud, widgets, device security). Domain logic must be pure Dart and reusable in the headless engine.

## Options considered
1. **Hand-written MethodChannels** — Flexible; stringly-typed, error-prone.
2. ****Pigeon-generated APIs + pure-Dart workspace packages (`zaghlol_domain`, `zaghlol_parsing`)**** — Type-safe, generated Kotlin/Swift; the domain is compiled and tested without Flutter.

## Decision
**Option 2** with a pub workspace (project-structure.md).

## Consequences
Pigeon regenerates on contract change, and CI fails if generated files are stale.
