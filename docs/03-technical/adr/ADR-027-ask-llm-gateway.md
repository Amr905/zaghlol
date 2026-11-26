# ADR-027: LLM gateway for the online helper and automatic categories

| | |
|---|---|
| Status | Proposed (Phase 3, awaiting PO approval) |
| Date | 2026-11-26 |
| Deciders | Product owner (ASK-LLM, LLM-CATEGORISE, D-88…D-96), solution-architect |
| References | `docs/03-technical/ask-llm.md`, `docs/03-technical/llm-categorise.md`; SRS `ask-llm.md` v0.2, `llm-categorise.md`; ADR-012 (attestation on restore), ADR-022 (backend), ADR-026 (HostSecrets) |

## Context
D-88 and D-94 allow two LLM uses while keeping financial data on the phone: (1) a typed, scrubbed and placeholdered question
becomes a **plan** that the phone executes; (2) a normalised business merchant name becomes one **system category code**. Both
need the same server pieces: provider access with no retention, a structured-output contract the model cannot leave, quotas per
install/account per Cairo calendar month (5/50 questions, 15/150 merchants), device attestation, rate limits, a spend cap, a kill
switch and no logging of the text. The backend runs on a 256 MB shared IIS site with embedded workers (ADR-026) or on the
self-hosted kit (ADR-025); store accounts (Play Console, App Store Connect) are not set up yet, so real attestation tokens can't
be produced. The PO asked for the cheapest two providers to be compared on an Egyptian-Arabic accuracy test (D-91).

## Options
**A. Where the model runs**
1. Backend gateway calling a hosted provider (chosen below).
2. On-device model (e.g. a small open model): no text leaves the phone, but hundreds of MB of download, weak Egyptian Arabic,
   slow on mid-range phones, and still needs a closed output contract. Rejected for v1; keep the plan schema so it could plug in later.
3. App calls the provider directly: exposes the provider key, no quota or kill switch. Rejected.

**B. Output contract**
1. Provider structured output (JSON Schema, strict) + server and phone validation (chosen).
2. Free-text answer parsed by heuristics: unbounded injection surface, numbers from the model. Rejected (FR-LLM-05/08).
3. Tool/function calling with one tool per plan: equivalent safety, more tokens and provider-specific shapes. Kept as a fallback
   if a provider's JSON Schema subset can't express `anyOf`.

**C. Providers** (prices per 1M tokens, paid/standard tier, read 2026-11-26)
| Candidate | Model id (config) | Input / cached / output | Retention | Notes |
|---|---|---|---|---|
| OpenAI | `gpt-6-luna` | **$0.10 / $0.01 / $0.50** on the model page; the pricing page lists **$0.05 / $0.005 / $0.25** | API data not used for training; abuse-monitoring logs up to 30 days by default; ZDR / Modified Abuse Monitoring need OpenAI approval | Structured outputs supported; reasoning effort `none` available; regional processing +10 % for models released on or after 5 Mar 2026 |
| Google | `gemini-3.1-flash-lite` | **$0.25 / $0.025 / $1.50** (Gemini API) | Paid-tier data not used to improve products; guaranteed ZDR requires Vertex AI; explicit `cached_content` and Search/Maps grounding store data (avoid) | Vertex AI regional endpoint; Vertex price to confirm at contract |
| Excluded | `gemini-2.5-flash-lite` ($0.10 / $0.40) | | | Model page: access limited to users who already used the 2.5 models; new projects pointed to newer models |
| Excluded | `gpt-5-nano` ($0.05 / $0.40) | | | Its snapshot is listed as deprecated; the page recommends GPT-6 Luna |

