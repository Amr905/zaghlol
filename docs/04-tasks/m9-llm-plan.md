# M9 — LLM helper: build plan (ASK-LLM + LLM-CATEGORISE)

| | |
|---|---|
| Status | **DRAFT, approved by the PO in advance (2026-11-26 03:25 Cairo: start the first batch without waiting)** (Phase 4) |
| Date | 2026-11-26 |
| Inputs | `docs/01-requirements/ask-llm.md` v0.2, `llm-categorise.md`; `docs/02-design/ask-llm-ux.md` + copy deck Part 4; `docs/03-technical/ask-llm.md`, `llm-categorise.md`, ADR-027 (approved 2026-11-26 03:21); PO_DECISIONS rows ASK-LLM, LLM-CATEGORISE |
| Tasks | T-272…T-315 (44): C1 3 · C2 12 · C3 9 · C4 17 · docs/ops 3. Opus builders: T-283, T-286, T-290, T-306, T-307 |

Batch numbers start at **78** (batch 77 is already used on the board). Each batch is ≤ 5 tasks, one builder per task, on different lanes or disjoint files; every batch except 86 holds a C4 task, so its reviewer runs on Opus.

## Lanes
| Lane | Area | Tasks |
|---|---|---|
| B | backend (`backend/`) | T-272, T-273, T-280, T-282, T-283, T-284, T-285, T-286, T-288, T-289, T-299, T-300, T-301, T-302, T-303, T-304 |
| A | app core (`app/lib/core`, `features/ask|categorization` application/data, device tests) | T-287, T-290, T-292, T-293, T-294, T-298, T-306, T-307, T-308, T-309, T-313 |
| P | parsing package + assets | T-275, T-278, T-281, T-305 |
| Q | domain package (`zaghlol_domain`, pure calculators) | T-276, T-277 |
| U | UI + ARB | T-274, T-295, T-296, T-297, T-310, T-311, T-312 |
| N | native (Kotlin/Swift) | T-291 |
| Doc | docs | T-279, T-314, T-315 |

**Contracts first:** T-272 (schemas, vectors, OpenAPI, fake fixtures) unblocks both sides. The backend builds against the fake provider; the app builds against fake clients and the fixture replies, so neither waits for the other until the device E2E tasks.

## Batches
| Batch | Tasks (lane) | Why together |
|---|---|---|
| 78 | T-272 (B contracts) · T-273 (B migration) · T-276 (Q) · T-278 (P) · T-274 (U, C1) | No dependencies; contract + schema roots; pure calculators and masker start at once |
| 79 | T-280 (B validator) · T-282 (B gateway core) · T-281 (P) · T-277 (Q) · T-306 (A, Opus) | Everything that needs only T-272, plus the independent Drift migration |
| 80 | T-284 (B config/flags) · T-285 (B quota) · T-287 (A) · T-291 (N) · T-275 (P, C1) | Backend gate pieces; app config; native attestation seam |
| 81 | T-283 (B keys, Opus) · T-286 (B attestation, Opus) · T-290 (A core/llm, Opus) · T-292 (A executor) · T-279 (Doc) | Security-heavy batch; executor in a separate feature folder from core/llm |
| 82 | T-288 (B adapters) · T-289 (B spend) · T-293 (A orchestrator) · T-295 (U consent) · T-305 (P) | — |
| 83 | T-299 (B ask endpoint) · T-294 (A filler) · T-296 (U S-50) · T-307 (A categorizer, Opus) · T-310 (U, C1) | Ask endpoint closes the backend Ask path |
| 84 | T-300 (B eval) · T-302 (B categorise) · T-297 (U answers) · T-308 (A sender) · T-309 (A feedback) | T-308/T-309 touch different files (sender vs feedback + sync builder) |
| 85 | T-303 (B feedback intake) · T-298 (A device E2E ask) · T-311 (U) · T-312 (U) | Ask feature complete on device behind flags |
| 86 | T-304 (B operator review) · T-313 (A device E2E categorise) · T-314 (Doc) | Categorise complete; docs as built |
| PO-blocked | T-301 (live eval) when keys arrive · T-315 (launch checklist) | Nothing goes on in production before T-315 |

