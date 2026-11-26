# M9 — LLM helper: build plan (ASK-LLM + LLM-CATEGORISE)

| | |
|---|---|
| Status | **DRAFT, approved by the PO in advance (2026-11-26 03:25 Cairo: start the first batch without waiting)** (Phase 4) |
| Date | 2026-11-26 |
| Inputs | `docs/01-requirements/ask-llm.md` v0.2, `llm-categorise.md`; `docs/02-design/ask-llm-ux.md` + copy deck Part 4; `docs/03-technical/ask-llm.md`, `llm-categorise.md`, ADR-027 (approved 2026-11-26 03:21); PO_DECISIONS rows ASK-LLM, LLM-CATEGORISE |
| Tasks | T-322…T-365 (44): C1 3 · C2 12 · C3 9 · C4 17 · docs/ops 3. Opus builders: T-333, T-336, T-340, T-356, T-357 |

Batch numbers start at **78** (batch 77 is already used on the board). Each batch is ≤ 5 tasks, one builder per task, on different lanes or disjoint files; every batch except 86 holds a C4 task, so its reviewer runs on Opus.

## Lanes
| Lane | Area | Tasks |
|---|---|---|
| B | backend (`backend/`) | T-322, T-323, T-330, T-332, T-333, T-334, T-335, T-336, T-338, T-339, T-349, T-350, T-351, T-352, T-353, T-354 |
| A | app core (`app/lib/core`, `features/ask|categorization` application/data, device tests) | T-337, T-340, T-342, T-343, T-344, T-348, T-356, T-357, T-358, T-359, T-363 |
| P | parsing package + assets | T-325, T-328, T-331, T-355 |
| Q | domain package (`zaghlol_domain`, pure calculators) | T-326, T-327 |
| U | UI + ARB | T-324, T-345, T-346, T-347, T-360, T-361, T-362 |
| N | native (Kotlin/Swift) | T-341 |
| Doc | docs | T-329, T-364, T-365 |

**Contracts first:** T-322 (schemas, vectors, OpenAPI, fake fixtures) unblocks both sides. The backend builds against the fake provider; the app builds against fake clients and the fixture replies, so neither waits for the other until the device E2E tasks.

## Batches
| Batch | Tasks (lane) | Why together |
|---|---|---|
| 78 | T-322 (B contracts) · T-323 (B migration) · T-326 (Q) · T-328 (P) · T-324 (U, C1) | No dependencies; contract + schema roots; pure calculators and masker start at once |
| 79 | T-330 (B validator) · T-332 (B gateway core) · T-331 (P) · T-327 (Q) · T-356 (A, Opus) | Everything that needs only T-322, plus the independent Drift migration |
| 80 | T-334 (B config/flags) · T-335 (B quota) · T-337 (A) · T-341 (N) · T-325 (P, C1) | Backend gate pieces; app config; native attestation seam |
| 81 | T-333 (B keys, Opus) · T-336 (B attestation, Opus) · T-340 (A core/llm, Opus) · T-342 (A executor) · T-329 (Doc) | Security-heavy batch; executor in a separate feature folder from core/llm |
| 82 | T-338 (B adapters) · T-339 (B spend) · T-343 (A orchestrator) · T-345 (U consent) · T-355 (P) | — |
| 83 | T-349 (B ask endpoint) · T-344 (A filler) · T-346 (U S-50) · T-357 (A categorizer, Opus) · T-360 (U, C1) | Ask endpoint closes the backend Ask path |
| 84 | T-350 (B eval) · T-352 (B categorise) · T-347 (U answers) · T-358 (A sender) · T-359 (A feedback) | T-358/T-359 touch different files (sender vs feedback + sync builder) |
| 85 | T-353 (B feedback intake) · T-348 (A device E2E ask) · T-361 (U) · T-362 (U) | Ask feature complete on device behind flags |
| 86 | T-354 (B operator review) · T-363 (A device E2E categorise) · T-364 (Doc) | Categorise complete; docs as built |
| PO-blocked | T-351 (live eval) when keys arrive · T-365 (launch checklist) | Nothing goes on in production before T-365 |

