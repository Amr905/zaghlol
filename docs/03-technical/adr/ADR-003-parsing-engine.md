# ADR-003: Parsing approach: data-driven template registry + generic heuristics

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | parsing-engine.md |

## Context
About 80 institutions in Arabic and English (FR-PAR-01), deterministic and auditable results, fast parsing (< 10 ms), templates updated per release (D-17). Competitors market "AI" parsing.

## Options considered
1. **Hand-coded parser per bank** — Fast to start; becomes unmaintainable; mixes data and code.
2. ****Versioned JSON regex templates + shared extraction + generic fallback**** — Adding a bank = data + fixtures; lintable; explainable ("how Zaghlol read this", S-12).
3. **On-device ML model (NER)** — Handles unseen formats, but needs a training corpus we don't have (OQ-04), is non-deterministic and adds MBs; OQ-14 keeps it as a later option.

## Decision
**Option 2**, with the generic heuristic parser for unknown senders always going through review (FR-PAR-13).

## Consequences
Accuracy depends on real samples (OQ-04/18, R-03). A regex linter guards against catastrophic backtracking.