## Dependency table
| Task | Depends on | Unblocks |
|---|---|---|
| T-272 | — | T-280, T-281, T-282, T-284, T-286, T-287, T-290, T-309 |
| T-273 | — | T-284, T-285, T-289, T-302 |
| T-274 | — | T-294, T-295, T-296, T-297 |
| T-275 | — | T-305 |
| T-276, T-277 | — | T-292 |
| T-278 | — | T-293, T-295 |
| T-279 | — | T-310 |
| T-280 | T-272 | T-299 |
| T-281 | T-272 | T-292, T-293, T-294 |
| T-282 | T-272 | T-283, T-288, T-289, T-299 |
| T-283 | T-282 | T-301 |
| T-284 | T-272, T-273 | T-289, T-299, T-303 |
| T-285 | T-273 | T-299 |
| T-286 | T-272 | T-299 |
| T-287 | T-272 | T-290 |
| T-288 | T-282 | T-300 |
| T-289 | T-282, T-273, T-284 | T-299 |
| T-290 | T-272, T-287, T-291 | T-293, T-295, T-308 |
| T-291 | — | T-290 |
| T-292 | T-281, T-276, T-277 | T-293, T-294 |
| T-293 | T-278, T-281, T-290, T-292 | T-296 |
| T-294 | T-281, T-274, T-292 | T-297 |
| T-295 | T-274, T-278, T-290 | T-298 |
| T-296 | T-274, T-293 | T-298 |
| T-297 | T-274, T-294 | T-298 |
| T-298 | T-295, T-296, T-297 | T-315 |
| T-299 | T-280, T-282, T-284, T-285, T-286, T-289 | T-300, T-302, T-314 |
| T-300 | T-299, T-288 | T-301 |
| T-301 | T-300, T-283, **PO** | T-315 |
| T-302 | T-299, T-273 | T-303, T-314 |
| T-303 | T-302, T-284 | T-304, T-314 |
| T-304 | T-303 | T-315 |
| T-305 | T-275 | T-308 |
| T-306 | — | T-307, T-308, T-309 |
| T-307 | T-306 | T-309 |
| T-308 | T-305, T-306, T-290 | T-312 |
| T-309 | T-306, T-307, T-272 | T-311 |
| T-310 | T-279 | T-311, T-312 |
| T-311 | T-309, T-310 | T-313 |
| T-312 | T-308, T-310 | T-313 |
| T-313 | T-311, T-312 | T-315 |
| T-314 | T-299, T-302, T-303 | T-315 |
| T-315 | T-298, T-301, T-304, T-313, T-314, **PO** | flags on |

## Critical path
**T-272 → T-284 → T-289 → T-299 → T-302 → T-303 → T-304 / T-314 → T-315** (backend; 7 build steps, batches 78 → 86). The app path T-272 → T-287 → T-290 → T-293 → T-296 → T-298 is one step shorter and finishes in batch 85. Production launch is gated by the PO items, not by code.

## PO-blocked
| Item | Blocks | Needed from the PO |
|---|---|---|
| Provider accounts and keys (OpenAI EU project, Vertex AI EU + service account, Anthropic) as GitHub `llm-eval` environment secrets | T-301 | Create accounts, add secrets; never paste keys anywhere else |
| OQ-ASK-01 legal (FRA, investment disclaimer) | T-315 → `ask_llm_invest` | Legal sign-off |
| OQ-ASK-03 provider contract, EU region, PDPL basis | T-315 → `ask_llm`, `llm_categorise` | Contract + legal |
| OQ-LCAT-08 retention and store labels | T-315 → `llm_categorise` | Legal confirmation |
| Zero-retention request (ZDR / Modified Abuse Monitoring or equivalent) | T-315 (policy wording) | Submit request; until granted, the policy states the 30-day window |
| Play Console + Play Integrity daily-quota increase; App Store Connect (App Attest) | T-315 → production `Enforce` | Store accounts |
| Production provider key in the KMS secret store; spend cap USD 10 + alert mailbox | T-315 | Key placement; confirm mailbox |

Build tasks are not blocked: production stays fail-closed (flags off, attestation `Enforce` with no verifiers → `503`), and staging/tests run on the fake provider and `Fake`/`ReportOnly` attestation (ask-llm §5).