## Dependency table
| Task | Depends on | Unblocks |
|---|---|---|
| T-322 | — | T-330, T-331, T-332, T-334, T-336, T-337, T-340, T-359 |
| T-323 | — | T-334, T-335, T-339, T-352 |
| T-324 | — | T-344, T-345, T-346, T-347 |
| T-325 | — | T-355 |
| T-326, T-327 | — | T-342 |
| T-328 | — | T-343, T-345 |
| T-329 | — | T-360 |
| T-330 | T-322 | T-349 |
| T-331 | T-322 | T-342, T-343, T-344 |
| T-332 | T-322 | T-333, T-338, T-339, T-349 |
| T-333 | T-332 | T-351 |
| T-334 | T-322, T-323 | T-339, T-349, T-353 |
| T-335 | T-323 | T-349 |
| T-336 | T-322 | T-349 |
| T-337 | T-322 | T-340 |
| T-338 | T-332 | T-350 |
| T-339 | T-332, T-323, T-334 | T-349 |
| T-340 | T-322, T-337, T-341 | T-343, T-345, T-358 |
| T-341 | — | T-340 |
| T-342 | T-331, T-326, T-327 | T-343, T-344 |
| T-343 | T-328, T-331, T-340, T-342 | T-346 |
| T-344 | T-331, T-324, T-342 | T-347 |
| T-345 | T-324, T-328, T-340 | T-348 |
| T-346 | T-324, T-343 | T-348 |
| T-347 | T-324, T-344 | T-348 |
| T-348 | T-345, T-346, T-347 | T-365 |
| T-349 | T-330, T-332, T-334, T-335, T-336, T-339 | T-350, T-352, T-364 |
| T-350 | T-349, T-338 | T-351 |
| T-351 | T-350, T-333, **PO** | T-365 |
| T-352 | T-349, T-323 | T-353, T-364 |
| T-353 | T-352, T-334 | T-354, T-364 |
| T-354 | T-353 | T-365 |
| T-355 | T-325 | T-358 |
| T-356 | — | T-357, T-358, T-359 |
| T-357 | T-356 | T-359 |
| T-358 | T-355, T-356, T-340 | T-362 |
| T-359 | T-356, T-357, T-322 | T-361 |
| T-360 | T-329 | T-361, T-362 |
| T-361 | T-359, T-360 | T-363 |
| T-362 | T-358, T-360 | T-363 |
| T-363 | T-361, T-362 | T-365 |
| T-364 | T-349, T-352, T-353 | T-365 |
| T-365 | T-348, T-351, T-354, T-363, T-364, **PO** | flags on |

## Critical path
**T-322 → T-334 → T-339 → T-349 → T-352 → T-353 → T-354 / T-364 → T-365** (backend; 7 build steps, batches 90 → 86). The app path T-322 → T-337 → T-340 → T-343 → T-346 → T-348 is one step shorter and finishes in batch 97. Production launch is gated by the PO items, not by code.

## PO-blocked
| Item | Blocks | Needed from the PO |
|---|---|---|
| Provider accounts and keys (OpenAI EU project, Vertex AI EU + service account, Anthropic) as GitHub `llm-eval` environment secrets | T-351 | Create accounts, add secrets; never paste keys anywhere else |
| OQ-ASK-01 legal (FRA, investment disclaimer) | T-365 → `ask_llm_invest` | Legal sign-off |
| OQ-ASK-03 provider contract, EU region, PDPL basis | T-365 → `ask_llm`, `llm_categorise` | Contract + legal |
| OQ-LCAT-08 retention and store labels | T-365 → `llm_categorise` | Legal confirmation |
| Zero-retention request (ZDR / Modified Abuse Monitoring or equivalent) | T-365 (policy wording) | Submit request; until granted, the policy states the 30-day window |
| Play Console + Play Integrity daily-quota increase; App Store Connect (App Attest) | T-365 → production `Enforce` | Store accounts |
| Production provider key in the KMS secret store; spend cap USD 10 + alert mailbox | T-365 | Key placement; confirm mailbox |

Build tasks are not blocked: production stays fail-closed (flags off, attestation `Enforce` with no verifiers → `503`), and staging/tests run on the fake provider and `Fake`/`ReportOnly` attestation (ask-llm §5).