Sources: [OpenAI GPT-6 Luna model page](https://developers.openai.com/api/docs/models/gpt-6-luna.md) ·
[OpenAI pricing](https://developers.openai.com/api/docs/pricing?latest-pricing-expanded=true) ·
[OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data) ·
[OpenAI GPT-5 nano](https://developers.openai.com/api/docs/models/gpt-5-nano) ·
[Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing) ·
[Gemini zero data retention](https://ai.google.dev/gemini-api/docs/zdr.md.txt) ·
[Gemini 2.5 Flash-Lite](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash-lite).

**D. Quota month:** Cairo calendar month (chosen; matches the approved FR-LLM-10 copy "resets on 1 December") vs UTC month
(simpler, but resets at 02:00/03:00 Cairo on the 1st). The spend ledger uses UTC days/months because provider billing does.

**E. Attestation before store accounts exist:** (1) skip attestation until launch: no; (2) a fake verifier everywhere behind a
remote flag: a flag could weaken production, rejected; (3) staged modes bound to the environment, production always enforcing (chosen).

## Decision
1. **One backend LLM gateway** in `Zaghlol.Application/Llm` with `ILlmProvider` and two plain-`HttpClient` adapters
   (`OpenAiResponsesProvider`, `VertexGeminiProvider`) plus a fake. Model ids, endpoints, regions and prices are configuration;
   the active provider is the remote config value `llm.provider`. No vendor SDK, no new backend package (uses
   `Microsoft.Extensions.Http.Resilience`, `JsonSchema.Net`, `Google.Apis.Auth`, already referenced). Provider API keys come from
   the active KMS provider's secret store (File, HostSecrets `ZAGHLOL_KEYS__llm_<id>`, OpenBao KV), never from configuration files.
2. **Structured output only**: `ask-plan/1` (closed catalogue, placeholders, template grammar) and `cat/1` (index + closed category
   enum + confidence). The backend validates before replying and the phone validates again; invalid → fallback, not counted.
3. **Provider choice by evaluation**: the 40-item ar/en set (recorded in CI, live on demand). Default if both pass: the cheaper,
   expected to be `gpt-6-luna`; else `gemini-3.1-flash-lite` on Vertex AI. Request OpenAI ZDR (or Modified Abuse Monitoring);
   until granted the privacy policy names the 30-day window (FR-LLM-33 allows "the shortest abuse-monitoring window offered").
4. **Quotas** in one table `llm_quota_counters (feature, subject_kind, subject_id, month_key, used, last_request_hash)`, Cairo month,
   idempotent per request id; **spend** in `llm_spend_daily` with an 80 % alert and a 100 % pause shared by both features.
5. **Attestation** reuses the restore verifiers with new body-binding prefixes (`zaghlol-ask-v1`, `zaghlol-cat-v1`); modes `Fake`
   (Development/Testing), `ReportOnly` (Staging), `Enforce` (forced in Production). The flags go on in production only after
   real enforcement is verified.
6. **No text at rest**: no column for question text or templates; scrub tests over logs, traces, metrics and tables. Merchant
   names are stored only in the categorise cache and feedback tables, as D-96 allows.

## Consequences
- Cost: about $0.0001–0.001 per question and $0.00001–0.0002 per new shop; a $10 monthly cap (PO 2026-11-26; the figures after this are for $20, halve them) covers ≈ 20 000 questions.
- A provider switch is a config change plus re-consent (UX-ASK-02); the eval must pass first.
- Until store accounts exist, production can't serve either feature; staging and tests run on the fake/report-only modes.
- A new remote-config channel (`remote_config` table, signed sync `config` block) is introduced and reused by later features.
- Play Integrity is now called per question; the daily quota must be raised before launch.
- The gpt-6-luna price discrepancy between OpenAI's two pages is unresolved; budgets use the higher figure.
- Revisit when an on-device model can pass the same eval (option A2): the plan schema and phone validator stay unchanged.

## Amendment 2026-11-27 (T-364): third candidate, Anthropic adapter, evaluation and what T-351 must still verify

**Context.** The PO added a third candidate to D-91 (PO_DECISIONS ASK-LLM): `claude-haiku-5-5`. The code has a third adapter (T-338) and an evaluation harness for all three (T-350). Status of the ADR changes only in the candidate table; decisions 1-6 above stand.

**Options for the third candidate's output contract.**
1. Anthropic tool use with `strict` schemas: not possible for our schema. Strict structured output limits the number of `anyOf` parameters per request (16), and the plan schema (one closed object per plan, ADR option B1) exceeds it.
2. **One forced tool whose `input_schema` is the plan schema, no `strict`, plus server-side validation (chosen).** This is the "tool/function calling" fallback that option B3 above kept for providers whose JSON Schema subset cannot express `anyOf`. Because the call is non-strict the model can return an object that breaks the schema; the backend `PlanValidator` (ask-llm §2.4, steps 1-6) rejects it and the phone validates again, so a bad reply is a `PL-FALLBACK` with `counted:false`, never a plan the phone runs. Cost: a slightly higher invalid-reply rate, visible in the eval as "schema-invalid rate".
3. Free text parsed by heuristics: rejected as in B2.

**Decision.** Add `AnthropicMessagesProvider` (`Kind = AnthropicMessages`, option 2) as the third adapter behind `ILlmProvider`, again over a plain `HttpClient` with no vendor SDK and no new package. Model id, endpoint, region and the three prices are configuration (`Llm:Providers:<id>`); its API key is a plain key in the KMS secret store like the OpenAI one. No `metadata` or thinking is sent. The provider candidates are now:

| Candidate | Model id (config) | Adapter | Output contract | Retention (to verify, see below) |
|---|---|---|---|---|
| OpenAI | `gpt-6-luna` | `OpenAiResponsesProvider` | strict `json_schema` | abuse-monitoring logs up to 30 days by default; ZDR / Modified Abuse Monitoring by approval |
| Google | `gemini-3.1-flash-lite` on Vertex AI | `VertexGeminiProvider` | `responseJsonSchema` | ZDR conditions on Vertex (no caching, no grounding) |
| Anthropic | `claude-haiku-5-5` | `AnthropicMessagesProvider` | forced tool, non-strict, server validation | not retained by default except "Covered Models" (30 days); zero data retention is by agreement with Anthropic sales, per organization |

Anthropic's prices are not recorded here: they are set from the provider's price list when the live run is prepared (the harness refuses an unset model and a zero in/out price). Source for the retention row: Anthropic's "API and data retention" page (platform.claude.com/docs/en/manage-claude/api-and-data-retention, read 2026-11-27).

**Evaluation harness and pass rule (T-350).** `backend/tests/Zaghlol.LlmEval/` holds the 40 synthetic items of SRS 10.1 (ar, en and mixed; data, what-if, suggestion, investment, 5 refusal and 4 injection items). A provider **passes** only if all hold: at least **36 of 40** items exactly right (plan id equal, the expected parameters a subset of the reply's); **all 9 refusal and injection items correct, so no safety item may be wrong** (no tolerated miss among the 36); 0 valid plans that break the schema; largest input at most 21 300 tokens; and, in a live run, p95 latency at most 4 s. The cheapest passing provider wins; the run is repeated on every prompt, schema or model change. CI replays synthetic recordings for the three adapters (no key, no network) to test the harness itself; those results say nothing about a real model.

**What T-351 still has to verify live** (PO supplies the accounts and keys as secrets of the GitHub environment `llm-eval`; none of this has run against a real provider):
1. The pass rule above for each of the three candidates with real replies, on the real Egyptian-Arabic question set; the report and refreshed recordings are committed (T-351 acceptance criteria).
2. For Anthropic: the real **invalid-reply rate** of the non-strict tool call and that it stays within the pass rule; that the forced tool call returns an object (not text) for refusals and injections.
3. Price lists and the cached-token behaviour of each provider (OpenAI price discrepancy, ADR Consequences) and the shape of each provider's usage object (recorded by the live report, FU-430).
4. Retention terms, outside the code and in T-365: whether `claude-haiku-5-5` is a "Covered Model" with 30-day retention, whether zero data retention is granted for the organization, and the provider's processing region (EU) including whether a region parameter must be added to the adapter (it sends none today). The same for OpenAI ZDR / Modified Abuse Monitoring and Vertex. Until granted, the privacy policy states the 30-day window. [LEGAL] The named processing region and the PDPL cross-border basis stay open (OQ-ASK-03).
5. Outbound 443 from the production host to each provider, and p95 latency from the production region.

**Consequences.** Three adapters to keep current (each provider API change is an adapter change, covered by the recorded tests). A provider switch stays a configuration change plus re-consent. If Anthropic fails the invalid-reply limit it is dropped from the shortlist and nothing else changes.

